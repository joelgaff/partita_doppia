require "test_helper"

# Active Storage keeps the filename a client sends with a receipt. The expense
# form posts it as a multipart upload, and the always-mounted direct upload
# endpoint lets a client name a blob before attaching it by signed id.
#
# GHSA-p2pm-g2h6-7j5j: a NUL byte in the name made Filename#base and #extension
# raise ArgumentError, so attaching the receipt, showing it and opening it for
# analysis all failed.
# GHSA-v924-7rp8-4mxh: the tempfile Blob#open hands to the analyzers (libvips,
# ImageMagick, ffprobe) carried the uploaded extension, letting the uploader
# pick the decoder; the fix keeps it only when it matches the content type.
class ActiveStorageFilenameTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )

  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @bank    = create_bank_account(@org, name: "Bank", code: "090")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting", code: "400")
  end

  test "a receipt uploaded with a NUL byte in its name is saved, shown and analyzed" do
    post_expense_with receipt("receipt\0.png")
    assert_redirected_to expenses_path

    expense = @org.documents.expenses.sole
    blob = expense.attachments.sole.blob
    assert_equal "png", blob.filename.extension
    assert blob.filename.base.start_with?("receipt")

    get expense_path(expense)
    assert_response :success
    assert_select "a", text: /\Areceipt/

    perform_enqueued_jobs
    assert blob.reload.analyzed?
    blob.open { |file| assert_equal PNG, file.read }
  end

  test "a directly uploaded receipt with a NUL byte in its name can be attached and shown" do
    post rails_direct_uploads_path, as: :json, params: { blob: {
      filename: "receipt\0.png", byte_size: PNG.bytesize, checksum: OpenSSL::Digest::MD5.base64digest(PNG), content_type: "image/png" } }
    assert_response :success
    upload = response.parsed_body
    put upload["direct_upload"]["url"], params: PNG, headers: upload["direct_upload"]["headers"]

    post_expense_with upload["signed_id"]
    assert_redirected_to expenses_path

    expense = @org.documents.expenses.sole
    get expense_path(expense)
    assert_response :success
    expense.attachments.sole.blob.open { |file| assert_equal PNG, file.read }
  end

  test "a receipt whose extension disagrees with its content does not name the tempfile" do
    post_expense_with receipt("receipt.avs")
    assert_redirected_to expenses_path

    blob = @org.documents.expenses.sole.attachments.sole.blob
    assert_equal "image/png", blob.content_type
    blob.open do |file|
      assert_not_equal ".avs", File.extname(file.path).downcase,
        "an uploader-chosen extension would pick the decoder libvips, ImageMagick or ffprobe runs"
    end
  end

  private

  def post_expense_with(attachment)
    post expenses_path, params: { document: {
      date: "2026-09-01", contact_name: "DO", documentable_attributes: { bank_account_id: @bank.id },
      line_items_attributes: { "0" => { description: "Hosting", quantity: 1, unit_amount: 20, account_id: @hosting.id } },
      attachments: [ attachment ] } }
  end

  # Rack::Test refuses a NUL in a path, so the name the browser sends is set
  # after the file is built; it travels verbatim in the multipart header.
  def receipt(filename)
    file = Tempfile.new([ "receipt", ".png" ]).tap { |f| f.binmode; f.write(PNG); f.rewind }
    Rack::Test::UploadedFile.new(file.path, "image/png", true).tap do |upload|
      upload.instance_variable_set(:@original_filename, filename)
    end
  end
end
