require "application_system_test_case"

class OrdersTest < ApplicationSystemTestCase
  self.fixture_table_names = []

  STRATEGY_HELP = {
    "N+1 intencional" => "Carrega as associações uma a uma de propósito. Compare as consultas e os tempos no terminal.",
    "Lazy loading" => "Carrega cada associação quando ela é acessada; neste exemplo, pode repetir o mesmo padrão do N+1. Compare os logs no terminal.",
    "Eager loading com includes" => "Deixa o Rails escolher como pré-carregar as associações. Compare as consultas e os tempos no terminal.",
    "Eager loading com preload" => "Pré-carrega as associações em consultas separadas e em lote. Compare as consultas e os tempos no terminal.",
    "Eager loading com eager_load" => "Pré-carrega as associações com LEFT OUTER JOIN. Compare as consultas e os tempos no terminal.",
    "JOIN de cliente via joins" => "Executa joins(:customer): aplica INNER JOIN apenas ao cliente e não pré-carrega nenhuma associação.",
    "SQL puro (PostgreSQL)" => "Executa uma única consulta SQL do PostgreSQL, com agregações JSONB e LATERAL, sem carregar associações pelo Active Record. Não é portátil para outros bancos."
  }.freeze

  setup do
    OrderItem.delete_all
    OrderPayment.delete_all
    OrderReview.delete_all
    Order.delete_all
    Customer.delete_all
    Product.delete_all
    Seller.delete_all
    @customer = Customer.create!(customer_id: "customer-one", customer_unique_id: "unique-one",
                                 zip_code_prefix: "01001", city: "Sao Paulo", state: "SP")
  end

  test "loads and reveals a complete related order graph with native keyboard interaction" do
    purchase_at = Time.utc(2026, 9, 1, 12, 30)
    unsafe_order_id = "<img src=x onerror=alert(1)>"
    order = create_order(order_id: unsafe_order_id, purchase_at: purchase_at)
    product = Product.create!(product_id: "product-one")
    seller = Seller.create!(seller_id: "seller-one", zip_code_prefix: "01001", city: "Campinas", state: "SP")
    OrderItem.create!(order: order, order_item_id: 1, product: product, seller: seller,
                      shipping_limit_at: purchase_at + 1.day, price: "19.90", freight_value: "3.40")
    OrderPayment.create!(order: order, payment_sequential: 1, payment_type: "credit_card",
                         payment_installments: 3, payment_value: "23.30")
    OrderReview.create!(order: order, review_id: "review-one", score: 5, comment_title: "Otimo",
                        comment_message: "<script>alert(1)</script>", creation_at: purchase_at + 2.days,
                        answer_at: purchase_at + 3.days)

    visit orders_path
    assert_text "Busque até 250 pedidos e compare as estratégias de consulta."
    assert_text "Selecione uma estratégia e clique em ‘Buscar pedidos’."
    assert_field "Tipo de busca", with: "n_plus_one"
    assert_no_text unsafe_order_id
    defer_next_fetch
    click_button "Buscar pedidos"
    assert_button "Buscando…", disabled: true
    assert_field "Tipo de busca", with: "n_plus_one", disabled: true
    assert_selector "[data-orders-target='results'][aria-busy='true']", visible: :all
    assert_text "Buscando até 250 pedidos com N+1 intencional…"
    assert_equal "n_plus_one", captured_strategy_parameter
    resolve_deferred_fetch

    assert_text "1 pedido encontrado com N+1 intencional."
    assert_selector ".order-card h2", text: "Pedido #{unsafe_order_id}"
    assert_no_selector ".orders-results img"
    assert_no_selector ".orders-results script"
    assert_selector ".order-card details:not([open])"
    summary = find(".order-card summary", text: "1 item, 1 pagamento, 1 avaliação")
    summary.send_keys(:enter)
    assert_selector ".order-card details[open]"

    assert_section("Cliente", [ "ID do cliente", "ID único do cliente", "Cidade", "Estado" ])
    assert_section("Itens", [ "Número do item", "ID do produto", "ID do vendedor", "Preço", "Frete" ])
    assert_section("Pagamentos", [ "Sequência", "Tipo", "Parcelas", "Valor" ])
    assert_section("Avaliações", [ "ID da avaliação", "Nota", "Título", "Comentário", "Criada em", "Respondida em" ])
    assert_text "R$ 19,90"
    assert_text "R$ 3,40"
    assert_text "R$ 23,30"
    assert_text(/01\/09\/2026, \d{2}:30/)
    assert_text "<script>alert(1)</script>"
    assert_button "Buscar pedidos", disabled: false
    assert_field "Tipo de busca", with: "n_plus_one", disabled: false
    assert_selector "[data-orders-target='results'][aria-busy='false']"

    page.current_window.resize_to(360, 800)
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
  end

  test "updates strategy guidance and sends and preserves an implemented strategy" do
    create_order(order_id: "joins-strategy")
    visit orders_path

    STRATEGY_HELP.each do |label, help|
      select label, from: "Tipo de busca"
      assert_text help
    end

    select "SQL puro (PostgreSQL)", from: "Tipo de busca"
    defer_next_fetch
    click_button "Buscar pedidos"

    assert_button "Buscando…", disabled: true
    assert_field "Tipo de busca", with: "raw_sql", disabled: true
    assert_text "Buscando até 250 pedidos com SQL puro (PostgreSQL)…"
    assert_equal "raw_sql", captured_strategy_parameter
    resolve_deferred_fetch

    assert_text "1 pedido encontrado com SQL puro (PostgreSQL)."
    assert_field "Tipo de busca", with: "raw_sql", disabled: false
    assert_selector ".order-card", count: 1

    Order.delete_all
    visit orders_path
    select "Eager loading com preload", from: "Tipo de busca"
    click_button "Buscar pedidos"

    assert_text "Nenhum pedido encontrado com Eager loading com preload."
    assert_field "Tipo de busca", with: "preload"
    assert_no_selector ".order-card"
  end

  test "isolates malformed associations and renders exact empty and fallback states" do
    visit orders_path
    stub_association_edge_cases
    click_button "Buscar pedidos"

    assert_text "2 pedidos encontrados com N+1 intencional."
    assert_selector ".order-card", count: 2
    all(".order-card summary").each { |summary| summary.click }
    within all(".order-card").first do
      assert_text "Cliente não informado."
      assert_text "Não informado", minimum: 12
    end
    within all(".order-card").last do
      assert_text "Nenhum item relacionado."
      assert_text "Nenhum pagamento relacionado."
      assert_text "Nenhuma avaliação relacionada."
    end
  end

  test "exposes empty, error, retry, and invalid date states" do
    visit orders_path
    click_button "Buscar pedidos"
    assert_text "Nenhum pedido encontrado com N+1 intencional."

    respond_next_fetch_with_invalid_dates
    click_button "Buscar pedidos"
    assert_text "invalid-date"
    assert_selector "dd", text: "Não informado", minimum: 3

    fail_next_fetch_with_invalid_payload
    click_button "Buscar pedidos"
    assert_selector "[role='alert']", text: "Não foi possível carregar os pedidos com N+1 intencional. Tente novamente."
    assert_no_selector ".order-card"

    fail_next_fetch_with_mismatched_strategy
    click_button "Buscar pedidos"
    assert_selector "[role='alert']", text: "Não foi possível carregar os pedidos com N+1 intencional. Tente novamente."
    assert_no_selector ".order-card"

    fail_next_fetch_with_wrong_effective_strategy
    click_button "Buscar pedidos"
    assert_selector "[role='alert']", text: "Não foi possível carregar os pedidos com N+1 intencional. Tente novamente."
    assert_no_selector ".order-card"

    fail_next_fetch_with_unimplemented_strategy
    click_button "Buscar pedidos"
    assert_selector "[role='alert']", text: "Não foi possível carregar os pedidos com N+1 intencional. Tente novamente."
    assert_no_selector ".order-card"

    fail_next_fetch_with_network_error
    click_button "Buscar pedidos"
    assert_selector "[role='alert']", text: "Não foi possível carregar os pedidos com N+1 intencional. Tente novamente."

    fail_next_fetch_with_http_error
    click_button "Buscar pedidos"
    assert_selector "[role='alert']", text: "Não foi possível carregar os pedidos com N+1 intencional. Tente novamente."
  end

  private

  def create_order(order_id:, purchase_at: Time.utc(2026, 9, 1, 12, 30))
    Order.create!(order_id: order_id, customer: @customer, status: "shipped", purchase_at: purchase_at,
                  estimated_delivery_at: purchase_at + 5.days, delivered_customer_at: nil)
  end

  def assert_section(title, labels)
    within find(".order-related-content section", text: title, match: :first) do
      assert_selector "h3", exact_text: title
      labels.each { |label| assert_selector "dt", exact_text: label }
    end
  end

  def defer_next_fetch
    page.execute_script <<~JAVASCRIPT
      window.__ordersRealFetch = window.fetch.bind(window);
      window.fetch = (...args) => new Promise((resolve, reject) => {
        window.__ordersFetchArgs = args;
        window.__ordersResolveFetch = () => window.__ordersRealFetch(...args).then(resolve, reject);
      });
    JAVASCRIPT
  end

  def captured_strategy_parameter
    page.evaluate_script(<<~JAVASCRIPT)
      new URL(window.__ordersFetchArgs[0], window.location.origin).searchParams.get("strategy")
    JAVASCRIPT
  end

  def resolve_deferred_fetch
    page.execute_script("window.__ordersResolveFetch()")
  end

  def stub_association_edge_cases
    page.execute_script <<~JAVASCRIPT
      window.fetch = () => Promise.resolve(new Response(JSON.stringify({
        strategy: {requested: "n_plus_one", effective: "n_plus_one", implemented: true},
        orders: [
          {order_id: "malformed", customer: "bad", items: [null], payments: [{}], reviews: [false]},
          {order_id: "empty", customer: null, items: [], payments: [], reviews: []}
        ]
      }), {status: 200, headers: {"Content-Type": "application/json"}}));
    JAVASCRIPT
  end

  def fail_next_fetch_with_invalid_payload
    page.execute_script <<~JAVASCRIPT
      window.fetch = () => Promise.resolve(new Response(JSON.stringify({unexpected: []}), {
        status: 200, headers: {"Content-Type": "application/json"}
      }));
    JAVASCRIPT
  end

  def respond_next_fetch_with_invalid_dates
    page.execute_script <<~JAVASCRIPT
      window.fetch = () => Promise.resolve(new Response(JSON.stringify({
        strategy: {requested: "n_plus_one", effective: "n_plus_one", implemented: true},
        orders: [{
          order_id: "invalid-date", status: "created", purchase_at: "not-a-date",
          estimated_delivery_at: null, delivered_customer_at: "", items: [], payments: [], reviews: []
        }]
      }), {status: 200, headers: {"Content-Type": "application/json"}}));
    JAVASCRIPT
  end

  def fail_next_fetch_with_mismatched_strategy
    page.execute_script <<~JAVASCRIPT
      window.fetch = () => Promise.resolve(new Response(JSON.stringify({
        strategy: {requested: "includes", effective: "includes", implemented: true},
        orders: [{order_id: "must-not-render"}]
      }), {status: 200, headers: {"Content-Type": "application/json"}}));
    JAVASCRIPT
  end

  def fail_next_fetch_with_wrong_effective_strategy
    page.execute_script <<~JAVASCRIPT
      window.fetch = () => Promise.resolve(new Response(JSON.stringify({
        strategy: {requested: "n_plus_one", effective: "includes", implemented: true},
        orders: [{order_id: "must-not-render"}]
      }), {status: 200, headers: {"Content-Type": "application/json"}}));
    JAVASCRIPT
  end

  def fail_next_fetch_with_unimplemented_strategy
    page.execute_script <<~JAVASCRIPT
      window.fetch = () => Promise.resolve(new Response(JSON.stringify({
        strategy: {requested: "n_plus_one", effective: "n_plus_one", implemented: false},
        orders: [{order_id: "must-not-render"}]
      }), {status: 200, headers: {"Content-Type": "application/json"}}));
    JAVASCRIPT
  end

  def fail_next_fetch_with_network_error
    page.execute_script("window.fetch = () => Promise.reject(new TypeError('Network error'))")
  end

  def fail_next_fetch_with_http_error
    page.execute_script("window.fetch = () => Promise.resolve(new Response('', {status: 503}))")
  end
end
