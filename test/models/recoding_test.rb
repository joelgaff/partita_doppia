require "test_helper"

# Find and recode: find the lines on an account (by dates, customer, vendor),
# choose among them, then move them to another account, flag their documents
# as billable to a customer, or both.
class RecodingTest < ActiveSupport::TestCase
  setup do
    @org    = organizations(:one)
    Current.organization = @org
    @bank   = create_bank_account(@org, name: "Checking", code: "1000")
    @ap     = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @ar     = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @travel = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6817")
    @reimb  = Plutus::Expense.create!(tenant: @org, name: "Reimbursable Expenses", code: "6900")
    @rent   = Plutus::Expense.create!(tenant: @org, name: "Rent", code: "6000")
    @ironman   = @org.contacts.create!(name: "IRONMAN", kind: "customer")
    @northwind = @org.contacts.create!(name: "Northwind", kind: "customer")

    @march = create_expense(@org, amount: 40, category: @travel, bank_account: @bank, vendor: "Delta", date: Date.new(2026, 3, 10))
    @april = create_expense(@org, amount: 60, category: @travel, bank_account: @bank, vendor: "Hertz", date: Date.new(2026, 4, 5))
    @bill  = create_bill(@org, amount: 25, category: @travel, payable: @ap, vendor: "Uber", date: Date.new(2026, 4, 20))
    @other = create_expense(@org, amount: 500, category: @rent, bank_account: @bank, vendor: "Landlord", date: Date.new(2026, 4, 1))
    @journal = @org.documents.create!(date: Date.new(2026, 4, 30), documentable: JournalEntry.new(narrative: "Accrue travel", lines_attributes: [
      { account_id: @travel.id, debit_amount: 15 }, { account_id: @ap.id, credit_amount: 15 } ]))
  end

  teardown { Current.reset }

  def recoding(**attrs) = Recoding.new(organization: @org, account_id: @travel.id, **attrs)
  def move(**attrs)     = recoding(to_account_id: @reimb.id, **attrs)
  def key(document)     = recoding.lines.find { |l| l.document == document }.key

  # ── Finding ───────────────────────────────────────────────────────────────

  test "it lists the lines on the account within the dates, document lines and journal lines alike" do
    r = recoding(from: "2026-04-01", to: "2026-04-30")
    assert r.valid?, "finding needs nothing to do yet"
    assert_equal [ @april, @bill, @journal ], r.lines.map(&:document)
    assert_equal 100, r.total
  end

  test "open-ended dates take everything on the account" do
    assert_equal 4, recoding.lines.size
    assert_equal 3, recoding(from: "2026-04-01").lines.size
    assert_equal 1, recoding(to: "2026-03-31").lines.size
  end

  test "a customer narrows it to their costs and their invoices; no customer yet finds the rest" do
    theirs  = create_expense(@org, amount: 30, category: @travel, bank_account: @bank, vendor: "Chipotle", date: Date.new(2026, 4, 8), billable_to: @ironman)
    create_expense(@org, amount: 20, category: @travel, bank_account: @bank, vendor: "Subway", date: Date.new(2026, 4, 9), billable_to: @northwind)
    invoice = create_invoice(@org, contact: @ironman, amount: 80, receivable: @ar, revenue: @travel, date: Date.new(2026, 4, 10))
    paid_to = create_expense(@org, amount: 12, category: @travel, bank_account: @bank, contact: @ironman, date: Date.new(2026, 4, 11))   # paid to them, not billed to them

    r = recoding(from: "2026-04-01", to: "2026-04-30", customer_id: @ironman.id)
    assert_equal @ironman, r.customer
    assert_equal [ theirs, invoice ], r.lines.map(&:document)

    none = recoding(from: "2026-04-01", to: "2026-04-30", customer_id: "none")
    assert none.valid?
    assert none.no_customer?
    assert_equal [ @april, paid_to, @bill, @journal ], none.lines.map(&:document)
  end

  test "a vendor narrows it to what was bought from them" do
    hertz = @org.contacts.find_by!(name: "Hertz")
    r = recoding(vendor_id: hertz.id)
    assert_equal hertz, r.vendor
    assert_equal [ @april ], r.lines.map(&:document)
  end

  test "finding needs an account of this organisation, known people and sane dates" do
    assert_not Recoding.new(organization: @org).valid?
    elsewhere = Organization.create!(name: "Elsewhere")
    assert_not Recoding.new(organization: @org, account_id: Plutus::Expense.create!(tenant: elsewhere, name: "Theirs", code: "6817").id).valid?
    assert_not recoding(from: "2026-05-01", to: "2026-04-01").valid?
    assert_not recoding(customer_id: elsewhere.contacts.create!(name: "IRONMAN", kind: "customer").id).valid?
    assert_not recoding(customer_id: 0).valid?
    assert_not recoding(vendor_id: 0).valid?
  end

  # ── Moving to another account ─────────────────────────────────────────────

  test "moving recodes the lines, reposts their documents, and leaves the rest alone" do
    result = move(from: "2026-04-01", to: "2026-04-30").apply!
    assert_equal 3, result.moved
    assert_equal 0, result.billed
    assert_equal 40,  @travel.reload.balance, "March stays where it was"
    assert_equal 100, @reimb.reload.balance
    assert_equal 500, @rent.reload.balance
    assert_equal @reimb, @april.reload.line_items.first.account
    assert_equal @travel, @march.reload.line_items.first.account
    assert_equal [ @reimb, @ap ], @journal.reload.journal_entry.lines.map(&:account)

    event = @april.events.newest_first.first
    assert_equal "reclassified", event.action
    assert_equal [ "1 line: 6817 Travel → 6900 Reimbursable Expenses" ], event.detail_lines
    assert_empty @march.events.where(action: "reclassified")
  end

  test "drafts move too; voided documents are left as they were" do
    draft = create_bill(@org, amount: 10, category: @travel, payable: @ap, vendor: "Lyft", date: Date.new(2026, 4, 21), state: "draft")
    @april.void!
    move(from: "2026-04-01", to: "2026-04-30").apply!
    assert_equal @reimb,  draft.reload.line_items.first.account
    assert_equal @travel, @april.reload.line_items.first.account
    assert_equal 40, @reimb.reload.balance, "the bill and the journal; a draft posts nothing"
  end

  test "only the chosen lines are touched; none chosen is an error, and stale choices are ignored" do
    result = move(line_keys: [ key(@april), "line_item_0" ]).apply!
    assert_equal 1, result.moved
    assert_equal @reimb,  @april.reload.line_items.first.account
    assert_equal @travel, @bill.reload.line_items.first.account

    r = move(line_keys: [])
    assert_not r.valid?(:apply)
    assert_match(/Tick at least one/, r.errors.full_messages.to_sentence)
    assert_raises(ActiveRecord::RecordInvalid) { r.apply! }
  end

  test "applying needs something to do, a different account, and one that is in use" do
    assert recoding.valid?
    assert_not recoding.valid?(:apply), "nothing to do"
    assert_not recoding(to_account_id: @travel.id).valid?(:apply)
    @reimb.archive!
    r = move
    assert_not r.valid?(:apply)
    assert_match(/archived/, r.errors.full_messages.to_sentence)
    assert_raises(ActiveRecord::RecordInvalid) { r.apply! }
    assert_equal @travel, @april.reload.line_items.first.account
  end

  # ── Billing to a customer ────────────────────────────────────────────────

  test "billing flags each cost for the customer, overwrites another customer, and says so in the history" do
    @bill.update!(billable_to: @northwind)
    result = recoding(from: "2026-04-01", to: "2026-04-30", bill_to: @ironman.id).apply!
    assert_equal 2, result.billed, "the expense and the bill; a journal is not a cost"
    assert_equal 0, result.moved
    assert_equal 0, result.skipped
    assert_equal @ironman, @april.reload.billable_to
    assert_equal @ironman, @bill.reload.billable_to
    assert_nil @march.reload.billable_to
    assert_equal @travel, @april.line_items.first.account, "nothing moved"

    event = @april.events.newest_first.first
    assert_equal "billable_changed", event.action
    assert_equal "Billable to IRONMAN", event.title
    assert_empty event.detail_lines
    assert_equal [ "Was billable to Northwind" ], @bill.events.newest_first.first.detail_lines
    assert_empty @journal.events.where(action: "billable_changed")
    assert_includes Document.billable_to(@ironman).unbilled, @april
  end

  test "a cost already on an invoice keeps its customer and is counted as skipped; one already theirs is left alone" do
    @april.update!(billable_to: @northwind)
    invoice = @org.documents.create!(contact: @northwind, date: Date.new(2026, 4, 28), documentable: Invoice.new(due_date: Date.new(2026, 5, 28), receivable_account: @ar),
      line_items_attributes: [ { description: "Car hire", quantity: 1, unit_amount: 60, account_id: @rent.id, rebills_document_id: @april.id } ])
    assert_equal invoice, @april.reload.billed_on
    @bill.update!(billable_to: @ironman)

    result = recoding(from: "2026-04-01", to: "2026-04-30", bill_to: @ironman.id).apply!
    assert_equal 0, result.billed
    assert_equal 1, result.skipped
    assert_equal @northwind, @april.reload.billable_to
    assert_empty @bill.events.where(action: "billable_changed"), "no change, no history"
  end

  test "not billable clears the flag" do
    @april.update!(billable_to: @ironman)
    result = recoding(bill_to: "none").apply!
    assert_equal 1, result.billed
    assert_nil @april.reload.billable_to
    event = @april.events.newest_first.first
    assert_equal "No longer billable", event.title
    assert_equal [ "Was billable to IRONMAN" ], event.detail_lines
  end

  test "a vendor billed for the first time becomes a customer too; a stranger is refused" do
    hertz = @org.contacts.find_by!(name: "Hertz")
    recoding(bill_to: hertz.id, line_keys: [ key(@march) ]).apply!
    assert_equal "both", hertz.reload.kind
    assert_not recoding(bill_to: 0).valid?(:apply)
  end

  test "moving and billing together, all or nothing" do
    result = move(from: "2026-04-01", to: "2026-04-30", bill_to: @ironman.id).apply!
    assert_equal [ 3, 2 ], [ result.moved, result.billed ]
    assert_equal @reimb, @april.reload.line_items.first.account
    assert_equal @ironman, @april.billable_to
  end
end
