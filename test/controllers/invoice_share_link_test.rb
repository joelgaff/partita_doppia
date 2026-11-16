require "test_helper"

# The invoice page makes, shows, rolls and stops the invoice's share link.
# Nothing makes one but the button.
class InvoiceShareLinkTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @org.settings.update!(receivable_account: @ar)
    @invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    @section = "##{ActionView::RecordIdentifier.dom_id(@invoice, :share)}"
  end

  def link_field = "#{@section} input[readonly][value=?]"

  test "an approved invoice offers to make a link, and has none until asked" do
    get invoice_path(@invoice)
    assert_select "#{@section} form[action=?][method=post]", invoice_share_path(@invoice) do
      assert_select "button", text: "Create link"
      assert_select "input[name=_method]", count: 0
    end
    assert_select "#{@section} input[readonly]", count: 0
    assert_nil @invoice.reload.share
  end

  test "creating a link shows it, with when it expires and how to roll or stop it" do
    post invoice_share_path(@invoice)
    assert_redirected_to invoice_path(@invoice)
    follow_redirect!
    share = @invoice.reload.share
    assert_select link_field, public_invoice_url(share.token)
    assert_select "#{@section} button", text: "Copy"
    assert_select @section, text: /Expires #{share.expires_at.strftime('%b %-d, %Y')}/
    assert_select "#{@section} form[action=?]", invoice_share_path(@invoice), count: 2
    assert_select "#{@section} input[name=_method][value=patch]"
    assert_select "#{@section} input[name=_method][value=delete]"
    assert_select "#{@section} button", text: "Roll link"
    assert_select "#{@section} button", text: "Stop sharing"
    assert_select "#{@section} button", text: "Create link", count: 0

    get public_invoice_path(share.token)
    assert_response :success
  end

  test "creating twice keeps the one link" do
    post invoice_share_path(@invoice)
    token = @invoice.reload.share.token
    post invoice_share_path(@invoice)
    assert_equal token, @invoice.reload.share.token
  end

  test "rolling swaps the link and the old one stops working" do
    post invoice_share_path(@invoice)
    old = @invoice.reload.share.token
    patch invoice_share_path(@invoice)
    assert_redirected_to invoice_path(@invoice)
    fresh = @invoice.reload.share.token
    assert_not_equal old, fresh
    follow_redirect!
    assert_select link_field, public_invoice_url(fresh)
    get public_invoice_path(old)
    assert_response :not_found
  end

  test "stopping takes the link away and offers to make one again" do
    post invoice_share_path(@invoice)
    token = @invoice.reload.share.token
    delete invoice_share_path(@invoice)
    assert_redirected_to invoice_path(@invoice)
    follow_redirect!
    assert_nil @invoice.reload.share
    assert_select "#{@section} button", text: "Create link"
    get public_invoice_path(token)
    assert_response :not_found

    delete invoice_share_path(@invoice)   # nothing to stop: no error, no history line
    assert_redirected_to invoice_path(@invoice)
    assert_equal 1, @invoice.events.where(action: "share_stopped").count
  end

  test "over Turbo the section is replaced in place" do
    post invoice_share_path(@invoice), as: :turbo_stream
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=?]", @section.delete_prefix("#") do
      assert_select "template input[readonly][value=?]", public_invoice_url(@invoice.reload.share.token)
    end

    delete invoice_share_path(@invoice), as: :turbo_stream
    assert_select "turbo-stream[action=replace][target=?] template button", @section.delete_prefix("#"), text: "Create link"
  end

  test "an expired link reads as none" do
    post invoice_share_path(@invoice)
    travel(1.year + 1.day) do
      sign_in_as_launchpad_user(@org)
      get invoice_path(@invoice)
      assert_select "#{@section} input[readonly]", count: 0
      assert_select "#{@section} button", text: "Create link"
    end
  end

  test "a draft offers nothing and can't be shared; approving it brings the offer" do
    @invoice.unapprove!
    get invoice_path(@invoice)
    assert_select "#{@section} button", count: 0

    post invoice_share_path(@invoice)
    assert_redirected_to invoice_path(@invoice)
    assert_match(/approve it/i, flash[:alert])
    assert_nil @invoice.reload.share

    post approve_invoice_path(@invoice), as: :turbo_stream
    assert_select "turbo-stream[action=replace][target=?] template button", @section.delete_prefix("#"), text: "Create link"
  end

  test "voiding over Turbo takes the link off the page" do
    post invoice_share_path(@invoice)
    post void_invoice_path(@invoice), as: :turbo_stream
    assert_select "turbo-stream[action=replace][target=?]", @section.delete_prefix("#") do
      assert_select "template input[readonly]", count: 0
      assert_select "template button", count: 0
    end
  end

  test "only invoices, and only this organisation's" do
    payable = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    rent    = Plutus::Expense.create!(tenant: @org, name: "Rent", code: "6000")
    bill    = create_bill(@org, vendor: "Landlord", amount: 50, category: rent, payable: payable)
    post "/invoices/#{bill.id}/share"
    assert_response :not_found
    assert_nil bill.reload.share
  end

  test "making a link takes signing in" do
    cookies.delete(Ee::Jwt::COOKIE_NAME.to_s)
    post invoice_share_path(@invoice)
    assert_response :redirect
    assert_no_match(/#{Regexp.escape(invoice_path(@invoice))}\z/, response.location)
    assert_nil @invoice.reload.share
  end

  test "emailing an invoice makes no link" do
    post send_email_invoice_path(@invoice), params: { to: "billing@acme.example" }
    assert_nil @invoice.reload.share
  end
end
