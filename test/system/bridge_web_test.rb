require "application_system_test_case"

# The web halves of the app's bridge components, driven in a real browser that
# wears the app's user agent, with a stand-in for the native adapter recording
# every message. What the native side would receive, without the native side.
class BridgeWebTest < ApplicationSystemTestCase
  NATIVE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 " \
              "Partita Doppia iOS/0.1.0 Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu theme share button];"
  FAKE_ADAPTER = <<~JS
    window.__bridgeMessages = [];
    window.HotwireNative.web.setAdapter({
      platform: "ios",
      supportedComponents: ["form", "menu", "theme", "share", "button"],
      supportsComponent(c) { return this.supportedComponents.includes(c) },
      receive(m) { window.__bridgeMessages.push(m) }
    });
  JS

  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @org.settings.update!(receivable_account: @ar)
    @invoice = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    sign_in_as_launchpad_user(@org)
    @browser_ua = page.evaluate_script("navigator.userAgent")
    page.driver.browser.execute_cdp("Network.setUserAgentOverride", userAgent: NATIVE_UA)
  end

  # The browser outlives the test: put its own user agent back for whatever runs next.
  teardown do
    page.driver.browser.execute_cdp("Network.setUserAgentOverride", userAgent: @browser_ua) if @browser_ua
  end

  def messages
    page.evaluate_script("window.__bridgeMessages")
  end

  def visit_as_app(path)
    visit path
    page.execute_script(FAKE_ADAPTER)
    sleep 0.3
  end

  def message(component, event = "connect")
    messages.find { |m| m["component"] == component && m["event"] == event }
  end

  test "every page tells the app its theme, and again when it changes" do
    visit_as_app "/"
    assert_equal "dark", message("theme")&.dig("data", "theme"), "theme connect: #{messages.inspect}"
    page.execute_script("document.documentElement.dataset.theme = 'light'")
    sleep 0.3
    assert_equal "light", message("theme", "update")&.dig("data", "theme")
  end

  test "a form names its submit, a list its primary action" do
    visit_as_app "/invoices/new"
    assert_equal "Save draft", message("form")&.dig("data", "submitTitle")
    visit_as_app "/invoices"
    assert_equal "New invoice", message("button")&.dig("data", "title")
  end

  test "a document's overflow lists its items, and choosing one clicks it" do
    visit_as_app "/invoices/#{@invoice.id}"
    items = message("menu")&.dig("data", "items")
    assert_equal [ "Print / PDF", "Email", "Copy", "Void", "Delete" ], items.map { |i| i["title"] }
    assert_equal [ false, false, false, true, true ], items.map { |i| i["destructive"] }
    assert_empty message("share").to_a, "share only speaks when Print is chosen"
  end
end
