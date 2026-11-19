require "test_helper"

# From the chart to an account's ledger, from a ledger row to the transaction
# behind it, and the ledger itself one click from anywhere.
class AccountLedgerLinksTest < ActionDispatch::IntegrationTest
  setup do
    @org   = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @bank  = create_bank_account(@org, name: "Checking", code: "1000")
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @rent  = Plutus::Expense.create!(tenant: @org, name: "Rent", code: "6000")
    @gone  = Plutus::Expense.create!(tenant: @org, name: "Old Bucket", code: "6999", archived_at: Time.current)
    @org.settings.update!(receivable_account: @ar)
  end

  def row(account) = "tr##{ActionView::RecordIdentifier.dom_id(account)}"

  test "an account's name on the chart opens its ledger, archived ones and bank accounts too" do
    get accounts_path
    [ @rent, @gone, @bank.account ].each do |account|
      assert_select "#{row(account)} a[href=?]", reports_general_ledger_path(account_id: account.id), text: account.name
    end
    assert_select "#{row(@rent)} a[data-turbo-frame=_top]", 0   # the frame already sends its links to the whole page
  end

  test "a ledger row opens the transaction behind it; a payment's row opens what it paid" do
    expense = create_expense(@org, amount: 500, category: @rent, bank_account: @bank, vendor: "Landlord")
    invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    invoice.payments.create!(organization: @org, amount: 100, paid_on: Date.current, bank_account: @bank)

    get reports_general_ledger_path(account_id: @rent.id)
    assert_select "table.data-table tbody tr", 1
    assert_select "table.data-table tbody a[href=?]", expense_path(expense)

    get reports_general_ledger_path(account_id: @ar.id)
    assert_select "table.data-table tbody tr", 2
    assert_select "table.data-table tbody a[href=?]", invoice_path(invoice), count: 2
  end

  test "the general ledger is in the sidebar, under its own name, and off the reports page" do
    get root_path
    assert_select "nav.app-nav a[href=?]", reports_general_ledger_path, text: "General Ledger"
    assert_select ".sheet-panel a[href=?]", reports_general_ledger_path

    get reports_general_ledger_path
    assert_select "nav.app-nav a[aria-current=page]", text: "General Ledger"
    assert_select "nav.app-nav a[aria-current=page]", count: 1

    get reports_trial_balance_path
    assert_select "nav.app-nav a[aria-current=page]", text: "Reports"
    assert_select "nav.app-nav a[aria-current=page]", count: 1

    get reports_path
    assert_select "main a[href=?]", reports_general_ledger_path, count: 0
    assert_select "main a[href=?]", reports_trial_balance_path

    get menu_path
    assert_select "nav.menu-page a[href=?]", reports_general_ledger_path, text: "General Ledger"
  end
end
