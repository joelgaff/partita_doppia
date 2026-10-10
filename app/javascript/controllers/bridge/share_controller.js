import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Print / PDF in the app: the PDF goes to the native share sheet (AirDrop, Mail,
// Files) instead of opening the print page. In the browser the link works as is.
export default class extends BridgeComponent {
  static component = "share"

  share(event) {
    if (!this.bridge.supportsComponent(this.component)) return
    event.preventDefault()
    const url = new URL(this.bridgeElement.bridgeAttribute("url"), window.location.href).toString()
    this.send("share", { url, title: document.title })
  }

  get component() { return this.constructor.component }
}
