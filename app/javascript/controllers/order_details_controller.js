import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["heading", "status"]

  connect() {
    this.focusHeading()
  }

  loading() {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = "Loading order details…"
    this.statusTarget.classList.add("is-loading")
  }

  loaded() {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Order details loaded."
      this.statusTarget.classList.remove("is-loading")
    }

    this.focusHeading()
  }

  focusHeading() {
    if (!this.hasHeadingTarget) return

    requestAnimationFrame(() => this.headingTarget.focus())
  }
}
