# The page a share link opens (see DocumentShare). No sign-in: the token in the
# path is the whole of the permission, so the invoice is found by it and by
# nothing else, and a link that doesn't work gets one answer whatever the reason.
class Public::InvoicesController < ApplicationController
  allow_unauthenticated
  skip_before_action :set_organization   # the token names the organisation, not the session

  rate_limit to: 60, within: 1.minute, with: -> { head :too_many_requests }

  before_action :keep_private
  before_action :set_document

  layout "public"

  def show
    respond_to do |format|
      format.html
      format.pdf { send_data InvoicePdf.new(@document).render, filename: InvoicePdf.filename(@document), type: "application/pdf", disposition: "inline" }
    end
  end

  private

  def set_document
    @document = DocumentShare.shared_invoice(params[:token])
    return render_not_found if @document.nil?
    Current.organization = @document.organization
  end

  # Unknown, rolled, stopped, expired, voided or draft: all the same page.
  def render_not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false, formats: :html, content_type: "text/html"
  end

  # Not for search engines, shared caches, or the next site's referrer log.
  def keep_private
    no_store
    response.headers["X-Robots-Tag"]    = "noindex, nofollow, noarchive"
    response.headers["Referrer-Policy"] = "no-referrer"
  end
end
