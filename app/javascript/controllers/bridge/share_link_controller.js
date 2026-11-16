import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// An invoice's share link in the app: Share hands the address itself to the
// native share sheet (Messages, Mail, AirDrop). Its own component, apart from
// "share" which sends a file, so the button only shows in an app that knows it.
export default class extends BridgeComponent {
  static component = "share-link"

  share() {
    this.send("share", { url: this.bridgeElement.bridgeAttribute("url"), title: this.bridgeElement.bridgeAttribute("title") })
  }
}
