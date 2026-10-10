import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// A document's overflow (Print, Email, Copy, Void, Delete) as a native menu in
// the navigation bar. The items are the page's own links and buttons; the native
// side shows their titles and replies with the index of the one chosen, which
// is then clicked here, confirmations and all.
export default class extends BridgeComponent {
  static component = "menu"
  static targets = ["item"]

  connect() {
    super.connect()
    const items = this.itemTargets.map((el, index) => ({
      index, title: el.dataset.bridgeTitle, destructive: el.hasAttribute("data-bridge-destructive")
    }))
    if (items.length === 0) return
    this.send("connect", { items }, message => {
      const item = this.itemTargets[message.data.index]
      if (item) item.click()
    })
  }
}
