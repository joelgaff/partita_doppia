require "test_helper"

# Moving every line on one account, in a stretch of dates, onto another: the
# lines themselves change and each document posts again, so the books read as
# if it had been coded that way from the start.
class ReclassificationTest < ActiveSupport::TestCase
  setup do
    @org    = organizations(:one)
    Current.organization = @org
    @bank   = create_bank_account(@org, name: "Checking", code: "1000")
    @ap     = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @travel = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6817")
    @reimb  = Plutus::Expense.create!(tenant: @org, name: "Reimbursable Expenses", code: "6900")
    @rent   = Plutus::Expense.create!(tenant: @org, name: "Rent", code: "6000")

    @march = create_expense(@org, amount: 40, category: @travel, bank_account: @bank, vendor: "Delta", date: Date.new(2026, 3, 10))
    @april = create_expense(@org, amount: 60, category: @travel, bank_account: @bank, vendor: "Hertz", date: Date.new(2026, 4, 5))
    @bill  = create_bill(@org, amount: 25, category: @travel, payable: @ap, vendor: "Uber", date: Date.new(2026, 4, 20))
    @other = create_expense(@org, amount: 500, category: @rent, bank_account: @bank, vendor: "Landlord", date: Date.new(2026, 4, 1))
    @journal = @org.documents.create!(date: Date.new(2026, 4, 30), documentable: JournalEntry.new(narrative: "Accrue travel", lines_attributes: [
      { account_id: @travel.id, debit_amount: 15 }, { account_id: @ap.id, credit_amount: 15 } ]))
  end

  teardown { Current.reset }

  def reclass(**attrs)
    Reclassification.new(organization: @org, from_account_id: @travel.id, to_account_id: @reimb.id, **attrs)
  end

  test "it lists the lines on the account within the dates, document lines and journal lines alike" do
    r = reclass(from: "2026-04-01", to: "2026-04-30")
    assert r.valid?
    assert_equal [ @april, @bill, @journal ], r.lines.map(&:document)
    assert_equal 100, r.total
  end

  test "applying moves those lines, reposts their documents, and leaves the rest alone" do
    moved = reclass(from: "2026-04-01", to: "2026-04-30").apply!
    assert_equal 3, moved
    assert_equal 40,  @travel.reload.balance, "March stays where it was"
    assert_equal 100, @reimb.reload.balance
    assert_equal 500, @rent.reload.balance
    assert_equal @reimb, @april.reload.line_items.first.account
    assert_equal @travel, @march.reload.line_items.first.account
    assert_equal [ @reimb, @ap ], @journal.reload.journal_entry.lines.map(&:account)
  end

  test "each document's history says what moved" do
    reclass(from: "2026-04-01", to: "2026-04-30").apply!
    event = @april.events.newest_first.first
    assert_equal "reclassified", event.action
    assert_equal "Reclassified", event.title
    assert_equal [ "1 line: 6817 Travel → 6900 Reimbursable Expenses" ], event.detail_lines
    assert_empty @march.events.where(action: "reclassified")
  end

  test "open-ended dates take everything on the account" do
    assert_equal 4, reclass.lines.size
    assert_equal 3, reclass(from: "2026-04-01").lines.size
    assert_equal 1, reclass(to: "2026-03-31").lines.size
  end

  test "drafts move too; voided documents are left as they were" do
    draft = create_bill(@org, amount: 10, category: @travel, payable: @ap, vendor: "Lyft", date: Date.new(2026, 4, 21), state: "draft")
    @april.void!
    reclass(from: "2026-04-01", to: "2026-04-30").apply!
    assert_equal @reimb,  draft.reload.line_items.first.account
    assert_equal @travel, @april.reload.line_items.first.account
    assert_equal 40, @reimb.reload.balance, "the bill and the journal; a draft posts nothing"
  end

  test "it needs two different accounts of this organisation, and sane dates" do
    assert_not Reclassification.new(organization: @org, from_account_id: @travel.id, to_account_id: @travel.id).valid?
    assert_not Reclassification.new(organization: @org, from_account_id: @travel.id).valid?
    elsewhere = Plutus::Expense.create!(tenant: organizations(:two), name: "Theirs", code: "6817")
    assert_not Reclassification.new(organization: @org, from_account_id: elsewhere.id, to_account_id: @reimb.id).valid?
    assert_not reclass(from: "2026-05-01", to: "2026-04-01").valid?
    assert_raises(ActiveRecord::RecordInvalid) { reclass(from: "2026-05-01", to: "2026-04-01").apply! }
  end

  test "an archived account takes nothing, and nothing moves" do
    @reimb.archive!
    r = reclass
    assert_not r.valid?
    assert_match(/archived/, r.errors.full_messages.to_sentence)
  end

  test "another organisation's lines on a same-numbered account are not touched" do
    assert_equal 4, reclass.apply!
    assert_equal 0, reclass.lines.size
  end
end
