# A ledger account may be the face of one bank account (see BankAccount), and
# can be archived (see AccountArchiving) and searched (see Searchable).
Rails.application.config.to_prepare do
  Plutus::Account.include AccountArchiving unless Plutus::Account.include?(AccountArchiving)
  unless Plutus::Account.include?(Searchable)
    Plutus::Account.include Searchable
    Plutus::Account.searchable_by :name, :code, :description
  end
  Plutus::Account.has_one :bank_account, dependent: :destroy unless Plutus::Account.reflect_on_association(:bank_account)
end
