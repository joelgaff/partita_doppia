import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Tells the app which theme the page wears, now and whenever it changes, so
// the native bars match.
export default class extends BridgeComponent {
  static component = "theme"

  connect() {
    super.connect()
    this.send("connect", { theme: this.theme })
    this.observer = new MutationObserver(() => this.send("update", { theme: this.theme }))
    this.observer.observe(this.element, { attributes: true, attributeFilter: ["data-theme"] })
  }

  disconnect() {
    this.observer?.disconnect()
    super.disconnect()
  }

  get theme() { return this.element.dataset.theme || "dark" }
}
