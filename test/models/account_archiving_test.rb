require "test_helper"

# A chart account can be archived: it stays on the ledger and in the reports
# with everything posted to it, and leaves the lists people pick from. An
# account something still depends on has to be let go of first.
class AccountArchivingTest < ActiveSupport::TestCase
  setup do
    @org     = organizations(:one)
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @old     = Plutus::Revenue.create!(tenant: @org, name: "Old Line of Business", code: "4900")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting", code: "6100")
  end

  test "archive and restore, with scopes for each side" do
    assert_not @old.archived?
    @old.archive!
    assert @old.reload.archived?
    assert_includes Plutus::Account.archived, @old
    assert_not_includes Plutus::Account.active, @old
    assert_not_includes Plutus::Revenue.where(tenant: @org).active, @old
    assert_includes Plutus::Revenue.where(tenant: @org).active, @sales

    @old.restore!
    assert_not @old.reload.archived?
    assert_includes Plutus::Account.active, @old
  end

  test "an account with postings can be archived and keeps its balance" do
    create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @old)
    assert_equal 100, @old.balance
    @old.archive!
    assert_equal 100, @old.reload.balance
    row = Reports::ProfitAndLoss.new(organization: @org).revenue_rows.find { |r| r.account == @old }
    assert_equal 100, row.amount, "still on the profit and loss"
  end

  test "a bank account's ledger account is archived from Banking, not here" do
    bank = create_bank_account(@org, name: "Checking", code: "1000")
    assert_match(/bank account/, bank.account.archive_blocker)
    assert_raises(ActiveRecord::RecordInvalid) { bank.account.archive! }
    assert_not bank.account.reload.archived?
  end

  test "the control accounts in Settings can't be archived while they are chosen" do
    ap = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @org.settings.update!(receivable_account: @ar, payable_account: ap, billable_income_account: @sales)
    [ @ar, ap, @sales ].each do |account|
      assert_match(/Settings/, account.archive_blocker, account.name)
      assert_raises(ActiveRecord::RecordInvalid) { account.archive! }
    end
    @org.settings.update!(billable_income_account: nil)
    assert_nil @sales.archive_blocker
  end

  test "an account a tax rate, a bank rule or a recurring invoice uses can't be archived" do
    tax = Plutus::Liability.create!(tenant: @org, name: "Sales Tax", code: "2200")
    @org.tax_rates.create!(name: "GST", rate: 0.1, liability_account: tax)
    assert_match(/tax rate GST/, tax.archive_blocker)

    cf = @org.contacts.create!(name: "Cloudflare", kind: "vendor")
    @org.bank_rules.create!(name: "Cloudflare hosting", match_kind: "contains", pattern: "cloudflare", amount_sign: "any", action_kind: "Expense", account: @hosting, contact: cf)
    assert_match(/bank rule Cloudflare hosting/, @hosting.archive_blocker)

    @org.recurring_invoices.create!(client_name: "Acme", receivable_account: @ar, frequency: "monthly", interval: 1, next_run_on: Date.current,
      line_items_attributes: [ { description: "Retainer", quantity: 1, unit_amount: 500, account_id: @old.id } ])
    assert_match(/recurring invoice/, @old.archive_blocker)
    assert_match(/recurring invoice/, @ar.archive_blocker)

    [ tax, @hosting, @old, @ar ].each { |a| assert_raises(ActiveRecord::RecordInvalid) { a.archive! } }
    assert_nil @sales.archive_blocker
  end
end
