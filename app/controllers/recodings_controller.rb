# Find and recode. The page is a GET form that finds lines; under what it
# finds is the form that does something to the ticked ones. Only that second
# form changes anything.
class RecodingsController < ApplicationController
  FIND = %i[account_id from to customer_id vendor_id].freeze

  before_action :load_choices

  def new
    @recoding = Recoding.new(params.permit(*FIND).to_h.merge(organization: Current.organization))
    @searched = FIND.any? { |key| params[key].present? }
    @recoding.validate if @searched
  end

  def create
    chosen    = params.fetch(:recoding, {}).permit(*FIND, :to_account_id, :bill_to, line_keys: []).to_h
    @recoding = Recoding.new(chosen.merge(organization: Current.organization, line_keys: Array(chosen["line_keys"])))
    @found    = chosen.slice(*FIND.map(&:to_s)).compact_blank
    result    = @recoding.apply!
    redirect_to after(result), notice: summary(result)
  rescue ActiveRecord::RecordInvalid
    @searched = true
    render :new, status: :unprocessable_entity
  end

  private

  # Moved lines are best seen where they went; billing shows on the same search.
  def after(result)
    r = @recoding
    return new_recoding_path(@found) unless r.moving?
    reports_general_ledger_path(account_id: r.to_account.id, from: r.from&.iso8601, to: r.to&.iso8601)
  end

  def summary(result)
    r, said = @recoding, []
    said << "#{helpers.pluralize(result.moved, 'line')} moved from #{r.account.name} to #{r.to_account.name}." if r.moving?
    if r.billing?
      costs = helpers.pluralize(result.billed, "cost")
      said << (r.unbilling? ? "#{costs} no longer billable." : "#{costs} now billable to #{r.customer_to_bill.name}.")
      said << "#{result.skipped} already on an invoice #{result.skipped == 1 ? 'was' : 'were'} left alone." if result.skipped.positive?
    end
    said.join(" ")
  end

  # Lines can be found on an archived account, never moved onto one.
  def load_choices
    contacts     = Current.organization.contacts.ordered
    @accounts    = Plutus::Account.where(tenant: Current.organization).order(:type, :code, :name)
    @to_accounts = @accounts.active
    @customers   = contacts.customers
    @vendors     = contacts.vendors
  end
end
