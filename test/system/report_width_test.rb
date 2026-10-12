require "application_system_test_case"

# Report tables on a phone, with account names as long as real ones: the page
# must not grow wider than the screen, with or without the web app's chrome.
class ReportWidthTest < ApplicationSystemTestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank  = create_bank_account(@org, name: "Chase Business Checking Account", code: "")
    @ar    = Plutus::Asset.create!(tenant: @org, name: "Accounts Receivable", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Timing Services:RunSignUp Partner Fees", code: "4701")
    @org.settings.update!(receivable_account: @ar, bank_account: @bank)
    create_invoice(@org, client_name: "Northwind", amount: 38_938.77, receivable: @ar, revenue: @sales)
    sign_in_as_launchpad_user(@org)
  end

  test "the reports fit a phone with long account names" do
    on_phone
    %w[/reports/balance_sheet /reports/profit_and_loss].each do |path|
      visit path
      assert_fits_viewport(path)
      find_all("td.num", visible: true).each do |amount|
        assert amount.evaluate_script("this.getBoundingClientRect().right") <= page.evaluate_script("window.innerWidth"), "#{path}: an amount is cut off"
      end
    end
    %w[/reports/trial_balance /reports/general_ledger].each do |path|   # wide: these scroll sideways inside, by design
      visit path
      assert_fits_viewport(path)
    end
  end
end
