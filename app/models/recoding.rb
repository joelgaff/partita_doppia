# Find and recode. Find the lines on one account (document lines and journal
# lines), narrowed by dates, customer, vendor and kind of document; choose among them; then move
# them to another account, flag their documents as billable to a customer, or
# both. All of it or none of it.
#
# Moving changes the lines themselves and posts each document again, so the
# ledger reads as if it had been coded that way all along. Legs a document
# posts on its own account (the bank, receivables, payables) are not lines and
# stay put. Voided documents are never found.
#
# Billing is the document's, not the line's: an expense or bill is flagged
# whole. A cost already on an invoice keeps its customer. Anything that is
# not a cost (an invoice, a deposit, a journal) is passed over.
class Recoding
  include ActiveModel::Model
  include ActiveModel::Attributes

  NONE = "none"   # as a customer to find: nobody yet; as a customer to bill: not billable

  # Kinds of document to find, by the types each takes in; blank finds any.
  KINDS = { "invoices" => %w[Invoice], "costs" => %w[Expense Bill] }.freeze

  Line = Struct.new(:record, :document, :description, :amount) do
    def key = "#{record.class.model_name.singular}_#{record.id}"
  end
  Result = Struct.new(:moved, :billed, :skipped, keyword_init: true)

  attribute :organization
  # what to find
  attribute :account_id,  :integer
  attribute :from,        :date
  attribute :to,          :date
  attribute :customer_id, :string    # a contact's id, NONE, or blank for anyone
  attribute :vendor_id,   :integer
  attribute :kind,        :string    # a key of KINDS, or blank for any
  # which of them: nil is all of them, a list is those and no others
  attribute :line_keys
  # what to do
  attribute :to_account_id, :integer
  attribute :bill_to,       :string  # a contact's id, NONE, or blank to leave it be

  validates :account, presence: { message: "must be chosen" }
  validate  :dates_in_order
  validate  :people_known
  validates :kind, inclusion: { in: KINDS.keys, message: "is not a kind of document to find" }, allow_blank: true
  with_options on: :apply do
    validate :something_to_do
    validate :something_chosen
    validate :target_account_usable
    validate :customer_to_bill_known
  end

  def account    = @account    ||= ledger_account(account_id)
  def to_account = @to_account ||= ledger_account(to_account_id)
  def vendor     = @vendor     ||= contact(vendor_id)
  def customer         = no_customer? ? nil : (@customer ||= contact(customer_id))
  def customer_to_bill = unbilling?   ? nil : (@customer_to_bill ||= contact(bill_to))

  def no_customer? = customer_id == NONE
  def moving?      = to_account_id.present?
  def billing?     = bill_to.present?
  def unbilling?   = bill_to == NONE

  # What was found, oldest first.
  def lines
    @lines ||= (document_lines + journal_lines).sort_by { |l| [ l.document.date, l.document.id, l.record.id ] }
  end

  def total = lines.sum(&:amount)

  def chosen?(line) = line_keys.nil? || line_keys.include?(line.key)
  def chosen_lines  = lines.select { |line| chosen?(line) }

  def apply!
    raise ActiveRecord::RecordInvalid.new(self) unless valid?(:apply)
    result = Result.new(moved: 0, billed: 0, skipped: 0)
    ActiveRecord::Base.transaction do
      chosen_lines.group_by(&:document).each do |document, its_lines|
        move(document, its_lines, result) if moving?
        bill(document, result)            if billing?
      end
    end
    @lines = nil
    result
  end

  private

  def move(document, its_lines, result)
    its_lines.each { |line| line.record.update!(account: to_account) }
    document.reload.repost_to_ledger!
    document.record_event!(:reclassified, lines: its_lines.size, from: label(account), to: label(to_account))
    result.moved += its_lines.size
  end

  def bill(document, result)
    return unless document.billable?
    return if document.billable_to == customer_to_bill
    return result.skipped += 1 if document.billed?
    was = document.billable_to&.name
    customer_to_bill.update!(kind: "both") if customer_to_bill && !customer_to_bill.customer?
    # Only the flag changes: an old document is not held to today's rules to get it.
    document.update_columns(billable_to_id: customer_to_bill&.id, updated_at: Time.current)
    document.record_event!(:billable_changed, to: customer_to_bill&.name, was: was)
    result.billed += 1
  end

  def ledger_account(id)
    Plutus::Account.where(tenant: organization).find_by(id: id) if id
  end

  def contact(id)
    organization.contacts.find_by(id: id) if id.present?
  end

  def label(account) = [ account.code.presence, account.name ].compact.join(" ")

  def documents
    scope = organization.documents.live
    scope = scope.where(date: from..) if from
    scope = scope.where(date: ..to)   if to
    scope = scope.where(contact_id: vendor_id) if vendor_id
    scope = scope.where(documentable_type: KINDS.fetch(kind)) if KINDS.key?(kind)
    scope = scope.without_customer             if no_customer?
    scope = scope.for_customer(customer_id)    if customer_id.present? && !no_customer?
    scope
  end

  def document_lines
    LineItem.where(lineable_type: "Document", lineable_id: documents.select(:id), account_id: account_id)
            .includes(lineable: %i[contact billable_to documentable line_items]).map { |li| Line.new(li, li.lineable, li.description, li.amount) }
  end

  def journal_lines
    JournalLine.where(account_id: account_id)
               .where(journal_entry_id: documents.where(documentable_type: "JournalEntry").select(:documentable_id))
               .includes(journal_entry: :document)
               .map { |jl| Line.new(jl, jl.journal_entry.document, jl.journal_entry.narrative, jl.debit? ? jl.debit_amount : -jl.credit_amount) }
  end

  def dates_in_order
    errors.add(:to, "must not be before the start date") if from && to && to < from
  end

  def people_known
    errors.add(:customer, "is not one of this organisation's contacts") if customer_id.present? && !no_customer? && customer.nil?
    errors.add(:vendor,   "is not one of this organisation's contacts") if vendor_id && vendor.nil?
  end

  def something_to_do
    errors.add(:base, "Choose an account to move the lines to, a customer to bill them to, or both") unless moving? || billing?
  end

  def something_chosen
    errors.add(:base, "Tick at least one line") if account && chosen_lines.empty?
  end

  def target_account_usable
    return unless moving?
    return errors.add(:to_account, "must be one of this organisation's accounts") if to_account.nil?
    errors.add(:to_account, "must be a different account") if to_account == account
    errors.add(:to_account, "#{to_account.name} is archived; restore it first") if to_account.archived?
  end

  def customer_to_bill_known
    errors.add(:bill_to, "is not one of this organisation's contacts") if billing? && !unbilling? && customer_to_bill.nil?
  end
end
