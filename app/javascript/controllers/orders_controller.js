import { Controller } from "@hotwired/stimulus"

const STRATEGIES = Object.freeze({
  n_plus_one: {
    label: "N+1 intencional",
    help: "Carrega as associações uma a uma de propósito. Compare as consultas e os tempos no terminal."
  },
  lazy_loading: {
    label: "Lazy loading",
    help: "Carrega cada associação quando ela é acessada; neste exemplo, pode repetir o mesmo padrão do N+1. Compare os logs no terminal."
  },
  includes: {
    label: "Eager loading com includes",
    help: "Deixa o Rails escolher como pré-carregar as associações. Compare as consultas e os tempos no terminal."
  },
  preload: {
    label: "Eager loading com preload",
    help: "Pré-carrega as associações em consultas separadas e em lote. Compare as consultas e os tempos no terminal."
  },
  eager_load: {
    label: "Eager loading com eager_load",
    help: "Pré-carrega as associações com LEFT OUTER JOIN. Compare as consultas e os tempos no terminal."
  },
  joins: {
    label: "JOIN de cliente via joins",
    help: "Executa joins(:customer): aplica INNER JOIN apenas ao cliente e não pré-carrega nenhuma associação."
  },
  raw_sql: {
    label: "SQL puro (PostgreSQL)",
    help: "Executa uma única consulta SQL do PostgreSQL, com agregações JSONB e LATERAL, sem carregar associações pelo Active Record. Não é portátil para outros bancos."
  }
})

export default class extends Controller {
  static targets = ["button", "error", "results", "status", "strategy", "strategyHelp"]
  static values = { url: String }

  connect() {
    this.updateStrategyHelp()
  }

  async load() {
    const selection = this.selectedStrategy()
    this.startLoading(selection)

    try {
      if (!selection) throw new Error("Invalid selected strategy")

      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("strategy", selection.requested)

      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })

      if (!response.ok) throw new Error(`Request failed with status ${response.status}`)

      const payload = await response.json()
      this.validatePayload(payload, selection)

