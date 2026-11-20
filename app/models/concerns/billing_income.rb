# An expense account's pairing (mixed into Plutus::Account): the income account
# its costs are billed as when a customer's invoice picks them up. Without one
# the pick-up falls back to the account Settings names, then to the cost's own
# (see Billing::PickUp). Only an expense account has a pairing.
module BillingIncome
  extend ActiveSupport::Concern

  included do
    belongs_to :billing_income_account, class_name: "Plutus::Account", optional: true
    has_many :billed_from_accounts, class_name: "Plutus::Account", foreign_key: :billing_income_account_id,
             inverse_of: :billing_income_account, dependent: :nullify
    validate :billing_income_pairing, if: :billing_income_account_id_changed?
  end

  def billable_cost_account? = is_a?(Plutus::Expense)

  private

  def billing_income_pairing
    return if billing_income_account_id.nil?
    return errors.add(:billing_income_account, "applies to this account's costs: only an expense account has one") unless billable_cost_account?
    income = billing_income_account
    if !income.is_a?(Plutus::Revenue) || income.tenant_id != tenant_id
      errors.add(:billing_income_account, "must be a revenue account")
    elsif income.archived?
      errors.add(:billing_income_account, "#{income.name} is archived; restore it first")
    end
  end
end
