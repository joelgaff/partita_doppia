require "test_helper"

class EmailSenderSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
  end

  test "the Organisation panel sets the sender name and reply-to, and refuses a bad address" do
    get settings_path
    assert_select "input[name='organization_settings[email_from_name]']"
    assert_select "input[name='organization_settings[email_reply_to]']"
    assert_match(/#{Regexp.escape(ApplicationMailer.sending_address)}/, response.body, "the page says which address mail leaves from")

    patch emailing_settings_path, params: { organization_settings: { email_from_name: "EE Timing Billing", email_reply_to: "joel@enduranceevolution.example" } }
    assert_redirected_to settings_path
    settings = @org.settings.reload
    assert_equal "EE Timing Billing", settings.email_from_name
    assert_equal "joel@enduranceevolution.example", settings.email_reply_to

    patch emailing_settings_path, params: { organization_settings: { email_from_name: "", email_reply_to: "not an address" } }
    assert_redirected_to settings_path
    assert_match(/reply/i, flash[:alert])
    assert_equal "joel@enduranceevolution.example", settings.reload.email_reply_to

    patch emailing_settings_path, params: { organization_settings: { email_from_name: "", email_reply_to: "" } }
    assert_nil settings.reload.email_from_name
    assert_nil settings.email_reply_to
  end

  test "a copy-to-me address and a mailing address are kept with the organisation" do
    get settings_path
    assert_select "input[name='organization_settings[email_copy_to]']"
    assert_select "textarea[name='organization_settings[mailing_address]']"

    patch emailing_settings_path, params: { organization_settings: { email_from_name: "", email_reply_to: "", email_copy_to: "me@enduranceevolution.example" } }
    assert_equal "me@enduranceevolution.example", @org.settings.reload.email_copy_to
    patch emailing_settings_path, params: { organization_settings: { email_from_name: "", email_reply_to: "", email_copy_to: "nope" } }
    assert_match(/copy/i, flash[:alert])
    assert_equal "me@enduranceevolution.example", @org.settings.reload.email_copy_to

    patch mailing_settings_path, params: { organization_settings: { mailing_address: "  PO Box 12\nTraverse City, MI 49684  " } }
    assert_redirected_to settings_path
    assert_equal "PO Box 12\nTraverse City, MI 49684", @org.settings.reload.mailing_address
    patch mailing_settings_path, params: { organization_settings: { mailing_address: "" } }
    assert_nil @org.settings.reload.mailing_address
  end
end
