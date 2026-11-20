module Billing
  # The invoice lines for billable costs picked up on an invoice: one line per
  # expense line, marked up on the unit price, tax and tracking carried across,
  # the account from the cost account's pairing, else Settings, else the cost's
  # own (see BillingIncome). Built on the invoice, not saved;
  # the form shows them and the save stores them like any other line.
  class PickUp
    def initialize(invoice, costs, markup: 0)
      @invoice = invoice
      @costs   = Array(costs)
      @factor  = 1 + markup.to_s.strip.to_d / 100
      @fallback = invoice.organization.settings.billable_income_account
    end

    def lines
      eligible.flat_map do |cost|
        cost.line_items.map do |src|
          line = @invoice.line_items.build(description: src.description, quantity: src.quantity,
                                           unit_amount: marked_up(src.unit_amount), account: income_account_for(src.account),
                                           tax_rate: src.tax_rate, rebills: cost)
          src.copy_tracking_to(line)
          line
        end
      end
    end

    private

    # The customer's own, unbilled costs; anything else offered is ignored.
    def eligible
      @costs.select { |c| c.billable_to && c.billable_to == @invoice.contact && !c.billed? }
    end

    # Where a cost on this account is billed: its pairing while that account is in use, then the fallback, then itself.
    def income_account_for(account)
      paired = account.billing_income_account
      (paired unless paired&.archived?) || @fallback || account
    end

    def marked_up(amount) = (amount.to_d * @factor).round(2)
  end
end
