# A ledger account may be the face of one bank account (see BankAccount), and
# can be archived (see AccountArchiving) searched (see Searchable), and paired with
# the income account its costs are billed as (see BillingIncome).
Rails.application.config.to_prepare do
  Plutus::Account.include AccountArchiving unless Plutus::Account.include?(AccountArchiving)
  unless Plutus::Account.include?(Searchable)
    Plutus::Account.include Searchable
    Plutus::Account.searchable_by :name, :code, :description
  end
  Plutus::Account.include BillingIncome unless Plutus::Account.include?(BillingIncome)
  Plutus::Account.has_one :bank_account, dependent: :destroy unless Plutus::Account.reflect_on_association(:bank_account)
end
