require "test_helper"

# Pairing many expense accounts with an income account at once, from the chart.
class ChartBulkPairingTest < ActionDispatch::IntegrationTest
  setup do
    @org     = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @bank    = create_bank_account(@org, name: "Checking", code: "1000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4000")
    @old     = Plutus::Revenue.create!(tenant: @org, name: "Old Income", code: "4900", archived_at: Time.current)
    @freight = Plutus::Expense.create!(tenant: @org, name: "Freight", code: "6100")
    @rent    = Plutus::Expense.create!(tenant: @org, name: "Rent", code: "6000")
    @retired = Plutus::Expense.create!(tenant: @org, name: "Retired", code: "6999", archived_at: Time.current)
  end

  def row(account) = "tr##{ActionView::RecordIdentifier.dom_id(account)}"
  def form_id      = ActionView::RecordIdentifier.dom_id(@org, :billing_income)

  test "expense rows have a tick each, tied to one form under the expenses; other types have none" do
    get accounts_path
    assert_select "[data-controller=checklist]" do
      assert_select "#{row(@freight)} input[type=checkbox][name='account_ids[]'][value=?][form=?]", @freight.id.to_s, form_id
      assert_select "#{row(@freight)} input[type=checkbox][checked]", count: 0
      assert_select "#{row(@sales)} input[type=checkbox]", count: 0
      assert_select "#{row(@retired)} input[type=checkbox]", count: 0
      assert_select "input[type=checkbox][data-checklist-target=all]", count: 1
      assert_select "form##{form_id}[action=?]", accounts_billing_income_path do
        assert_select "input[name=_method][value=patch]"
        assert_select "select[name=billing_income_account_id]" do
          assert_select "option[value='']", text: /The fallback in Settings/
          assert_select "option[value=?]", @sales.id.to_s, text: "4000 — Sales"
          assert_select "option", text: /Old Income/, count: 0
        end
        assert_select "input[type=submit][data-checklist-target=submit]"
      end
    end
  end

  test "the ticked accounts are paired together, and unpaired together" do
    patch accounts_billing_income_path, params: { account_ids: [ @freight.id, @rent.id ], billing_income_account_id: @sales.id }
    assert_redirected_to accounts_path
    assert_equal "2 accounts now bill as Sales.", flash[:notice]
    assert_equal [ @sales, @sales ], [ @freight, @rent ].map { |a| a.reload.billing_income_account }

    patch accounts_billing_income_path, params: { account_ids: [ @rent.id ], billing_income_account_id: "" }
    assert_equal "1 account now bills as the fallback in Settings.", flash[:notice]
    assert_nil @rent.reload.billing_income_account
    assert_equal @sales, @freight.reload.billing_income_account
  end

  test "a search is kept, and nothing ticked is said so" do
    patch accounts_billing_income_path, params: { account_ids: [ @freight.id ], billing_income_account_id: @sales.id, q: "frei" }
    assert_redirected_to accounts_path(q: "frei")
    patch accounts_billing_income_path, params: { billing_income_account_id: @sales.id }
    assert_redirected_to accounts_path
    assert_equal "Tick at least one expense account.", flash[:alert]
  end

  test "all or nothing: one account that can't take the pairing stops them all" do
    patch accounts_billing_income_path, params: { account_ids: [ @freight.id, @sales.id ], billing_income_account_id: @sales.id }
    assert_redirected_to accounts_path
    assert_match(/only an expense account/, flash[:alert])
    assert_nil @freight.reload.billing_income_account

    patch accounts_billing_income_path, params: { account_ids: [ @freight.id ], billing_income_account_id: @old.id }
    assert_match(/archived/, flash[:alert])
    theirs = Plutus::Expense.create!(tenant: Organization.create!(name: "Elsewhere"), name: "Theirs", code: "6100")
    patch accounts_billing_income_path, params: { account_ids: [ theirs.id ], billing_income_account_id: @sales.id }
    assert_response :not_found
    assert_nil theirs.reload.billing_income_account_id
  end
end
