require "test_helper"

# Emailing an invoice can send a copy to an address of your own: the one in
# Settings by default, changeable on the form, off with one untick.
class InvoiceCopyToMeTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @org.settings.update!(receivable_account: @ar, email_copy_to: "me@enduranceevolution.example")
    @invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
  end

  test "the form offers a copy to the Settings address, ticked, and sending honours it" do
    get email_invoice_path(@invoice)
    assert_select "input[type=checkbox][name=copy_to_me][checked]"
    assert_select "input[name=copy_to][value=?]", "me@enduranceevolution.example"

    perform_enqueued_jobs do
      post send_email_invoice_path(@invoice), params: { to: "billing@acme.example", copy_to_me: "1", copy_to: "me@enduranceevolution.example" }
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "billing@acme.example" ], mail.to
    assert_equal [ "me@enduranceevolution.example" ], mail.bcc
    assert_match(/copy to me@enduranceevolution\.example/, @invoice.events.last.detail_lines.join(" · "))
  end

  test "unticked, no copy; a different address can be typed; with no Settings address the box starts unticked" do
    perform_enqueued_jobs do
      post send_email_invoice_path(@invoice), params: { to: "billing@acme.example", copy_to: "me@enduranceevolution.example" }
    end
    assert_empty ActionMailer::Base.deliveries.last.bcc.to_a

    perform_enqueued_jobs do
      post send_email_invoice_path(@invoice), params: { to: "billing@acme.example", copy_to_me: "1", copy_to: "other@enduranceevolution.example" }
    end
    assert_equal [ "other@enduranceevolution.example" ], ActionMailer::Base.deliveries.last.bcc

    @org.settings.update!(email_copy_to: nil)
    get email_invoice_path(@invoice)
    assert_select "input[type=checkbox][name=copy_to_me]:not([checked])"
  end
end
