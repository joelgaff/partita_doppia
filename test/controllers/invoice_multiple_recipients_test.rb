require "test_helper"

# An invoice can go to several addresses at once: typed into the one "Send to"
# field, separated by commas, and every one of them is a recipient.
class InvoiceMultipleRecipientsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @org.settings.update!(receivable_account: @ar)
    @invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
  end

  test "the form takes several addresses and says how" do
    get email_invoice_path(@invoice)
    assert_select "input[type=email][name=to][multiple]"
    assert_select ".field-help", text: /Separate multiple addresses with commas/
  end

  test "every address gets the invoice, and the history and the notice name them all" do
    perform_enqueued_jobs do
      post send_email_invoice_path(@invoice), params: { to: " billing@acme.example, ap@acme.example ;owner@acme.example,BILLING@acme.example" }
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal %w[billing@acme.example ap@acme.example owner@acme.example], mail.to
    assert_equal 1, mail.attachments.size
    assert_match(/To billing@acme\.example, ap@acme\.example, owner@acme\.example/, @invoice.events.last.detail_lines.join(" · "))
    assert_match(/billing@acme\.example, ap@acme\.example, and owner@acme\.example/, flash[:notice])
    assert @invoice.reload.invoice.sent?
  end

  test "one bad address sends nothing and hands the form back as typed" do
    assert_no_enqueued_jobs do
      post send_email_invoice_path(@invoice), params: { to: "billing@acme.example, not-an-address", subject: "Please pay", body: "Thanks" }
    end
    assert_response :unprocessable_entity
    assert_select ".flash-alert", text: /not-an-address isn't an email address/
    assert_select "input[name=to][value=?]", "billing@acme.example, not-an-address"
    assert_select "input[name=subject][value=?]", "Please pay"
    assert_select "textarea[name=body]", text: /Thanks/
    assert_not @invoice.reload.invoice.sent?
    assert_empty @invoice.events.where(action: "emailed")

    post send_email_invoice_path(@invoice), params: { to: " , " }
    assert_response :unprocessable_entity
    assert_select ".flash-alert", text: /Add an email address/
  end
end
