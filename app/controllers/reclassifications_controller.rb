# Recode in bulk. The page is a GET form: choosing accounts and dates shows
# what would move, and only the button under that list moves anything.
class ReclassificationsController < ApplicationController
  before_action :load_accounts

  def new
    @reclassification = Reclassification.new(choice(params))
    @chosen = %i[from_account_id to_account_id customer_id].any? { |key| params[key].present? }
    @reclassification.validate if @chosen
  end

  def create
    @reclassification = Reclassification.new(choice(params.fetch(:reclassification, {})))
    moved = @reclassification.apply!
    r = @reclassification
    redirect_to reports_general_ledger_path(account_id: r.to_account.id, from: r.from&.iso8601, to: r.to&.iso8601),
                notice: "#{helpers.pluralize(moved, 'line')}#{" for #{r.customer.name}" if r.customer} moved from #{r.from_account.name} to #{r.to_account.name}."
  rescue ActiveRecord::RecordInvalid
    @chosen = true
    render :new, status: :unprocessable_entity
  end

  private

  def choice(source)
    source.permit(:from_account_id, :to_account_id, :from, :to, :customer_id).to_h.merge(organization: Current.organization)
  end

  # Lines can be moved off an archived account, never onto one.
  def load_accounts
    @from_accounts = Plutus::Account.where(tenant: Current.organization).order(:type, :code, :name)
    @to_accounts   = @from_accounts.active
    @customers     = Current.organization.contacts.customers.ordered
  end
end
