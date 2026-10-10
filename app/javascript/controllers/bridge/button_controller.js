import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// A list page's primary action ("New invoice") as a + in the app's navigation
// bar. The link's own text names it; the native tap replies and the link is clicked.
export default class extends BridgeComponent {
  static component = "button"

  connect() {
    super.connect()
    const title = this.element.textContent.trim()
    this.send("connect", { title }, () => this.element.click())
  }
}
