import { Controller } from "@hotwired/stimulus"

// A list of tick boxes with one box over them all, a running count, and a
// submit that waits for at least one tick. The form works without it.
export default class extends Controller {
  static targets = ["box", "all", "count", "submit"]

  connect() { this.refresh() }

  toggleAll() {
    this.boxTargets.forEach((box) => { if (!box.disabled) box.checked = this.allTarget.checked })
    this.refresh()
  }

  refresh() {
    const ticked = this.boxTargets.filter((box) => box.checked).length
    this.countTargets.forEach((el) => { el.textContent = ticked })
    if (this.hasSubmitTarget) this.submitTarget.disabled = ticked === 0
    if (this.hasAllTarget) {
      this.allTarget.checked = ticked > 0 && ticked === this.boxTargets.length
      this.allTarget.indeterminate = ticked > 0 && ticked < this.boxTargets.length
    }
  }
}
