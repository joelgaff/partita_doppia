require "test_helper"

# A mailing address in Settings puts "Make payments to … and send to …" on
# the invoice, its print view and its PDF. No address, no line.
class InvoiceMailingAddressTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @org.settings.update!(receivable_account: @ar)
    @invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
  end

  test "the line appears once an address is set, with the organisation's name and the address's lines" do
    get invoice_path(@invoice)
    assert_select ".payment-instructions", 0
    get print_invoice_path(@invoice)
    assert_select ".payment-instructions", 0
    assert_nil InvoicePdf.new(@invoice).payment_instructions

    @org.settings.update!(mailing_address: "PO Box 12\nTraverse City, MI 49684")
    get invoice_path(@invoice)
    assert_select ".payment-instructions", text: /Make payments to #{Regexp.escape(@org.name)} and send to PO Box 12,? Traverse City, MI 49684/
    get print_invoice_path(@invoice)
    assert_select ".payment-instructions", text: /Make payments to #{Regexp.escape(@org.name)}/
    assert_select ".payment-instructions br", 1, "the address keeps its lines"
    assert_equal "Make payments to #{@org.name} and send to:\nPO Box 12\nTraverse City, MI 49684", InvoicePdf.new(@invoice).payment_instructions
    assert InvoicePdf.new(@invoice).render.start_with?("%PDF"), "the PDF still renders with the line"
  end
end
