# For a line that posts to a ledger account (LineItem, JournalLine): nothing
# new goes to an archived account. A line already there is left alone, so old
# documents stay editable, and an import (Current.importing) may still bring
# in history that used the account.
module RefusesArchivedAccount
  extend ActiveSupport::Concern

  included do
    validate :account_not_archived, if: -> { new_record? || account_id_changed? }
  end

  private

  def account_not_archived
    return unless account&.archived?
    return if Current.importing
    errors.add(:account, "#{account.name} is archived; choose another, or restore it on the chart of accounts")
  end
end
