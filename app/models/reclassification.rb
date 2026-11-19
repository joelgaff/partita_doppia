# Recode in bulk: every line on one account, between two dates, moves to
# another account. The lines themselves change (document lines and journal
# lines) and each document posts again, so the ledger reads as if it had been
# coded that way all along. Legs a document posts on its own account (the
# bank, receivables, payables) are not lines and stay put. Voided documents
# are left as they were.
class Reclassification
  include ActiveModel::Model
  include ActiveModel::Attributes

  Line = Struct.new(:record, :document, :description, :amount)

  attribute :organization
  attribute :from_account_id, :integer
  attribute :to_account_id,   :integer
  attribute :from, :date
  attribute :to,   :date

  validates :from_account, presence: { message: "must be chosen" }
  validates :to_account,   presence: { message: "must be chosen" }
  validate  :accounts_differ
  validate  :target_in_use
  validate  :dates_in_order

  def from_account = @from_account ||= account(from_account_id)
  def to_account   = @to_account   ||= account(to_account_id)

  # What would move, oldest first.
  def lines
    @lines ||= (document_lines + journal_lines).sort_by { |l| [ l.document.date, l.document.id, l.record.id ] }
  end

  def total = lines.sum(&:amount)

  # Moves the lines and returns how many moved. All of it or none of it.
  def apply!
    raise ActiveRecord::RecordInvalid.new(self) unless valid?
    ActiveRecord::Base.transaction do
      lines.group_by(&:document).each do |document, moving|
        moving.each { |line| line.record.update!(account: to_account) }
        document.reload.repost_to_ledger!
        document.record_event!(:reclassified, lines: moving.size, from: label(from_account), to: label(to_account))
      end
    end
    lines.size.tap { @lines = nil }
  end

  private

  def account(id)
    Plutus::Account.where(tenant: organization).find_by(id: id) if id
  end

  def label(account) = [ account.code.presence, account.name ].compact.join(" ")

  def documents
    scope = organization.documents.live
    scope = scope.where(date: from..) if from
    scope = scope.where(date: ..to)   if to
    scope
  end

  def document_lines
    LineItem.where(lineable_type: "Document", lineable_id: documents.select(:id), account_id: from_account_id)
            .includes(:lineable).map { |li| Line.new(li, li.lineable, li.description, li.amount) }
  end

  def journal_lines
    JournalLine.where(account_id: from_account_id)
               .where(journal_entry_id: documents.where(documentable_type: "JournalEntry").select(:documentable_id))
               .includes(journal_entry: :document)
               .map { |jl| Line.new(jl, jl.journal_entry.document, jl.journal_entry.narrative, jl.debit? ? jl.debit_amount : -jl.credit_amount) }
  end

  def accounts_differ
    errors.add(:to_account, "must be a different account") if from_account && from_account == to_account
  end

  def target_in_use
    errors.add(:to_account, "#{to_account.name} is archived; restore it first") if to_account&.archived?
  end

  def dates_in_order
    errors.add(:to, "must not be before the start date") if from && to && to < from
  end
end
