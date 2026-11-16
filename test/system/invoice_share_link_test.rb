require "application_system_test_case"

# The share link in a real browser: made, copied, rolled and stopped without
# leaving the invoice page, and the link itself opening signed out. Desktop and phone.
class InvoiceShareLinkSystemTest < ApplicationSystemTestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @org.settings.update!(receivable_account: @ar)
    @invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    sign_in_as_launchpad_user(@org)
  end

  def share_a_link
    visit invoice_path(@invoice)
    section = "##{ActionView::RecordIdentifier.dom_id(@invoice, :share)}"
    within(section) { click_button "Create link" }
    field = find("#{section} input[readonly]")
    first_link = field.value
    assert_match %r{/i/[A-Za-z0-9]{24}\z}, first_link
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, page.evaluate_script("window.innerWidth"), "no sideways scroll"
    page.save_screenshot(ENV["SHOT"]) if ENV["SHOT"]

    within(section) { click_button "Copy" }
    assert_selector "#{section} button", text: "Copied"

    accept_confirm { within(section) { click_button "Roll link" } }
    assert_no_selector "#{section} input[value='#{first_link}']"
    rolled = find("#{section} input[readonly]").value
    assert_not_equal first_link, rolled

    visit rolled
    assert_selector "h1", text: /INVOICE/i
    assert_text "Acme"
    assert_no_selector ".app-nav"
    visit first_link
    assert_no_text "Acme"

    visit invoice_path(@invoice)
    accept_confirm { within(section) { click_button "Stop sharing" } }
    assert_selector "#{section} button", text: "Create link"
    assert_no_selector "#{section} input[readonly]"
    visit rolled
    assert_no_text "Acme"
  end

  test "on a desktop" do
    share_a_link
  end

  test "on a phone" do
    on_phone
    share_a_link
  end
end
