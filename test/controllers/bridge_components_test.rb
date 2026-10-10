require "test_helper"

# The pages carry the hooks the app's bridge components look for: a form's
# submit moves to the navigation bar, a document's overflow becomes a native
# menu, the theme is told to the native chrome, and Print becomes a share
# sheet. Each hook is plain data; the native side decides what to do with it.
class BridgeComponentsTest < ActionDispatch::IntegrationTest
  NATIVE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) Partita Doppia iOS/0.1.0 Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu theme share];"

  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @bank  = create_bank_account(@org, name: "Checking")
    Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6812")
    @org.settings.update!(receivable_account: @ar, bank_account: @bank)
    @invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
  end

  test "a document form names its submit for the navigation bar" do
    get new_invoice_path, headers: { "User-Agent" => NATIVE_UA }
    assert_select "form[data-controller~='bridge--form'][data-bridge-submit-title='Save draft']"
    get edit_invoice_path(@invoice), headers: { "User-Agent" => NATIVE_UA }
    assert_select "form[data-controller~='bridge--form'][data-bridge-submit-title='Update invoice']"
    get new_expense_path, headers: { "User-Agent" => NATIVE_UA }
    assert_select "form[data-controller~='bridge--form'][data-bridge-submit-title='Record expense']"
  end

  test "a document's overflow is a menu the app can draw natively" do
    get invoice_path(@invoice), headers: { "User-Agent" => NATIVE_UA }
    assert_select "[data-controller~='bridge--menu']" do
      assert_select "[data-bridge--menu-target=item][data-bridge-title='Print / PDF']"
      assert_select "[data-bridge--menu-target=item][data-bridge-title='Void'][data-bridge-destructive]"
      assert_select "[data-bridge--menu-target=item][data-bridge-title='Delete'][data-bridge-destructive]"
    end
  end

  test "the page tells the app its theme, and Print offers the PDF to share" do
    get invoice_path(@invoice), headers: { "User-Agent" => NATIVE_UA }
    assert_select "html[data-controller~='bridge--theme'][data-theme=dark]"
    assert_select "a[data-controller~='bridge--share'][data-bridge-url=?]", print_invoice_path(@invoice, format: :pdf)
  end

  test "a list's primary action is a button the app can put in the navigation bar" do
    get invoices_path, headers: { "User-Agent" => NATIVE_UA }
    assert_select "a.page-primary[data-controller~='bridge--button']", text: "New invoice"
    get expenses_path, headers: { "User-Agent" => NATIVE_UA }
    assert_select "a.page-primary[data-controller~='bridge--button']", text: "New expense"
  end
end
