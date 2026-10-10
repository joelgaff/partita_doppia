require "test_helper"

# The iOS app is a Hotwire Native shell: native tabs and navigation bars around
# these same pages. When the app asks, the pages drop their own chrome, the app
# can fetch which paths open as modals, and the More tab has a page to show.
class NativeAppTest < ActionDispatch::IntegrationTest
  NATIVE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) Partita Doppia iOS/0.1.0 Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu];"

  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
  end

  test "pages drop the sidebar, titlebar, tabs and status bar for the app" do
    get root_path
    assert_select ".app-titlebar"
    assert_select ".app-nav"
    assert_select ".app-tabs"
    assert_select ".app-statusbar"

    get root_path, headers: { "User-Agent" => NATIVE_UA }
    assert_response :success
    assert_select "body.native"
    assert_select ".app-main"
    assert_select ".app-titlebar", 0
    assert_select ".app-nav", 0
    assert_select ".app-tabs", 0
    assert_select ".app-statusbar", 0
  end

  test "the path configuration is public JSON naming the modal paths" do
    cookies.delete(Ee::Jwt::COOKIE_NAME.to_s)
    get "/configurations/ios_v1.json"
    assert_response :success
    assert_equal "application/json", response.media_type
    config = response.parsed_body
    assert_kind_of Array, config["rules"]
    modal = config["rules"].find { |r| r.dig("properties", "context") == "modal" }
    assert_includes modal["patterns"], "/new$"
    assert_includes modal["patterns"], "/edit$"
    assert_equal false, modal.dig("properties", "pull_to_refresh_enabled")
  end

  test "the More page lists the sections the tabs do not carry, and a way to sign out" do
    get menu_path, headers: { "User-Agent" => NATIVE_UA }
    assert_response :success
    assert_select "title", text: /More/
    %w[Bills Deposits Journal Accounts Banking Reports Contacts Settings].each do |section|
      assert_select "a", text: section
    end
    assert_select "button", text: "Sign out"
  end

  test "the bridge library is pinned for the app's components" do
    get root_path, headers: { "User-Agent" => NATIVE_UA }
    assert_match(/@hotwired\/hotwire-native-bridge/, response.body)
  end

  test "each page has a title of its own: the app's navigation bar shows it, the browser tab adds the app name" do
    @ar = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @org.settings.update!(receivable_account: @ar)
    inv = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)

    { invoices_path => "Invoices", invoice_path(inv) => inv.label, new_invoice_path => "New invoice",
      bank_transactions_path => "Reconcile", root_path => "Home", menu_path => "More", settings_path => "Settings" }.each do |path, title|
      get path, headers: { "User-Agent" => NATIVE_UA }
      assert_select "title", text: title, count: 1
      get path
      assert_select "title", text: "#{title} · Partita Doppia", count: 1
    end
  end
end
