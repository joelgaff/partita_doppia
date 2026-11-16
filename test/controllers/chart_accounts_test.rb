require "test_helper"

# The chart of accounts page: add an account by hand, archive one that is no
# longer used, bring it back.
class ChartAccountsTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @old   = Plutus::Revenue.create!(tenant: @org, name: "Old Line of Business", code: "4900")
  end

  def row(account) = "##{ActionView::RecordIdentifier.dom_id(account)}"

  test "the chart offers to add an account" do
    get accounts_path
    assert_select "a[href=?]", new_account_path, text: "Add account"
    get new_account_path
    assert_response :success
    assert_select "form[action=?]", accounts_path do
      assert_select "select[name='account[type]'] option", count: 5
      assert_select "select[name='account[type]'] option[value=Expense][selected]"
      assert_select "input[name='account[name]']"
      assert_select "input[name='account[code]']"
      assert_select "textarea[name='account[description]']"
      assert_select "input[type=submit][value='Add account']"
    end
  end

  test "adding an account puts it on the chart under its type, in this organisation" do
    assert_difference -> { @org.plutus_accounts.count }, 1 do
      post accounts_path, params: { account: { type: "Expense", name: " Race Supplies ", code: "6450", description: "Bibs, pins, tape" } }
    end
    assert_redirected_to accounts_path
    account = @org.plutus_accounts.find_by!(code: "6450")
    assert_instance_of Plutus::Expense, account
    assert_equal "Race Supplies", account.name
    assert_equal "Bibs, pins, tape", account.description
    follow_redirect!
    assert_select ".flash-notice", text: /Race Supplies added/
    assert_select row(account), text: /Race Supplies/
  end

  test "each of the five types can be added, and a blank code is no code" do
    %w[Asset Liability Equity Revenue Expense].each do |type|
      post accounts_path, params: { account: { type: type, name: "New #{type}", code: "" } }
      account = @org.plutus_accounts.find_by!(name: "New #{type}")
      assert_equal "Plutus::#{type}", account.type
      assert_nil account.code
    end
  end

  test "a missing name, a taken name, a taken code or a made-up type is refused with the form back" do
    { { type: "Expense", name: "" }                      => /Name can't be blank/,
      { type: "Expense", name: "Sales" }                 => /Name has already been taken/,
      { type: "Expense", name: "Fresh", code: "4100" }   => /Code has already been taken/,
      { type: "Entry", name: "Fresh" }                   => /Type is not included in the list/ }.each do |attrs, message|
      assert_no_difference -> { Plutus::Account.count } do
        post accounts_path, params: { account: attrs }
      end
      assert_response :unprocessable_entity
      assert_select ".form-errors", text: message
      assert_select "input[name='account[name]'][value=?]", attrs[:name] if attrs[:name].present?
    end
  end

  test "archiving moves an account to the archived list, restoring brings it back" do
    get accounts_path
    assert_select "#{row(@old)} form[action=?] button", archive_account_path(@old), text: "Archive"

    post archive_account_path(@old)
    assert_redirected_to accounts_path
    assert @old.reload.archived?
    follow_redirect!
    assert_select ".flash-notice", text: /Old Line of Business archived/
    assert_select ".archived-accounts #{row(@old)} form[action=?] button", restore_account_path(@old), text: "Restore"
    assert_select ".account-group:not(.archived-accounts) #{row(@old)}", count: 0
    assert_select ".account-group:not(.archived-accounts) #{row(@sales)}"

    post restore_account_path(@old)
    assert_redirected_to accounts_path
    assert_not @old.reload.archived?
    follow_redirect!
    assert_select ".account-group:not(.archived-accounts) #{row(@old)}"
    assert_select ".archived-accounts", count: 0
  end

  test "over Turbo the chart is redrawn in place" do
    post archive_account_path(@old), as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", ActionView::RecordIdentifier.dom_id(@org, :chart) do
      assert_select "template .archived-accounts #{row(@old)}"
    end
  end

  test "an account still in use says why it can't be archived" do
    @org.settings.update!(receivable_account: @ar)
    post archive_account_path(@ar)
    assert_redirected_to accounts_path
    assert_match(/AR is a control account; choose another under Settings first/, flash[:alert])
    assert_not @ar.reload.archived?
  end

  test "a bank account's row sends you to Banking instead of offering Archive" do
    bank = create_bank_account(@org, name: "Checking", code: "1000")
    get accounts_path
    assert_select "#{row(bank.account)} form", count: 0
    assert_select "#{row(bank.account)} a[href=?]", edit_bank_account_path(bank)
  end

  test "another organisation's account is not there to archive" do
    other = Plutus::Expense.create!(tenant: Organization.create!(name: "Someone else"), name: "Theirs")
    post archive_account_path(other)
    assert_response :not_found
    assert_not other.reload.archived?
  end
end
