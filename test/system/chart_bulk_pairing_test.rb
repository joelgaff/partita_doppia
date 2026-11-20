require "application_system_test_case"

class ChartBulkPairingSystemTest < ApplicationSystemTestCase
  test "tick two expense accounts on the chart and pair them with an income account" do
    org = organizations(:one)
    Plutus::Revenue.create!(tenant: org, name: "Sales", code: "4000")
    freight = Plutus::Expense.create!(tenant: org, name: "Freight", code: "6100")
    Plutus::Expense.create!(tenant: org, name: "Rent", code: "6000")
    printing = Plutus::Expense.create!(tenant: org, name: "Printing", code: "6200")
    sign_in_as_launchpad_user(org)

    visit "/accounts"
    assert_button "Apply to ticked accounts", disabled: true
    find("tr", text: "Freight").find("input[type=checkbox]").check
    find("tr", text: "Printing").find("input[type=checkbox]").check
    assert_text "2 ticked"
    select "4000 — Sales", from: "Bill the ticked accounts as"
    click_button "Apply to ticked accounts"

    assert_text "2 accounts now bill as Sales."
    assert_selector "tr", text: /Freight\s+bills as 4000 Sales/
    assert_no_selector "tr", text: /Rent\s+bills as/
    assert_equal "Sales", freight.reload.billing_income_account.name
    assert_equal "Sales", printing.reload.billing_income_account.name
    page.save_screenshot("/tmp/claude-1000/-home-joel-Work-partita-doppia/24777f4b-7183-44b1-8f0d-9f6ac02d6e16/scratchpad/pairing.png") if ENV["SHOT"]

    find("tr", text: "Freight").click_link "Edit"
    assert_select "When billed to a customer, post income to", selected: "4000 — Sales"
    page.save_screenshot("/tmp/claude-1000/-home-joel-Work-partita-doppia/24777f4b-7183-44b1-8f0d-9f6ac02d6e16/scratchpad/account-edit.png") if ENV["SHOT"]
  end
end
