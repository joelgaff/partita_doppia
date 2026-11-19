require "application_system_test_case"

class FindAndRecodeTest < ApplicationSystemTestCase
  test "find meals with no customer, untick one, bill the rest to a customer" do
    org = organizations(:one); Current.organization = org
    bank  = create_bank_account(org, name: "Checking", code: "1000")
    meals = Plutus::Expense.create!(tenant: org, name: "Meals", code: "6400")
    org.contacts.create!(name: "IRONMAN", kind: "customer")
    lunch  = create_expense(org, amount: 30, category: meals, bank_account: bank, vendor: "Chipotle", date: Date.new(2026, 4, 8))
    dinner = create_expense(org, amount: 90, category: meals, bank_account: bank, vendor: "Olive Garden", date: Date.new(2026, 4, 9))
    mine   = create_expense(org, amount: 12, category: meals, bank_account: bank, vendor: "Subway", date: Date.new(2026, 4, 10))
    sign_in_as_launchpad_user(org)

    visit "/recoding/new"
    select "6400 — Meals (Expense)", from: "Lines on"
    select "No customer yet", from: "Customer"
    click_button "Find"
    assert_selector "tbody tr", count: 3
    assert_text "3 of 3 ticked"
    page.save_screenshot("/tmp/claude-1000/-home-joel-Work-partita-doppia/24777f4b-7183-44b1-8f0d-9f6ac02d6e16/scratchpad/recode.png") if ENV["SHOT"]

    find("tbody tr", text: "Subway").find("input[type=checkbox]").uncheck
    assert_text "2 of 3 ticked"
    find("thead input[type=checkbox]").click   # some ticked: the box over them ticks them all
    assert_text "3 of 3 ticked"
    find("thead input[type=checkbox]").click
    assert_text "0 of 3 ticked"
    assert_button "Apply to ticked lines", disabled: true
    find("tbody tr", text: "Chipotle").find("input[type=checkbox]").check
    find("tbody tr", text: "Olive Garden").find("input[type=checkbox]").check

    select "IRONMAN", from: "Bill to"
    accept_confirm { click_button "Apply to ticked lines" }
    assert_text "2 costs now billable to IRONMAN."
    assert_selector "tbody tr", count: 1, text: "Subway"
    assert_equal "IRONMAN", lunch.reload.billable_to.name
    assert_equal "IRONMAN", dinner.reload.billable_to.name
    assert_nil mine.reload.billable_to
    if ENV["SHOT"]
      page.current_window.resize_to(390, 844)
      visit "/recoding/new?account_id=#{meals.id}"
      page.save_screenshot("/tmp/claude-1000/-home-joel-Work-partita-doppia/24777f4b-7183-44b1-8f0d-9f6ac02d6e16/scratchpad/recode-phone.png")
    end
  end
end
