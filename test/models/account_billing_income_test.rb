require "test_helper"

# An expense account can name the income account its costs are billed as when
# a customer's invoice picks them up.
class AccountBillingIncomeTest < ActiveSupport::TestCase
  setup do
    @org     = organizations(:one)
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4000")
    @reimb   = Plutus::Revenue.create!(tenant: @org, name: "Reimbursed Expenses", code: "4030")
    @freight = Plutus::Expense.create!(tenant: @org, name: "Freight", code: "6100")
    @rent    = Plutus::Expense.create!(tenant: @org, name: "Rent", code: "6000")
  end

  test "an expense account can be paired with a revenue account, and unpaired" do
    @freight.update!(billing_income_account: @sales)
    assert_equal @sales, @freight.reload.billing_income_account
    assert_equal [ @freight ], @sales.billed_from_accounts.to_a
    @freight.update!(billing_income_account: nil)
    assert_nil @freight.reload.billing_income_account
  end

  test "only an expense account takes a pairing, only with revenue, only in its own books, and not an archived one" do
    @sales.billing_income_account = @reimb
    assert_not @sales.valid?
    assert_match(/only an expense account/, @sales.errors.full_messages.to_sentence)

    @freight.billing_income_account_id = @rent.id
    assert_not @freight.valid?
    assert_match(/must be a revenue account/, @freight.errors.full_messages.to_sentence)

    theirs = Plutus::Revenue.create!(tenant: Organization.create!(name: "Elsewhere"), name: "Sales", code: "4000")
    @freight.billing_income_account_id = theirs.id
    assert_not @freight.valid?

    @reimb.update!(archived_at: Time.current)
    @freight.billing_income_account_id = @reimb.id
    assert_not @freight.valid?
    assert_match(/archived/, @freight.errors.full_messages.to_sentence)
  end

  test "a pairing made before its income account was archived does not stop other edits" do
    @freight.update!(billing_income_account: @sales)
    @sales.update_columns(archived_at: Time.current)
    assert @freight.reload.update(name: "Freight and courier")
  end

  test "an income account others bill as can't be archived until they let go, and says who" do
    @freight.update!(billing_income_account: @sales)
    assert_match(/is where Freight bills its income/, @sales.archive_blocker)
    assert_raises(ActiveRecord::RecordInvalid) { @sales.archive! }
    @freight.update!(billing_income_account: nil)
    assert_nil @sales.archive_blocker
  end
end
