require "test_helper"

# An archived account is off every list an account is picked from, and stays
# on the documents that already use it.
class ArchivedAccountPickersTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar       = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @ap       = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @sales    = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @old_rev  = Plutus::Revenue.create!(tenant: @org, name: "Old Revenue", code: "4900")
    @rent     = Plutus::Expense.create!(tenant: @org, name: "Rent", code: "6000")
    @old_exp  = Plutus::Expense.create!(tenant: @org, name: "Old Expense", code: "6900")
    @old_ast  = Plutus::Asset.create!(tenant: @org, name: "Old Asset", code: "1900")
    @old_liab = Plutus::Liability.create!(tenant: @org, name: "Old Liability", code: "2900")
    @bank     = create_bank_account(@org, name: "Checking", code: "1000")
    @org.settings.update!(receivable_account: @ar, payable_account: @ap, bank_account: @bank)
    @archived = [ @old_rev, @old_exp, @old_ast, @old_liab ]
  end

  def archive_all = @archived.each(&:archive!)

  def offered_ids(selector = "select[name$='[account_id]']")
    css_select(selector.split(",").map { |part| "#{part.strip} option" }.join(", ")).map { |o| o["value"] }.compact_blank.map(&:to_i).uniq
  end

  def assert_offers(account, path, selector = "select[name$='[account_id]']")
    get path
    assert_response :success
    assert_includes offered_ids(selector), account.id, "#{path} offers #{account.name}"
  end

  def assert_hides_archived(path, selector = "select[name$='[account_id]']")
    get path
    assert_response :success
    assert_empty offered_ids(selector) & @archived.map(&:id), "#{path} offers an archived account"
    assert_no_match(/Old (Revenue|Expense|Asset|Liability)/, css_select(selector).to_s, path)
  end

  test "the document forms stop offering an archived account" do
    assert_offers @old_rev, new_invoice_path
    assert_offers @old_exp, new_bill_path
    assert_offers @old_exp, new_expense_path
    assert_offers @old_rev, new_deposit_path
    assert_offers @old_rev, new_recurring_invoice_path
    assert_offers @old_ast, new_journal_entry_path
    assert_offers @old_exp, new_bank_rule_path, "select[name='bank_rule[account_id]']"

    archive_all
    [ new_invoice_path, new_bill_path, new_expense_path, new_deposit_path, new_recurring_invoice_path, new_journal_entry_path ].each do |path|
      assert_hides_archived path
    end
    assert_hides_archived new_bank_rule_path, "select[name='bank_rule[account_id]']"
  end

  test "Settings and tax rates stop offering an archived account" do
    selects = "select[name$='account_id]']"
    assert_offers @old_ast,  settings_path, selects
    assert_offers @old_liab, new_tax_rate_path, selects
    archive_all
    assert_hides_archived settings_path, selects
    assert_hides_archived new_tax_rate_path, selects
  end

  test "reconcile stops offering an archived account" do
    @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: -48, description: "LANDLORD LLC")
    @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: 90, description: "DEPOSIT ACME")
    assert_offers @old_exp, bank_transactions_path, "select[name=account_id], select[name='remainder[account_id]']"
    archive_all
    assert_hides_archived bank_transactions_path, "select[name=account_id], select[name='remainder[account_id]']"
  end

  test "an invoice already on an archived account keeps it when edited, marked as archived" do
    invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @old_rev)
    @old_rev.archive!

    get edit_invoice_path(invoice)
    assert_select "select[name$='[account_id]'] option[selected][value=?]", @old_rev.id.to_s, text: /Old Revenue \(archived\)/
    line = invoice.line_items.first
    patch invoice_path(invoice), params: { document: { memo: "Thanks", line_items_attributes: { "0" => { id: line.id, description: "Services rendered", quantity: 1, unit_amount: 100, account_id: @old_rev.id } } } }
    assert_redirected_to invoice_path(invoice)
    assert_equal @old_rev, invoice.reload.line_items.first.account

    get invoice_path(invoice)
    assert_response :success
    get new_invoice_path
    assert_not_includes offered_ids, @old_rev.id, "and it is still not offered on a new invoice"
  end

  test "a journal entry on an archived account keeps it when edited" do
    entry = @org.documents.create!(date: Date.current, documentable: JournalEntry.new(narrative: "Reclass", lines_attributes: [
      { account_id: @old_ast.id, debit_amount: 50 }, { account_id: @rent.id, credit_amount: 50 } ]))
    @old_ast.archive!
    get edit_journal_entry_path(entry)
    assert_select "select[name$='[account_id]'] option[selected][value=?]", @old_ast.id.to_s, text: /Old Asset .*\(archived\)/
  end

  test "the general ledger report still lists an archived account" do
    archive_all
    get reports_general_ledger_path
    assert_includes offered_ids("select[name$='account_id]'], select[name=account_id]"), @old_exp.id
  end
end
