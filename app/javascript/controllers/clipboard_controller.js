import { Controller } from "@hotwired/stimulus"

// Copy a field's text: the share link on an invoice. The button says so for a moment.
export default class extends Controller {
  static targets = ["source", "button"]

  select() { this.sourceTarget.select() }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.sourceTarget.value)
    } catch {
      this.sourceTarget.select()          // no clipboard API here: the old way
      document.execCommand("copy")
    }
    this.said("Copied")
  }

  said(word) {
    if (!this.hasButtonTarget) return
    this.label ??= this.buttonTarget.textContent
    this.buttonTarget.textContent = word
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { this.buttonTarget.textContent = this.label }, 2000)
  }

  disconnect() { clearTimeout(this.timer) }
}
