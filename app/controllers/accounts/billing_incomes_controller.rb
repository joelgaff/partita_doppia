# Pair the ticked expense accounts with one income account, or with none, in
# one go from the chart (see BillingIncome). All of them or none of them.
class Accounts::BillingIncomesController < ApplicationController
  def update
    accounts = Current.organization.plutus_accounts.find(Array(params[:account_ids]))
    return redirect_to(back_to_chart, alert: "Tick at least one expense account.") if accounts.empty?

    income = Current.organization.plutus_accounts.find(params[:billing_income_account_id]) if params[:billing_income_account_id].present?
    Plutus::Account.transaction { accounts.each { |account| account.update!(billing_income_account: income) } }
    redirect_to back_to_chart, notice: "#{helpers.pluralize(accounts.size, 'account')} now #{accounts.one? ? 'bills' : 'bill'} as #{income&.name || 'the fallback in Settings'}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to back_to_chart, alert: "#{e.record.name}: #{e.record.errors.full_messages.to_sentence}. Nothing was changed."
  end

  private

  def back_to_chart = accounts_path(q: params[:q].presence)
end
