class AddArchivedAtToPlutusAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :plutus_accounts, :archived_at, :datetime
  end
end
