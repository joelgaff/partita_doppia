import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// A form's submit moves into the app's navigation bar. The native side adds the
// button; tapping it replies here, which submits the form as the first submit
// button would. The web button stays for the browser and is hidden in the app.
export default class extends BridgeComponent {
  static component = "form"

  connect() {
    super.connect()
    const submitTitle = this.bridgeElement.bridgeAttribute("submit-title")
    this.send("connect", { submitTitle }, () => this.submit())
    this.onStart = () => this.send("submitStarted")
    this.onEnd   = () => this.send("submitEnded")
    this.element.addEventListener("turbo:submit-start", this.onStart)
    this.element.addEventListener("turbo:submit-end", this.onEnd)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.onStart)
    this.element.removeEventListener("turbo:submit-end", this.onEnd)
    super.disconnect()
  }

  submit() {
    const button = this.element.querySelector("input[type=submit], button[type=submit]")
    button ? button.click() : this.element.requestSubmit()
  }
}
