require "test_helper"

# The find and recode page: find lines, tick the ones you mean, then move
# them to another account, bill them to a customer, or both.
class RecodingsTest < ActionDispatch::IntegrationTest
  setup do
    @org    = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @bank   = create_bank_account(@org, name: "Checking", code: "1000")
    @ar     = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @travel = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6817")
    @reimb  = Plutus::Expense.create!(tenant: @org, name: "Reimbursable Expenses", code: "6900")
    @gone   = Plutus::Expense.create!(tenant: @org, name: "Old Bucket", code: "6999", archived_at: Time.current)
    @ironman = @org.contacts.create!(name: "IRONMAN", kind: "customer")
    @march  = create_expense(@org, amount: 40, category: @travel, bank_account: @bank, vendor: "Delta", date: Date.new(2026, 3, 10))
    @april  = create_expense(@org, amount: 60, category: @travel, bank_account: @bank, vendor: "Hertz", date: Date.new(2026, 4, 5))
  end

  def found(extra = {}) = { account_id: @travel.id, from: "2026-04-01", to: "2026-04-30" }.merge(extra)
  def key(document)     = "line_item_#{document.line_items.first.id}"
  def apply(extra)      = post(recoding_path, params: { recoding: found(extra) })

  test "the chart and the general ledger lead to it, and the old address still does" do
    get accounts_path
    assert_select "a[href=?]", new_recoding_path, text: "Find and recode"
    get reports_general_ledger_path(account_id: @travel.id, from: "2026-04-01", to: "2026-04-30")
    assert_select "a[href=?]", new_recoding_path(account_id: @travel.id, from: "2026-04-01", to: "2026-04-30"), text: "Recode these"
    get "/reclassification/new?from=2026-04-01"
    assert_redirected_to "/recoding/new?from=2026-04-01"
  end

  test "it starts with a form to find by account, dates, customer and vendor, and nothing to apply" do
    get new_recoding_path
    assert_response :success
    assert_select "h1", text: "Find and recode"
    assert_select "form[method=get][action=?]", new_recoding_path do
      assert_select "select[name=account_id] option", text: /6817 — Travel/
      assert_select "select[name=account_id] option", text: /Old Bucket/, count: 1   # history can be found on an archived account
      assert_select "input[type=date][name=from]"
      assert_select "input[type=date][name=to]"
      assert_select "select[name=customer_id]" do
        assert_select "option", text: "Any customer"
        assert_select "option[value=none]", text: "No customer yet"
        assert_select "option[value=?]", @ironman.id.to_s, text: "IRONMAN"
        assert_select "option", text: "Hertz", count: 0
      end
      assert_select "select[name=vendor_id]" do
        assert_select "option", text: "Any vendor"
        assert_select "option", text: "Hertz"
        assert_select "option", text: "IRONMAN", count: 0
      end
    end
    assert_select "form[method=post][action=?]", recoding_path, count: 0
  end

  test "what is found is listed with a tick each, the customer, and what can be done to it" do
    billed  = create_expense(@org, amount: 15, category: @travel, bank_account: @bank, vendor: "Uber", date: Date.new(2026, 4, 6), billable_to: @ironman)
    invoice = create_invoice(@org, contact: @ironman, amount: 80, receivable: @ar, revenue: @travel, date: Date.new(2026, 4, 7))

    get new_recoding_path(found)
    assert_response :success
    assert_select "form[method=post][action=?][data-controller=checklist]", recoding_path do
      assert_select "input[type=hidden][name='recoding[account_id]'][value=?]", @travel.id.to_s
      assert_select "input[type=hidden][name='recoding[from]'][value='2026-04-01']"
      assert_select "input[type=hidden][name='recoding[to]'][value='2026-04-30']"
      assert_select "thead input[type=checkbox][data-checklist-target=all]"
      assert_select "tbody tr", count: 3
      assert_select "tbody input[type=checkbox][name='recoding[line_keys][]'][checked]", count: 3
      assert_select "tbody input[type=checkbox][value=?]", key(@april)
      assert_select "tbody a[href=?]", expense_path(@april)
      assert_select "thead th", text: "Customer"
      assert_equal [ "", "IRONMAN", "IRONMAN" ], css_select("tbody td.recode-customer").map { |td| td.text.strip }
      assert_select "td.recode-customer a[href=?]", contact_path(@ironman)
      assert_select "select[name='recoding[to_account_id]']" do
        assert_select "option", text: "Leave the account as it is"
        assert_select "option", text: /Reimbursable Expenses/
        assert_select "option", text: /Old Bucket/, count: 0
      end
      assert_select "select[name='recoding[bill_to]']" do
        assert_select "option", text: "Leave billing as it is"
        assert_select "option[value=none]", text: "Not billable"
        assert_select "option[value=?]", @ironman.id.to_s, text: "IRONMAN"
      end
      assert_select "input[type=submit][data-checklist-target=submit]"
    end
  end

  test "a cost already on an invoice says so; one of several lines says the flag is the document's" do
    @april.update!(billable_to: @ironman)
    invoice = @org.documents.create!(contact: @ironman, date: Date.new(2026, 4, 28), documentable: Invoice.new(due_date: Date.new(2026, 5, 28), receivable_account: @ar, number: "INV-9"),
      line_items_attributes: [ { description: "Car hire", quantity: 1, unit_amount: 60, account_id: @reimb.id, rebills_document_id: @april.id } ])
    @org.documents.create!(contact: @april.contact, date: Date.new(2026, 4, 9), documentable: Expense.new(vendor: "Hertz", bank_account: @bank),
      line_items_attributes: [ { description: "Car", quantity: 1, unit_amount: 50, account_id: @travel.id }, { description: "Fuel", quantity: 1, unit_amount: 20, account_id: @reimb.id } ])

    get new_recoding_path(found)
    assert_select "td.recode-customer", text: /IRONMAN\s+on Invoice INV-9/
    assert_select "td.recode-customer a[href=?]", invoice_path(invoice)
    assert_select "tbody td", text: /Car\s+1 of 2 lines/
  end

  test "the filters narrow what is found and stay chosen" do
    billed = create_expense(@org, amount: 15, category: @travel, bank_account: @bank, vendor: "Uber", date: Date.new(2026, 4, 6), billable_to: @ironman)
    hertz  = @org.contacts.find_by!(name: "Hertz")

    get new_recoding_path(found(customer_id: @ironman.id))
    assert_select "select[name=customer_id] option[selected][value=?]", @ironman.id.to_s
    assert_select "tbody tr", count: 1
    assert_select "tbody a[href=?]", expense_path(billed)
    assert_select "input[type=hidden][name='recoding[customer_id]'][value=?]", @ironman.id.to_s

    get new_recoding_path(found(customer_id: "none"))
    assert_select "select[name=customer_id] option[selected][value=none]"
    assert_select "tbody tr", count: 1
    assert_select "tbody a[href=?]", expense_path(@april)

    get new_recoding_path(found(vendor_id: hertz.id))
    assert_select "select[name=vendor_id] option[selected][value=?]", hertz.id.to_s
    assert_select "tbody tr", count: 1
    assert_select "input[type=hidden][name='recoding[vendor_id]'][value=?]", hertz.id.to_s
  end

  test "a type can be chosen: invoices only, or costs only, and it is carried into the apply" do
    invoice = create_invoice(@org, contact: @ironman, amount: 80, receivable: @ar, revenue: @travel, date: Date.new(2026, 4, 7))

    get new_recoding_path
    assert_select "form[method=get] select[name=kind]" do
      assert_select "option[value='']", text: "Any type"
      assert_select "option[value=invoices]", text: "Invoices only"
      assert_select "option[value=costs]", text: "Expenses and bills only"
    end

    get new_recoding_path(found(kind: "invoices"))
    assert_select "select[name=kind] option[selected][value=invoices]"
    assert_select "tbody tr", count: 1
    assert_select "tbody a[href=?]", invoice_path(invoice)
    assert_select "input[type=hidden][name='recoding[kind]'][value=invoices]"

    get new_recoding_path(found(kind: "costs"))
    assert_select "tbody tr", count: 1
    assert_select "tbody a[href=?]", expense_path(@april)

    apply(kind: "invoices", to_account_id: @reimb.id, line_keys: [ key(invoice), key(@april) ])
    assert_equal "1 line moved from Travel to Reimbursable Expenses.", flash[:notice]
    assert_equal @reimb,  invoice.reload.line_items.first.account
    assert_equal @travel, @april.reload.line_items.first.account, "ticked, but not among what was found"

    get new_recoding_path(found(kind: "invoices", from: "2025-01-01", to: "2025-01-31"))
    assert_select ".empty-state", text: /Nothing on Travel among invoices/
  end

  test "nothing found says so, with nothing to apply; a bad search explains itself" do
    get new_recoding_path(found(from: "2025-01-01", to: "2025-01-31", customer_id: @ironman.id))
    assert_select ".empty-state", text: /Nothing on Travel for IRONMAN/
    assert_select "form[method=post][action=?]", recoding_path, count: 0

    get new_recoding_path(found(from: "2026-05-01"))
    assert_select ".form-errors", text: /must not be before/
    assert_select "form[method=post][action=?]", recoding_path, count: 0
  end

  test "moving the ticked lines goes to the ledger of where they went" do
    create_expense(@org, amount: 15, category: @travel, bank_account: @bank, vendor: "Uber", date: Date.new(2026, 4, 6))
    apply(to_account_id: @reimb.id, line_keys: [ key(@april) ])
    assert_redirected_to reports_general_ledger_path(account_id: @reimb.id, from: "2026-04-01", to: "2026-04-30")
    assert_equal "1 line moved from Travel to Reimbursable Expenses.", flash[:notice]
    assert_equal @reimb,  @april.reload.line_items.first.account
    assert_equal @travel, @march.reload.line_items.first.account
    assert_equal 15, @travel.reload.balance - 40, "the unticked April line stayed"
  end

  test "billing the ticked costs comes back to the same search, and says what was skipped" do
    uber = create_expense(@org, amount: 15, category: @travel, bank_account: @bank, vendor: "Uber", date: Date.new(2026, 4, 6), billable_to: @ironman)
    @org.documents.create!(contact: @ironman, date: Date.new(2026, 4, 28), documentable: Invoice.new(due_date: Date.new(2026, 5, 28), receivable_account: @ar),
      line_items_attributes: [ { description: "Ride", quantity: 1, unit_amount: 15, account_id: @reimb.id, rebills_document_id: uber.id } ])
    northwind = @org.contacts.create!(name: "Northwind", kind: "customer")

    apply(bill_to: northwind.id, line_keys: [ key(@april), key(uber) ])
    assert_redirected_to new_recoding_path(found)
    assert_equal "1 cost now billable to Northwind. 1 already on an invoice was left alone.", flash[:notice]
    assert_equal northwind, @april.reload.billable_to
    assert_equal @ironman, uber.reload.billable_to

    apply(bill_to: "none", line_keys: [ key(@april) ])
    assert_equal "1 cost no longer billable.", flash[:notice]
    assert_nil @april.reload.billable_to
  end

  test "both at once" do
    apply(to_account_id: @reimb.id, bill_to: @ironman.id, line_keys: [ key(@april) ])
    assert_equal "1 line moved from Travel to Reimbursable Expenses. 1 cost now billable to IRONMAN.", flash[:notice]
  end

  test "nothing ticked, nothing to do, or a bad target changes nothing and keeps the page as it was" do
    apply(to_account_id: @reimb.id)
    assert_response :unprocessable_entity
    assert_select ".form-errors", text: /Tick at least one line/
    assert_select "tbody input[type=checkbox][checked]", count: 0

    apply(line_keys: [ key(@april) ])
    assert_response :unprocessable_entity
    assert_select ".form-errors", text: /Choose an account to move the lines to, a customer to bill them to, or both/
    assert_select "tbody input[type=checkbox][checked]", count: 1

    apply(to_account_id: @gone.id, line_keys: [ key(@april) ])
    assert_response :unprocessable_entity
    assert_select ".form-errors", text: /archived/
    assert_equal @travel, @april.reload.line_items.first.account
  end

  test "another organisation's account is not a choice" do
    theirs = Plutus::Expense.create!(tenant: Organization.create!(name: "Elsewhere"), name: "Theirs", code: "6817")
    post recoding_path, params: { recoding: { account_id: theirs.id, to_account_id: @reimb.id, line_keys: [ "line_item_1" ] } }
    assert_response :unprocessable_entity
  end
end
