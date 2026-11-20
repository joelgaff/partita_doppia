class AddBillingIncomeAccountToPlutusAccounts < ActiveRecord::Migration[8.1]
  def change
    add_reference :plutus_accounts, :billing_income_account, foreign_key: { to_table: :plutus_accounts }, index: true
  end
end
