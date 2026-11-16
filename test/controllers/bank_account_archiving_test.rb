require "test_helper"

# Archiving a bank account archives its side of the ledger with it, so the
# account leaves the chart's pickers as well as the bank pickers. Restoring
# brings both back. The chart sends you to Banking for either.
class BankAccountArchivingTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @bank = create_bank_account(@org, name: "Old Savings", code: "1050", kind: "savings")
    @rent = Plutus::Expense.create!(tenant: @org, name: "Rent", code: "6000")
  end

  def row(account) = "##{ActionView::RecordIdentifier.dom_id(account)}"

  test "the ledger account follows the bank account in and out of the archive" do
    @bank.archive!
    assert @bank.reload.archived?
    assert @bank.account.reload.archived?
    assert_not_includes @org.plutus_accounts.active, @bank.account

    @bank.restore!
    assert_not @bank.reload.archived?
    assert_not @bank.account.reload.archived?
  end

  test "an archived bank account is off the journal and Settings pickers" do
    get new_journal_entry_path
    assert_select "select[name$='[account_id]'] option[value=?]", @bank.account.id.to_s
    post archive_bank_account_path(@bank)

    get new_journal_entry_path
    assert_select "select[name$='[account_id]'] option[value=?]", @bank.account.id.to_s, count: 0
    get settings_path
    assert_select "select[name$='[receivable_account_id]'] option[value=?]", @bank.account.id.to_s, count: 0
  end

  test "the chart lists it as archived and points to Banking to bring it back" do
    @bank.archive!
    get accounts_path
    assert_select ".archived-accounts #{row(@bank.account)}" do
      assert_select "form", count: 0
      assert_select "a[href=?]", edit_bank_account_path(@bank)
    end

    post restore_account_path(@bank.account)
    assert_redirected_to accounts_path
    assert_match(/Banking/, flash[:alert])
    assert @bank.account.reload.archived?, "the chart does not restore half of a bank account"
  end

  test "its history stays on the ledger and in the reports" do
    @org.documents.create!(date: Date.current, documentable: JournalEntry.new(narrative: "Opening", lines_attributes: [
      { account_id: @bank.account.id, debit_amount: 500 }, { account_id: @rent.id, credit_amount: 500 } ]))
    @bank.archive!
    assert_equal 500, @bank.reload.balance
    get bank_account_path(@bank)
    assert_response :success
  end
end
