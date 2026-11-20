# The chart of accounts: every ledger account by type, with adding one by hand,
# editing it, archiving one that is done with and bringing it back.
class AccountsController < ApplicationController
  TYPES = %w[Asset Liability Equity Revenue Expense].freeze   # the order the chart reads in

  before_action :load_chart,   only: :index
  before_action :load_account, only: %i[edit update archive restore]
  before_action :send_bank_accounts_to_banking, only: %i[edit update]

  def index; end

  def new
    @account = Plutus::Expense.new
  end

  def create
    @account = build_account
    if @account.errors.none? && @account.save
      redirect_to accounts_path, notice: "#{@account.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_income_accounts
  end

  # Its type stays as it was made: changing it would move its history between reports.
  def update
    attrs = params.require(:account).permit(:name, :code, :description, :billing_income_account_id)
    attrs = attrs.to_h.transform_values { |v| v.to_s.strip.presence }
    if @account.update(attrs)
      redirect_to accounts_path, notice: "#{@account.name} saved."
    else
      load_income_accounts
      render :edit, status: :unprocessable_entity
    end
  end

  def archive
    @account.archive!
    respond_with_chart "#{@account.name} archived."
  rescue ActiveRecord::RecordInvalid
    redirect_to accounts_path, alert: "#{@account.name} #{@account.errors.full_messages.to_sentence}."
  end

  def restore
    return redirect_to(accounts_path, alert: "#{@account.name} is a bank account; restore it under Banking.") if @account.bank_account
    @account.restore!
    respond_with_chart "#{@account.name} restored."
  end

  private

  def load_account
    @account = Current.organization.plutus_accounts.find(params[:id])
  end

  # A bank account's name and number are the bank account's; its ledger side follows.
  def send_bank_accounts_to_banking
    redirect_to edit_bank_account_path(@account.bank_account) if @account.bank_account
  end

  def load_income_accounts
    @income_accounts = Plutus::Revenue.where(tenant: Current.organization).active.order(:code, :name)
  end

  def load_chart
    @q        = params[:q].to_s.strip
    accounts  = Current.organization.plutus_accounts.includes(:bank_account, :billing_income_account).order(:code, :name)
    accounts  = accounts.matching(@q) if @q.present?
    accounts  = accounts.to_a
    @archived = accounts.select(&:archived?)
    load_income_accounts
    @grouped  = (accounts - @archived).group_by { |a| a.type.demodulize }.sort_by { |type, _| TYPES.index(type) || TYPES.size }
  end

  # The type picks the class; anything but the five is an error on the form.
  def build_account
    attrs = params.require(:account).permit(:type, :name, :code, :description)
    klass = TYPES.include?(attrs[:type]) ? Plutus.const_get(attrs[:type]) : Plutus::Expense
    klass.new(tenant: Current.organization, name: attrs[:name].to_s.strip, code: attrs[:code].to_s.strip.presence,
              description: attrs[:description].to_s.strip.presence).tap do |account|
      account.errors.add(:type, :inclusion) unless TYPES.include?(attrs[:type])
    end
  end

  def respond_with_chart(notice)
    respond_to do |format|
      format.turbo_stream do
        load_chart
        render turbo_stream: turbo_stream.replace(helpers.dom_id(Current.organization, :chart), partial: "accounts/chart")
      end
      format.html { redirect_to accounts_path, notice: notice }
    end
  end
end
