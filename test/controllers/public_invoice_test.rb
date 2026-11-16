require "test_helper"

# The page a share link opens: the live invoice and its PDF, for anyone holding
# the token and nobody else. No sign-in, no way into the app, and one answer
# for every link that doesn't work.
class PublicInvoiceTest < ActionDispatch::IntegrationTest
  setup do
    @org   = organizations(:one)
    Organization.where.not(id: @org.id).destroy_all
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @org.settings.update!(receivable_account: @ar)
    @invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    @token   = @invoice.start_sharing!.token
  end

  test "the link opens the invoice without signing in" do
    get public_invoice_path(@token)
    assert_response :success
    assert_select "h1", text: /Invoice/
    assert_select "body", text: /#{@invoice.invoice.number}/
    assert_select "body", text: /Acme/
    assert_select "body", text: /#{Regexp.escape(@org.name)}/
    assert_select "body", text: /100\.00/
    assert_select "a[href=?]", public_invoice_path(@token, format: :pdf), text: "Download PDF"
  end

  test "the page is the invoice and nothing else: no app chrome, no way in, nothing from elsewhere" do
    get public_invoice_path(@token)
    assert_select ".app-nav, .app-titlebar, .app-statusbar, nav", count: 0
    assert_select "a[href^='/']" do |links|
      assert_equal [ public_invoice_path(@token, format: :pdf) ], links.map { |a| a["href"] }.uniq
    end
    assert_select "form", count: 0
    assert_select "script[src], link[href^='http'], img[src^='http']", count: 0
    assert_no_match(/History|Record payment|Edit/, response.body)
  end

  test "it tells browsers, caches and search engines to keep it to themselves" do
    get public_invoice_path(@token)
    assert_match(/noindex/, response.headers["X-Robots-Tag"])
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_match(/no-store/, response.headers["Cache-Control"])
    assert_select "meta[name=robots][content*=noindex]"
  end

  test "it is live: an edit and a payment show up on the same link" do
    bank = create_bank_account(@org, name: "Checking", code: "1000")
    @invoice.payments.create!(organization: @org, amount: 40, paid_on: Date.current, bank_account: bank)
    get public_invoice_path(@token)
    assert_select ".totals", text: /Paid/
    assert_select "body", text: /60\.00/

    @invoice.payments.create!(organization: @org, amount: 60, paid_on: Date.current, bank_account: bank)
    get public_invoice_path(@token)
    assert_response :success, "a paid invoice keeps its link"
    assert_select ".paid-mark", text: /Paid/i
  end

  test "the PDF comes down the same link" do
    get public_invoice_path(@token, format: :pdf)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF-")
    assert_match(/no-store/, response.headers["Cache-Control"])
  end

  test "every link that doesn't work gets the same 404" do
    get public_invoice_path("nosuchtokennosuchtoken00")
    assert_response :not_found
    not_found = response.body

    dead = lambda do |why, token = @token|
      %i[html pdf].each do |format|
        get public_invoice_path(token, format: (format unless format == :html))
        assert_response :not_found, "#{why} (#{format})"
        assert_equal not_found, response.body, "#{why} (#{format}) says the same as an unknown token"
      end
    end

    rolled_away = @token
    @token = @invoice.roll_share!.token
    dead.call("a rolled-away token", rolled_away)

    travel(1.year + 1.day) { dead.call("an expired link") }

    get public_invoice_path(@token)
    assert_response :success

    @invoice.stop_sharing!
    dead.call("a stopped link")

    token = @invoice.start_sharing!.token
    @invoice.share.document.update_columns(state: "draft")
    dead.call("a draft", token)
    @invoice.update_columns(state: "approved", voided_at: Time.current)
    dead.call("a voided invoice", token)
  end

  test "the invoice id is no way in" do
    get "/i/#{@invoice.id}"
    assert_response :not_found
  end

  test "the token stays out of the log" do
    log = StringIO.new
    Rails.logger.broadcast_to(sink = ActiveSupport::Logger.new(log))
    get public_invoice_path(@token)
    get public_invoice_path(@token, format: :pdf)
    assert_response :success
    assert_match(%r{/i/\[FILTERED\]}, log.string)
    assert_no_match(/#{@token}/, log.string)
  ensure
    Rails.logger.stop_broadcasting_to(sink)
  end

  test "the signed-in print page is unchanged by sharing its markup" do
    sign_in_as_launchpad_user(@org)
    get print_invoice_path(@invoice)
    assert_response :success
    assert_select ".doc .invoice-header h1", text: /Invoice/
    assert_select "a", text: "Email to customer"
  end
end
