# A document's public link: one per document, found by its token alone. The
# record being there is what "shared" means; rolling replaces it and stopping
# deletes it. It lasts LIFETIME from the day it was made and there is no
# extending: a new link is a new record, with a new token.
class DocumentShare < ApplicationRecord
  LIFETIME = 1.year

  belongs_to :document
  belongs_to :organization, default: -> { document.organization }

  # Readable again on the invoice page, unreadable in a copy of the database.
  # Deterministic so a token can be looked up.
  encrypts :token, deterministic: true
  has_secure_token :token

  scope :live,    -> { where(created_at: LIFETIME.ago..) }
  scope :expired, -> { where(created_at: ...LIFETIME.ago) }

  # The invoice a token opens: approved, not voided, link still in its year.
  # Anything else is nil, and the caller says the same thing for all of it.
  def self.shared_invoice(token)
    return if token.blank?
    document = live.find_by(token: token.to_s)&.document
    document if document&.shareable?
  end

  # Clears links past their year. Expiry is enforced on every lookup; this
  # only keeps dead rows from piling up.
  def self.sweep_expired = expired.delete_all

  def expires_at = created_at + LIFETIME
  def expired?   = expires_at <= Time.current
end
