# An invoice's public link (see DocumentShare), from the invoice page: create
# makes it, update rolls it to a new token, destroy stops it.
class Invoices::SharesController < ApplicationController
  before_action :set_document

  def create
    @document.start_sharing!
    respond "Share link created."
  end

  def update
    @document.roll_share!
    respond "Share link rolled. The old link no longer works."
  end

  def destroy
    @document.stop_sharing!
    respond "Sharing stopped. The link no longer works."
  end

  private

  def set_document
    @document = Current.organization.documents.invoices.find(params[:invoice_id])
  end

  def respond(notice)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(helpers.dom_id(@document, :share), partial: "invoices/share", locals: { document: @document }) }
      format.html { redirect_to invoice_path(@document), notice: notice }
    end
  end

  rescue_from ActiveRecord::RecordInvalid do
    redirect_to invoice_path(@document), alert: "#{@document.label} can't be shared#{@document.draft? ? '; approve it first' : ''}."
  end
end
