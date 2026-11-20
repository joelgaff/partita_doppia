require "test_helper"

# Editing a chart account: its name, code and description, and for an expense
# account the income account its costs are billed as.
class ChartAccountEditTest < ActionDispatch::IntegrationTest
  setup do
    @org     = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @bank    = create_bank_account(@org, name: "Checking", code: "1000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4000")
    @reimb   = Plutus::Revenue.create!(tenant: @org, name: "Reimbursed Expenses", code: "4030")
    @old     = Plutus::Revenue.create!(tenant: @org, name: "Old Income", code: "4900", archived_at: Time.current)
    @freight = Plutus::Expense.create!(tenant: @org, name: "Freight", code: "6100", description: "Courier")
  end

  def row(account) = "tr##{ActionView::RecordIdentifier.dom_id(account)}"

  test "each account on the chart can be edited, except a bank account's, which is Banking's" do
    get accounts_path
    assert_select "#{row(@freight)} a[href=?]", edit_account_path(@freight), text: "Edit"
    assert_select "#{row(@sales)} a[href=?]", edit_account_path(@sales), text: "Edit"
    assert_select "#{row(@bank.account)} a[href=?]", edit_account_path(@bank.account), count: 0
    get edit_account_path(@bank.account)
    assert_redirected_to edit_bank_account_path(@bank)
  end

  test "the form has the account's details; an expense account also says what it is billed as" do
    get edit_account_path(@freight)
    assert_response :success
    assert_select "h1", text: "Edit Freight"
    assert_select "form[action=?]", account_path(@freight) do
      assert_select "input[name=_method][value=patch]"
      assert_select "select[name='account[type]']", count: 0   # an account's type is not changed after the fact
      assert_select "input[name='account[name]'][value=Freight]"
      assert_select "input[name='account[code]'][value='6100']"
      assert_select "textarea[name='account[description]']", text: "Courier"
      assert_select "select[name='account[billing_income_account_id]']" do
        assert_select "option[value='']", text: /The fallback in Settings/
        assert_select "option[value=?]", @sales.id.to_s, text: "4000 — Sales"
        assert_select "option", text: /Old Income/, count: 0
        assert_select "option", text: /Freight/, count: 0
      end
    end

    get edit_account_path(@sales)
    assert_select "select[name='account[billing_income_account_id]']", count: 0
  end

  test "the fallback is named when Settings has one" do
    @org.settings.update!(billable_income_account: @reimb)
    get edit_account_path(@freight)
    assert_select "select[name='account[billing_income_account_id]'] option[value='']", text: "The fallback in Settings (4030 Reimbursed Expenses)"
  end

  test "saving changes the account and its pairing, and the chart shows the pairing" do
    patch account_path(@freight), params: { account: { name: " Freight and courier ", code: "6110", description: "", billing_income_account_id: @sales.id } }
    assert_redirected_to accounts_path
    assert_equal "Freight and courier saved.", flash[:notice]
    @freight.reload
    assert_equal [ "Freight and courier", "6110", nil, @sales ], [ @freight.name, @freight.code, @freight.description, @freight.billing_income_account ]
    assert_instance_of Plutus::Expense, @freight

    get accounts_path
    assert_select "#{row(@freight)} .chart-billed-as", text: "bills as 4000 Sales"
    assert_select "#{row(@sales)} .chart-billed-as", count: 0

    patch account_path(@freight), params: { account: { name: "Freight", billing_income_account_id: "" } }
    assert_nil @freight.reload.billing_income_account
  end

  test "a bad edit comes back with its reasons and changes nothing" do
    patch account_path(@freight), params: { account: { name: "", code: "4000" } }
    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_equal [ "Freight", "6100" ], [ @freight.reload.name, @freight.code ]

    patch account_path(@sales), params: { account: { name: "Sales", billing_income_account_id: @reimb.id } }
    assert_response :unprocessable_entity
    assert_nil @sales.reload.billing_income_account_id
  end

  test "the type can't be changed by a crafted form, nor another organisation's account edited" do
    patch account_path(@freight), params: { account: { name: "Freight", type: "Revenue" } }
    assert_instance_of Plutus::Expense, Plutus::Account.find(@freight.id)
    theirs = Plutus::Expense.create!(tenant: Organization.create!(name: "Elsewhere"), name: "Theirs", code: "6100")
    patch account_path(theirs), params: { account: { name: "Mine now" } }
    assert_response :not_found
  end
end
