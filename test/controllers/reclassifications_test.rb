require "test_helper"

# The reclassify page: choose an account, where its lines should go and the
# dates; see what would move; then move it.
class ReclassificationsTest < ActionDispatch::IntegrationTest
  setup do
    @org    = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @bank   = create_bank_account(@org, name: "Checking", code: "1000")
    @travel = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6817")
    @reimb  = Plutus::Expense.create!(tenant: @org, name: "Reimbursable Expenses", code: "6900")
    @gone   = Plutus::Expense.create!(tenant: @org, name: "Old Bucket", code: "6999", archived_at: Time.current)
    @march  = create_expense(@org, amount: 40, category: @travel, bank_account: @bank, vendor: "Delta", date: Date.new(2026, 3, 10))
    @april  = create_expense(@org, amount: 60, category: @travel, bank_account: @bank, vendor: "Hertz", date: Date.new(2026, 4, 5))
  end

  def chosen(extra = {}) = { from_account_id: @travel.id, to_account_id: @reimb.id, from: "2026-04-01", to: "2026-04-30" }.merge(extra)

  test "the chart and the general ledger lead to it" do
    get accounts_path
    assert_select "a[href=?]", new_reclassification_path, text: "Reclassify"
    get reports_general_ledger_path(account_id: @travel.id, from: "2026-04-01", to: "2026-04-30")
    assert_select "a[href=?]", new_reclassification_path(from_account_id: @travel.id, from: "2026-04-01", to: "2026-04-30")
  end

  test "it starts with a form and nothing to confirm" do
    get new_reclassification_path
    assert_response :success
    assert_select "form[method=get][action=?]", new_reclassification_path do
      assert_select "select[name=from_account_id] option", text: /6817 — Travel/
      assert_select "select[name=from_account_id] option", text: /Old Bucket/, count: 1   # history can be moved off an archived account
      assert_select "select[name=to_account_id] option", text: /Old Bucket/, count: 0
      assert_select "input[type=date][name=from]"
      assert_select "input[type=date][name=to]"
    end
    assert_select "form[method=post][action=?]", reclassification_path, count: 0
  end

  test "a choice shows what would move, and the button to move it" do
    get new_reclassification_path(chosen)
    assert_response :success
    assert_select "table.data-table tbody tr", count: 1
    assert_select "table.data-table a[href=?]", expense_path(@april)
    assert_select "table.data-table", text: /60\.00/
    assert_select "form[method=post][action=?]", reclassification_path do
      assert_select "input[type=hidden][name='reclassification[from_account_id]'][value=?]", @travel.id.to_s
      assert_select "input[type=hidden][name='reclassification[to_account_id]'][value=?]", @reimb.id.to_s
      assert_select "input[type=hidden][name='reclassification[from]'][value='2026-04-01']"
      assert_select "input[type=hidden][name='reclassification[to]'][value='2026-04-30']"
      assert_select "input[type=submit][value='Move 1 line'][data-turbo-confirm='Move 1 line from Travel to Reimbursable Expenses?']"
    end
  end

  test "each line names the customer: who a cost is billed to, who an invoice is for" do
    northwind = @org.contacts.create!(name: "Northwind", kind: "customer")
    acme      = @org.contacts.create!(name: "Acme", kind: "customer")
    ar        = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    billed    = create_expense(@org, amount: 15, category: @travel, bank_account: @bank, vendor: "Uber", date: Date.new(2026, 4, 6), billable_to: northwind)
    invoice   = create_invoice(@org, contact: acme, amount: 80, receivable: ar, revenue: @travel, date: Date.new(2026, 4, 7))

    get new_reclassification_path(chosen)
    assert_select "table.data-table thead th", text: "Customer"
    rows = css_select("table.data-table tbody tr")
    assert_equal [ "", "Northwind", "Acme" ], rows.map { |r| r.css("td.reclass-customer").text.strip }
    assert_select "td.reclass-customer a[href=?]", contact_path(northwind)
    assert_select "tfoot th[colspan='4']"
  end

  test "a customer can be chosen, narrows the preview, and is carried into the move" do
    ironman = @org.contacts.create!(name: "IRONMAN", kind: "customer")
    @org.contacts.create!(name: "Delta Vendor", kind: "vendor")
    billed  = create_expense(@org, amount: 15, category: @travel, bank_account: @bank, vendor: "Chipotle", date: Date.new(2026, 4, 6), billable_to: ironman)

    get new_reclassification_path
    assert_select "form[method=get] select[name=customer_id]" do
      assert_select "option", text: "Any customer"
      assert_select "option[value=?]", ironman.id.to_s, text: "IRONMAN"
      assert_select "option", text: "Delta Vendor", count: 0
    end

    get new_reclassification_path(chosen(customer_id: ironman.id))
    assert_select "form[method=get] select[name=customer_id] option[selected][value=?]", ironman.id.to_s
    assert_select "table.data-table tbody tr", count: 1
    assert_select "table.data-table a[href=?]", expense_path(billed)
    assert_select "form[action=?] input[type=hidden][name='reclassification[customer_id]'][value=?]", reclassification_path, ironman.id.to_s
    assert_select "input[type=submit][data-turbo-confirm=?]", "Move 1 line for IRONMAN from Travel to Reimbursable Expenses?"

    post reclassification_path, params: { reclassification: chosen(customer_id: ironman.id) }
    assert_equal "1 line for IRONMAN moved from Travel to Reimbursable Expenses.", flash[:notice]
    assert_equal @reimb,  billed.reload.line_items.first.account
    assert_equal @travel, @april.reload.line_items.first.account

    get new_reclassification_path(chosen(customer_id: ironman.id, from: "2025-01-01", to: "2025-01-31"))
    assert_select ".empty-state", text: /Nothing on Travel for IRONMAN/
  end

  test "nothing in range says so, with nothing to press" do
    get new_reclassification_path(chosen(from: "2025-01-01", to: "2025-01-31"))
    assert_select ".empty-state", text: /Nothing on Travel/
    assert_select "form[method=post][action=?]", reclassification_path, count: 0
  end

  test "a bad choice explains itself" do
    get new_reclassification_path(chosen(to_account_id: @travel.id))
    assert_response :success
    assert_select ".form-errors", text: /different account/
    assert_select "form[method=post][action=?]", reclassification_path, count: 0
  end

  test "confirming moves the lines and reports back" do
    post reclassification_path, params: { reclassification: chosen }
    assert_redirected_to reports_general_ledger_path(account_id: @reimb.id, from: "2026-04-01", to: "2026-04-30")
    assert_equal "1 line moved from Travel to Reimbursable Expenses.", flash[:notice]
    assert_equal @reimb,  @april.reload.line_items.first.account
    assert_equal @travel, @march.reload.line_items.first.account
  end

  test "a bad confirmation moves nothing" do
    post reclassification_path, params: { reclassification: chosen(to_account_id: @gone.id) }
    assert_response :unprocessable_entity
    assert_equal @travel, @april.reload.line_items.first.account
  end

  test "another organisation's account is not a choice" do
    theirs = Plutus::Expense.create!(tenant: Organization.create!(name: "Elsewhere"), name: "Theirs", code: "6817")
    post reclassification_path, params: { reclassification: chosen(from_account_id: theirs.id) }
    assert_response :unprocessable_entity
  end
end
