import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.narrowScreen = window.matchMedia("(max-width: 62rem)")
    this.startLoadingBound = this.startLoading.bind(this)
    this.finishLoadingBound = this.finishLoading.bind(this)
    this.screenChangedBound = this.screenChanged.bind(this)
    this.keydownBound = this.keydown.bind(this)

    this.element.addEventListener("turbo:before-fetch-request", this.startLoadingBound)
    this.element.addEventListener("turbo:frame-load", this.finishLoadingBound)
    this.narrowScreen.addEventListener("change", this.screenChangedBound)
    window.addEventListener("keydown", this.keydownBound)

    if (this.element.classList.contains("order-details-frame--empty")) {
      this.restoreOriginFocus()
    } else {
      this.finishLoading()
    }
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-fetch-request", this.startLoadingBound)
    this.element.removeEventListener("turbo:frame-load", this.finishLoadingBound)
    this.narrowScreen.removeEventListener("change", this.screenChangedBound)
    window.removeEventListener("keydown", this.keydownBound)
    this.setBackgroundInert(false)
  }

  startLoading() {
    this.returnUrl = window.location.href
    this.rememberOriginFocus()
    this.element.classList.remove("order-details-frame--empty")
    this.element.setAttribute("aria-busy", "true")

    const status = document.createElement("div")
    status.className = "order-details-loading"
    status.setAttribute("role", "status")
    status.setAttribute("aria-live", "polite")
    status.innerHTML = '<h2 id="order-details-loading-heading">Loading order details</h2><p>Please wait…</p>'
    this.element.replaceChildren(status)
    this.updateOverlaySemantics("order-details-loading-heading")
    const heading = status.querySelector("h2")
    heading.setAttribute("tabindex", "-1")
    requestAnimationFrame(() => heading.focus())
  }

  finishLoading() {
    this.element.classList.remove("order-details-frame--empty")
    this.element.removeAttribute("aria-busy")

    const heading = this.element.querySelector("h1[id], h2[id]")
    this.updateOverlaySemantics(heading?.id)

    if (heading) {
      heading.setAttribute("tabindex", "-1")
      requestAnimationFrame(() => heading.focus())
    }
  }

  screenChanged() {
    const heading = this.element.querySelector("h1[id], h2[id]")
    this.updateOverlaySemantics(heading?.id)
  }

  keydown(event) {
    if (!this.isModal()) return

    if (event.key === "Escape") {
      event.preventDefault()
      const close = this.element.querySelector("[data-order-details-close]")
      if (close) {
        close.click()
      } else if (this.returnUrl) {
        window.Turbo.visit(this.returnUrl, { action: "replace" })
      }
      return
    }

    if (event.key !== "Tab") return

    const focusable = Array.from(this.element.querySelectorAll(
      'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])'
    )).filter((node) => node.getClientRects().length > 0)
    if (focusable.length === 0) return

    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    const focusedHeading = document.activeElement?.matches("h1[tabindex='-1'], h2[tabindex='-1']")
    if (event.shiftKey && (document.activeElement === first || focusedHeading)) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  updateOverlaySemantics(headingId) {
    const open = !this.element.classList.contains("order-details-frame--empty")
    if (open && this.narrowScreen.matches) {
      this.element.setAttribute("role", "dialog")
      this.element.setAttribute("aria-modal", "true")
      if (headingId) this.element.setAttribute("aria-labelledby", headingId)
      this.setBackgroundInert(true)
    } else {
      this.element.removeAttribute("role")
      this.element.removeAttribute("aria-modal")
      this.element.removeAttribute("aria-labelledby")
      this.setBackgroundInert(false)
    }
  }

  isModal() {
    return this.element.getAttribute("aria-modal") === "true"
  }

  setBackgroundInert(inert) {
    document.querySelectorAll(".admin-sidebar, .page-header, .filter-card, .orders-card").forEach((node) => {
      node.inert = inert
    })
  }

  rememberOriginFocus() {
    const link = document.activeElement?.closest("[data-order-id]")
    if (!link) return

    try {
      sessionStorage.setItem("admin-order-return-focus", link.dataset.orderId)
    } catch (_error) {
      // Focus restoration is progressive enhancement when storage is unavailable.
    }
  }

  restoreOriginFocus() {
    let orderId
    try {
      orderId = sessionStorage.getItem("admin-order-return-focus")
      sessionStorage.removeItem("admin-order-return-focus")
    } catch (_error) {
      return
    }
    if (!orderId) return

    const link = Array.from(document.querySelectorAll("[data-order-id]"))
      .find((candidate) => candidate.dataset.orderId === orderId)
    if (link) requestAnimationFrame(() => link.focus())
  }
}
