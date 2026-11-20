# Archiving a chart account (mixed into Plutus::Account): it keeps its postings
# and its place in the reports, and leaves the lists people pick from. An
# account something still points at for new postings can't go until that
# something lets go of it.
module AccountArchiving
  extend ActiveSupport::Concern

  included do
    scope :active,   -> { where(archived_at: nil) }
    scope :archived, -> { where.not(archived_at: nil) }
    validates :code, uniqueness: { scope: :tenant_id }, allow_nil: true   # the index says so too; this says it kindly
  end

  def archived? = archived_at.present?

  def archive!
    if (reason = archive_blocker)
      errors.add(:base, reason)
      raise ActiveRecord::RecordInvalid.new(self)
    end
    update!(archived_at: Time.current)
  end

  def restore! = update!(archived_at: nil)

  def archivable? = archive_blocker.nil?

  # Why it can't be archived, as the end of "<name> ...", or nil when it can.
  def archive_blocker
    return "is the ledger side of a bank account; archive the bank account under Banking instead" if bank_account
    if (settings = tenant&.settings) && [ settings.receivable_account_id, settings.payable_account_id, settings.billable_income_account_id ].include?(id)
      return "is a control account; choose another under Settings first"
    end
    if (paired = billed_from_accounts.active.order(:code, :name).pluck(:name)).any?
      return "is where #{paired.to_sentence} #{paired.one? ? 'bills its' : 'bill their'} income; change that on the chart first"
    end
    if (rate = TaxRate.where(organization_id: tenant_id).where("liability_account_id = :id OR asset_account_id = :id", id: id).first)
      return "is the account for tax rate #{rate.name}"
    end
    if (rule = BankRule.where(organization_id: tenant_id, account_id: id).first)
      return "is used by bank rule #{rule.name}"
    end
    recurring = RecurringInvoice.where(organization_id: tenant_id)
    if recurring.where(receivable_account_id: id).exists? || LineItem.where(lineable_type: "RecurringInvoice", lineable_id: recurring.select(:id), account_id: id).exists?
      return "is used by a recurring invoice"
    end
    nil
  end
end