      this.renderOrders(payload.orders, selection)
    } catch (_error) {
      this.showError(selection)
    } finally {
      this.finishLoading()
    }
  }

  selectedStrategy() {
    const requested = this.strategyTarget.value
    const strategy = STRATEGIES[requested]

    if (!strategy) return null

    return { requested, ...strategy }
  }

  updateStrategyHelp() {
    const selection = this.selectedStrategy()
    this.strategyHelpTarget.textContent = selection?.help || ""
  }

  validatePayload(payload, selection) {
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) throw new Error("Invalid orders response")
    if (!Array.isArray(payload.orders)) throw new Error("Invalid orders response")

    const strategy = payload.strategy
    if (!strategy || typeof strategy !== "object" || Array.isArray(strategy)) throw new Error("Invalid strategy response")
    if (strategy.requested !== selection.requested) throw new Error("Mismatched strategy response")
    if (strategy.effective !== selection.requested) throw new Error("Invalid effective strategy")
    if (strategy.implemented !== true) throw new Error("Invalid implementation status")
  }

  startLoading(selection) {
    this.buttonTarget.disabled = true
    this.strategyTarget.disabled = true
    this.buttonTarget.textContent = "Buscando…"
    this.resultsTarget.replaceChildren()
    this.resultsTarget.setAttribute("aria-busy", "true")
    this.statusTarget.textContent = selection ? `Buscando até 250 pedidos com ${selection.label}…` : ""
    this.errorTarget.hidden = true
    this.errorTarget.textContent = ""
  }

  finishLoading() {
    this.buttonTarget.disabled = false
    this.strategyTarget.disabled = false
    this.buttonTarget.textContent = "Buscar pedidos"
    this.resultsTarget.setAttribute("aria-busy", "false")
  }

  renderOrders(orders, strategy) {
    if (orders.length === 0) {
      this.statusTarget.textContent = `Nenhum pedido encontrado com ${strategy.label}.`
      return
    }

    const list = document.createElement("ul")
    list.className = "orders-list"

    orders.forEach((order) => list.append(this.buildOrderItem(order)))
    this.resultsTarget.append(list)

    const noun = orders.length === 1 ? "pedido encontrado" : "pedidos encontrados"
    this.statusTarget.textContent = `${orders.length} ${noun} com ${strategy.label}.`
  }

  buildOrderItem(order) {
    const item = document.createElement("li")
    item.className = "order-card"
    const safeOrder = order && typeof order === "object" ? order : {}
    const heading = document.createElement("h2")
    const baseDetails = document.createElement("dl")
    const relatedDetails = document.createElement("details")
    const summary = document.createElement("summary")
    const relatedContent = document.createElement("div")
    const items = this.collection(safeOrder.items)
    const payments = this.collection(safeOrder.payments)
    const reviews = this.collection(safeOrder.reviews)

    heading.textContent = `Pedido ${this.displayValue(safeOrder.order_id)}`
    this.appendDetail(baseDetails, "Código do pedido", this.displayValue(safeOrder.order_id))
    this.appendDetail(baseDetails, "Status", this.displayValue(safeOrder.status))
    this.appendDetail(baseDetails, "Comprado em", this.formatDate(safeOrder.purchase_at))
    this.appendDetail(baseDetails, "Entrega estimada", this.formatDate(safeOrder.estimated_delivery_at))
    this.appendDetail(baseDetails, "Entregue em", this.formatDate(safeOrder.delivered_customer_at))

    relatedDetails.className = "order-related"
    summary.textContent = `Ver dados relacionados — ${this.quantity(items.length, "item", "itens")}, ${this.quantity(payments.length, "pagamento", "pagamentos")}, ${this.quantity(reviews.length, "avaliação", "avaliações")}`
    relatedContent.className = "order-related-content"
    relatedContent.append(
      this.buildCustomerSection(safeOrder.customer),
      this.buildItemsSection(items),
      this.buildPaymentsSection(payments),
      this.buildReviewsSection(reviews)
    )
    relatedDetails.append(summary, relatedContent)

    item.append(heading, baseDetails, relatedDetails)
    return item
  }

  buildCustomerSection(customer) {
    const section = this.section("Cliente")

    if (!customer || typeof customer !== "object" || Array.isArray(customer)) {
      section.append(this.emptyMessage("Cliente não informado."))
      return section
    }

    const details = document.createElement("dl")
    this.appendDetail(details, "ID do cliente", this.displayValue(customer.customer_id))
    this.appendDetail(details, "ID único do cliente", this.displayValue(customer.customer_unique_id))
    this.appendDetail(details, "Cidade", this.displayValue(customer.city))
    this.appendDetail(details, "Estado", this.displayValue(customer.state))
    section.append(details)
    return section
  }

  buildItemsSection(items) {
    const section = this.section("Itens")

    if (items.length === 0) {
      section.append(this.emptyMessage("Nenhum item relacionado."))
      return section
    }

    section.append(this.relatedList(items, (item) => {
      const details = document.createElement("dl")
      this.appendDetail(details, "Número do item", this.displayValue(item.order_item_id))
      this.appendDetail(details, "ID do produto", this.displayValue(item.product_id))
      this.appendDetail(details, "ID do vendedor", this.displayValue(item.seller_id))
      this.appendDetail(details, "Preço", this.formatMoney(item.price))
      this.appendDetail(details, "Frete", this.formatMoney(item.freight_value))
      return details
    }))
    return section
  }

  buildPaymentsSection(payments) {
    const section = this.section("Pagamentos")

    if (payments.length === 0) {
      section.append(this.emptyMessage("Nenhum pagamento relacionado."))
      return section
    }

    section.append(this.relatedList(payments, (payment) => {
      const details = document.createElement("dl")
      this.appendDetail(details, "Sequência", this.displayValue(payment.payment_sequential))
      this.appendDetail(details, "Tipo", this.displayValue(payment.payment_type))
      this.appendDetail(details, "Parcelas", this.displayValue(payment.payment_installments))
      this.appendDetail(details, "Valor", this.formatMoney(payment.payment_value))
      return details
    }))
    return section
  }

  buildReviewsSection(reviews) {
    const section = this.section("Avaliações")

    if (reviews.length === 0) {
      section.append(this.emptyMessage("Nenhuma avaliação relacionada."))
      return section
    }

    section.append(this.relatedList(reviews, (review) => {
      const details = document.createElement("dl")
      this.appendDetail(details, "ID da avaliação", this.displayValue(review.review_id))
      this.appendDetail(details, "Nota", this.displayValue(review.score))
      this.appendDetail(details, "Título", this.displayValue(review.comment_title))
      this.appendDetail(details, "Comentário", this.displayValue(review.comment_message))
      this.appendDetail(details, "Criada em", this.formatDate(review.creation_at))
      this.appendDetail(details, "Respondida em", this.formatDate(review.answer_at))
      return details
    }))
    return section
  }

  section(title) {
    const section = document.createElement("section")
    const heading = document.createElement("h3")

    heading.textContent = title
    section.append(heading)
    return section
  }

  relatedList(records, buildContent) {
    const list = document.createElement("ul")
    list.className = "order-related-list"

    records.forEach((record) => {
      const item = document.createElement("li")
      const safeRecord = record && typeof record === "object" ? record : {}
      item.append(buildContent(safeRecord))
      list.append(item)
    })
    return list
  }

  emptyMessage(message) {
    const paragraph = document.createElement("p")
    paragraph.className = "order-related-empty"
    paragraph.textContent = message
    return paragraph
  }

  appendDetail(details, label, value) {
    const group = document.createElement("div")
    const term = document.createElement("dt")
    const description = document.createElement("dd")

    term.textContent = label
    description.textContent = value
    group.append(term, description)
    details.append(group)
  }

  displayValue(value) {
    if (typeof value === "string") return value.trim() ? value : "Não informado"
    if (typeof value === "number" && Number.isFinite(value)) return String(value)

    return "Não informado"
  }

  collection(value) {
    return Array.isArray(value) ? value : []
  }

  quantity(count, singular, plural) {
    return `${count} ${count === 1 ? singular : plural}`
  }

  formatMoney(value) {
    if ((typeof value !== "string" && typeof value !== "number") || value === "") return "Não informado"

    const amount = Number(value)
    if (!Number.isFinite(amount)) return "Não informado"

    return new Intl.NumberFormat("pt-BR", {
      style: "currency",
      currency: "BRL",
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(amount)
  }

  formatDate(value) {
    if (typeof value !== "string" || !value) return "Não informado"

    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return "Não informado"

    return new Intl.DateTimeFormat("pt-BR", {
      dateStyle: "short",
      timeStyle: "short"
    }).format(date)
  }

  showError(strategy) {
    this.statusTarget.textContent = ""
    const label = strategy?.label || "a estratégia selecionada"
    this.errorTarget.textContent = `Não foi possível carregar os pedidos com ${label}. Tente novamente.`
    this.errorTarget.hidden = false
  }
}
