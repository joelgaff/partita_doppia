# The chart of accounts: every ledger account by type, with adding one by hand,
# archiving one that is done with and bringing it back.
class AccountsController < ApplicationController
  TYPES = %w[Asset Liability Equity Revenue Expense].freeze   # the order the chart reads in

  before_action :load_chart,   only: :index
  before_action :load_account, only: %i[archive restore]

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

  def archive
    @account.archive!
    respond_with_chart "#{@account.name} archived."
  rescue ActiveRecord::RecordInvalid
    redirect_to accounts_path, alert: "#{@account.name} #{@account.errors.full_messages.to_sentence}."
  end

  def restore
    @account.restore!
    respond_with_chart "#{@account.name} restored."
  end

  private

  def load_account
    @account = Current.organization.plutus_accounts.find(params[:id])
  end

  def load_chart
    accounts  = Current.organization.plutus_accounts.includes(:bank_account).order(:code, :name).to_a
    @archived = accounts.select(&:archived?)
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
