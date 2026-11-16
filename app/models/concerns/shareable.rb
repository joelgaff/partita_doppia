# A public link to a document (see DocumentShare). Made by hand, one at a
# time; every change is a line in the document's history.
module Shareable
  extend ActiveSupport::Concern

  included do
    has_one :share, class_name: "DocumentShare", dependent: :destroy
  end

  # Invoices only for now, and only ones a customer could be sent.
  def shareable? = invoice? && approved? && !voided?

  # The link while it works; an expired one reads as none.
  def live_share = share&.expired? ? nil : share

  # The link, made if there isn't a working one.
  def start_sharing!
    live_share || replace_share(:shared)
  end

  # A new token and a new year; the old link stops at once.
  def roll_share! = replace_share(:share_rolled)

  def stop_sharing!
    return if share.nil?
    transaction do
      end_share
      record_event!(:share_stopped)
    end
  end

  private

  def replace_share(event)
    unless shareable?
      errors.add(:base, "can't be shared")
      raise ActiveRecord::RecordInvalid.new(self)
    end
    transaction do
      end_share
      create_share!.tap { |fresh| record_event!(event, expires_on: fresh.expires_at.to_date) }
    end
  end

  # Quietly: the caller writes whatever history line fits.
  def end_share
    share&.destroy!
    association(:share).reset
  end
end
