require "application_system_test_case"

class ChartAccountsSearchSystemTest < ApplicationSystemTestCase
  test "typing in the chart's search box narrows the chart and keeps the box" do
    org = organizations(:one)
    Plutus::Expense.create!(tenant: org, name: "Travel", code: "6817")
    Plutus::Expense.create!(tenant: org, name: "Rent", code: "6000")
    sign_in_as_launchpad_user(org)

    visit "/accounts"
    assert_selector "td", text: "Rent"
    find("input[name=q]").send_keys("trav")
    assert_no_selector "td", text: "Rent"
    assert_selector "td", text: "Travel"
    assert_equal "trav", find("input[name=q]").value
    assert_equal "q", page.evaluate_script("document.activeElement.name"), "focus stays in the box"
    assert_match(/q=trav/, page.current_url)

    click_button "Archive"
    assert_selector ".archived-accounts td", text: "Travel"
    assert_no_selector "td", text: "Rent"
  end
end
