require "test_helper"

# The chart of accounts has a search box, the same one the contacts page has.
class ChartAccountsSearchTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @travel = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6817", description: "Flights and hotels")
    @rent   = Plutus::Expense.create!(tenant: @org, name: "Rent", code: "6000")
    @sales  = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @old    = Plutus::Revenue.create!(tenant: @org, name: "Old Travel Income", code: "4900", archived_at: Time.current)
  end

  def row(account) = "tr##{ActionView::RecordIdentifier.dom_id(account)}"

  test "the chart searches name, code and description, inside a frame the search box drives" do
    get accounts_path
    assert_select "form[action=?][data-controller=search] input[type=search][name=q][data-action*='search#']", accounts_path
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(@org, :accounts)} #{row(@travel)}"

    get accounts_path(q: "trav")
    assert_select row(@travel), 1
    assert_select row(@old), 1, "archived accounts are searched too"
    assert_select row(@rent), 0
    assert_select "h2", text: "Expenses", count: 1
    assert_select "h2", text: "Revenues", count: 0   # a type with no match has no heading

    get accounts_path(q: "6000")
    assert_select row(@rent), 1
    assert_select row(@travel), 0
    get accounts_path(q: "hotels")
    assert_select row(@travel), 1

    get accounts_path(q: "%")
    assert_select "tbody tr", 0, "a wildcard is just a character"
    assert_select ".empty-state", text: /Nothing matches “%”/
    assert_select ".empty-state", text: /No accounts yet/, count: 0
  end

  test "archiving from a search keeps the search" do
    get accounts_path(q: "trav")
    assert_select "#{row(@travel)} form[action=?] input[name=q][value=trav]", archive_account_path(@travel)
    post archive_account_path(@travel), params: { q: "trav" }, as: :turbo_stream
    assert_response :success
    assert_select row(@travel), 1
    assert_select row(@rent), 0
  end

  test "another organisation's accounts are never found" do
    Plutus::Expense.create!(tenant: Organization.create!(name: "Elsewhere"), name: "Travel elsewhere", code: "6817")
    get accounts_path(q: "elsewhere")
    assert_select "tbody tr", 0
  end
end
