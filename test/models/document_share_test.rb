require "test_helper"

# An invoice can carry one public link: a token on its own small record. The
# link is made by hand, can be rolled or stopped, and dies a year after it was
# made. Only an approved, live invoice is ever found by it.
class DocumentShareTest < ActiveSupport::TestCase
  setup do
    @org   = organizations(:one)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @org.settings.update!(receivable_account: @ar)
    @invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
  end

  test "an invoice has no link until one is made, and then exactly one" do
    assert_nil @invoice.share
    share = @invoice.start_sharing!
    assert_match(/\A[A-Za-z0-9]{24}\z/, share.token)
    assert_equal @org, share.organization
    assert_equal share, @invoice.start_sharing!, "asking again hands back the same link"
    assert_equal 1, DocumentShare.where(document: @invoice).count
  end

  test "the token finds the invoice, and is not kept in the clear" do
    share = @invoice.start_sharing!
    assert_equal @invoice, DocumentShare.shared_invoice(share.token)
    stored = DocumentShare.connection.select_value("SELECT token FROM document_shares WHERE id = #{share.id}")
    assert_not_includes stored, share.token
    assert_nil DocumentShare.shared_invoice("nope")
    assert_nil DocumentShare.shared_invoice(nil)
    assert_nil DocumentShare.shared_invoice("")
  end

  test "rolling swaps the token: the old one stops, the new one works, the year starts again" do
    old = @invoice.start_sharing!.token
    travel 200.days do
      fresh = @invoice.roll_share!
      assert_not_equal old, fresh.token
      assert_nil DocumentShare.shared_invoice(old)
      assert_equal @invoice, DocumentShare.shared_invoice(fresh.token)
      assert_equal (Time.current + 1.year).to_date, fresh.expires_at.to_date
      assert_equal 1, DocumentShare.where(document: @invoice).count
    end
  end

  test "stopping removes the link" do
    token = @invoice.start_sharing!.token
    @invoice.stop_sharing!
    assert_nil @invoice.reload.share
    assert_nil DocumentShare.shared_invoice(token)
  end

  test "a link lasts one year from the day it was made" do
    share = @invoice.start_sharing!
    assert_equal (share.created_at + 1.year), share.expires_at

    travel_to share.expires_at - 1.minute do
      assert_equal @invoice, DocumentShare.shared_invoice(share.token)
      assert_equal share, @invoice.reload.live_share
    end
    travel_to share.expires_at + 1.minute do
      assert_nil DocumentShare.shared_invoice(share.token)
      assert_nil @invoice.reload.live_share, "an expired link reads as not shared"
      fresh = @invoice.start_sharing!
      assert_not_equal share.token, fresh.token, "making a link after expiry makes a new one"
      assert_equal 1, DocumentShare.where(document: @invoice).count
    end
  end

  test "paying the invoice leaves the link alone" do
    token = @invoice.start_sharing!.token
    bank  = create_bank_account(@org, name: "Checking", code: "1000")
    @invoice.payments.create!(organization: @org, amount: 100, paid_on: Date.current, bank_account: bank)
    assert @invoice.reload.paid?
    assert_equal @invoice, DocumentShare.shared_invoice(token)
  end

  test "a draft can't be shared, and only invoices can" do
    @invoice.unapprove!
    assert_not @invoice.shareable?
    assert_raises(ActiveRecord::RecordInvalid) { @invoice.start_sharing! }
    assert_nil @invoice.share

    payable = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    rent    = Plutus::Expense.create!(tenant: @org, name: "Rent", code: "6000")
    bill    = create_bill(@org, vendor: "Landlord", amount: 50, category: rent, payable: payable, state: "approved")
    assert_not bill.shareable?
    assert_raises(ActiveRecord::RecordInvalid) { bill.start_sharing! }
  end

  test "voiding an invoice or sending it back to draft ends its link for good" do
    token = @invoice.start_sharing!.token
    @invoice.unapprove!
    assert_nil DocumentShare.shared_invoice(token)
    @invoice.approve!
    assert_nil DocumentShare.shared_invoice(token), "approving again does not bring the old link back"
    assert_nil @invoice.reload.share

    token = @invoice.start_sharing!.token
    @invoice.void!
    assert_nil DocumentShare.shared_invoice(token)
    assert_nil @invoice.reload.share
  end

  test "a link that outlived its invoice's standing is not honoured even if the record is still there" do
    share = @invoice.start_sharing!
    @invoice.update_columns(state: "draft")
    assert_nil DocumentShare.shared_invoice(share.token)
    @invoice.update_columns(state: "approved", voided_at: Time.current)
    assert_nil DocumentShare.shared_invoice(share.token)
  end

  test "the history says who made, rolled and stopped the link" do
    Current.user = users(:one)
    share = @invoice.start_sharing!
    @invoice.roll_share!
    @invoice.stop_sharing!
    events = @invoice.events.order(:id).last(3)
    assert_equal [ "Share link created", "Share link rolled", "Share link stopped" ], events.map(&:title)
    assert_equal [ users(:one) ] * 3, events.map(&:user)
    assert_equal [ "Expires #{share.expires_at.strftime('%b %-d, %Y')}" ], events.first.detail_lines
    assert_no_match(/#{share.token}/, events.map { |e| e.details.to_json }.join)
  ensure
    Current.reset
  end

  test "deleting the invoice takes its link with it" do
    @invoice.start_sharing!
    assert_difference -> { DocumentShare.count }, -1 do
      @invoice.destroy!
    end
  end

  test "sweeping deletes links past their year and leaves the rest" do
    old   = @invoice.start_sharing!
    other = create_invoice(@org, client_name: "Globex", amount: 40, receivable: @ar, revenue: @sales)
    travel 366.days do
      keep = other.start_sharing!
      assert_equal 1, DocumentShare.sweep_expired
      assert_equal [ keep.id ], DocumentShare.pluck(:id)
      assert_not DocumentShare.exists?(old.id)
    end
  end
end
