# Archiving a bank account now archives its ledger account with it. Bring the
# bank accounts archived before that into line.
class ArchiveLedgerAccountsOfArchivedBankAccounts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE plutus_accounts
      SET archived_at = (SELECT bank_accounts.archived_at FROM bank_accounts WHERE bank_accounts.account_id = plutus_accounts.id)
      WHERE archived_at IS NULL
        AND id IN (SELECT account_id FROM bank_accounts WHERE archived_at IS NOT NULL)
    SQL
  end

  def down
    execute <<~SQL
      UPDATE plutus_accounts SET archived_at = NULL
      WHERE id IN (SELECT account_id FROM bank_accounts WHERE archived_at IS NOT NULL)
    SQL
  end
end
