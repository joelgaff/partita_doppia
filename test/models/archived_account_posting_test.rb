require "test_helper"

# Nothing new is posted to an archived account, whatever page it came from.
# What was already there stays, and stays editable; a Xero import may still
# bring in history that used the account.
class ArchivedAccountPostingTest < ActiveSupport::TestCase
  setup do
    @org   = organizations(:one)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @old   = Plutus::Revenue.create!(tenant: @org, name: "Old Revenue", code: "4900")
    @rent  = Plutus::Expense.create!(tenant: @org, name: "Rent", code: "6000")
    @org.settings.update!(receivable_account: @ar)
  end

  test "a new document line on an archived account is refused, by name" do
    @old.archive!
    error = assert_raises(ActiveRecord::RecordInvalid) do
      create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @old)
    end
    assert_match(/Old Revenue is archived/, error.message)
    assert_equal 0, @org.documents.count
  end

  test "a document already on the account keeps working: edit it, add a line elsewhere, approve it, void it" do
    invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @old, state: "draft")
    @old.archive!
    line = invoice.line_items.first

    invoice.update_and_repost!(memo: "Thanks", line_items_attributes: [
      { id: line.id, description: "Services, reworded", unit_amount: 120 },
      { description: "Extra", quantity: 1, unit_amount: 30, account_id: @sales.id } ])
    assert_equal 150, invoice.reload.total
    assert_equal @old, line.reload.account

    invoice.approve!
    assert_equal 120, @old.reload.balance
    invoice.void!
    assert invoice.reload.voided?
  end

  test "a line can't be moved onto an archived account, nor a new one added there" do
    invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    @old.archive!
    line = invoice.line_items.first
    assert_raises(ActiveRecord::RecordInvalid) { invoice.update_and_repost!(line_items_attributes: [ { id: line.id, account_id: @old.id } ]) }
    assert_raises(ActiveRecord::RecordInvalid) do
      invoice.reload.update_and_repost!(line_items_attributes: [ { description: "More", quantity: 1, unit_amount: 5, account_id: @old.id } ])
    end
    assert_equal [ @sales ], invoice.reload.line_items.map(&:account)
  end

  test "a line moved off the account and back is a new use of it" do
    invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @old)
    @old.archive!
    line = invoice.line_items.first
    invoice.update_and_repost!(line_items_attributes: [ { id: line.id, account_id: @sales.id } ])
    assert_raises(ActiveRecord::RecordInvalid) { invoice.reload.update_and_repost!(line_items_attributes: [ { id: line.id, account_id: @old.id } ]) }
  end

  test "journal lines follow the same rule" do
    entry = @org.documents.create!(date: Date.current, documentable: JournalEntry.new(narrative: "Reclass", lines_attributes: [
      { account_id: @old.id, credit_amount: 50 }, { account_id: @rent.id, debit_amount: 50 } ]))
    @old.archive!
    assert entry.reload.journal_entry.lines.all?(&:valid?), "what is there stays valid"

    error = assert_raises(ActiveRecord::RecordInvalid) do
      @org.documents.create!(date: Date.current, documentable: JournalEntry.new(narrative: "Again", lines_attributes: [
        { account_id: @old.id, credit_amount: 10 }, { account_id: @rent.id, debit_amount: 10 } ]))
    end
    assert_match(/Old Revenue is archived/, error.message)
  end

  test "a recurring invoice can't take a new line on an archived account" do
    @old.archive!
    recurring = @org.recurring_invoices.build(client_name: "Acme", receivable_account: @ar, frequency: "monthly", interval: 1, next_run_on: Date.current,
      line_items_attributes: [ { description: "Retainer", quantity: 1, unit_amount: 500, account_id: @old.id } ])
    assert_not recurring.save
  end

  test "an import may still post history to an archived account" do
    Current.organization = @org
    report = Imports::BundleService.new(file_fixture("xero/bundle"), organization: @org).call
    assert_not report.failed?, report.to_s
    used = @org.documents.invoices.first.line_items.first.account
    assert_nil used.archive_blocker, "the fixture's revenue account is free to archive"
    used.archive!

    BooksReset.new(@org, scope: :transactions).call
    report = Imports::BundleService.new(file_fixture("xero/bundle"), organization: @org).call
    assert_not report.failed?, report.to_s
    assert_equal 2, @org.documents.invoices.count
    assert used.reload.archived?, "and the import leaves it archived"
    assert_not Current.importing, "the pass is the import's alone"
  ensure
    Current.reset
  end
end
