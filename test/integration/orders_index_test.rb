require "test_helper"
require "stringio"

class OrdersIndexTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  SEARCH_STRATEGIES = %w[n_plus_one lazy_loading includes preload eager_load joins raw_sql].freeze
  STRATEGY_LABELS = [
    [ "n_plus_one", "N+1 intencional" ],
    [ "lazy_loading", "Lazy loading" ],
    [ "includes", "Eager loading com includes" ],
    [ "preload", "Eager loading com preload" ],
    [ "eager_load", "Eager loading com eager_load" ],
    [ "joins", "JOIN de cliente via joins" ],
    [ "raw_sql", "SQL puro (PostgreSQL)" ]
  ].freeze

  QUERY_PROFILES = {
    "n_plus_one" => [ 7, 13 ],
    "lazy_loading" => [ 7, 13 ],
    "includes" => [ 7, 7 ],
    "preload" => [ 7, 7 ],
    "eager_load" => [ 2, 2 ],
    "joins" => [ 7, 13 ],
    "raw_sql" => [ 1, 1 ]
  }.freeze

  setup do
    OrderItem.delete_all
    OrderPayment.delete_all
    OrderReview.delete_all
    Order.delete_all
    Customer.delete_all
    Product.delete_all
    Seller.delete_all
    @customer = Customer.create!(customer_id: "customer-one", customer_unique_id: "customer-unique-one",
                                 zip_code_prefix: "01001", city: "Sao Paulo", state: "SP")
  end

  test "renders the study page without loading orders automatically" do
    create_order(order_id: "not-rendered-before-click")
    get orders_path

    assert_response :success
    assert_select "main[data-controller='orders'][data-orders-url-value='/orders.json']"
    assert_select "h1", text: "Pedidos"
    assert_select "label[for='orders-strategy']", text: "Tipo de busca"
    assert_select "select#orders-strategy[data-orders-target='strategy'][aria-describedby='orders-strategy-help']"
    assert_equal STRATEGY_LABELS, css_select("#orders-strategy option").map { |option| [ option["value"], option.text ] }
    assert_select "#orders-strategy option:first-child[value='n_plus_one']"
    assert_select ".orders-header p", text: "Busque até 250 pedidos e compare as estratégias de consulta."
    assert_select "#orders-strategy-help", text: "Carrega as associações uma a uma de propósito. Compare as consultas e os tempos no terminal."
    assert_select "button[type='button'][data-action='orders#load']", text: "Buscar pedidos"
    assert_select "[role='status'][aria-live='polite']", text: "Selecione uma estratégia e clique em ‘Buscar pedidos’."
    assert_select "[role='alert'][hidden]"
    assert_select "[data-orders-target='results'][aria-busy='false']:empty"
    assert_select ".orders-list", count: 0
    assert_no_match(/not-rendered-before-click/, response.body)
  end

  test "all strategies return the same deterministic public graph without writes" do
    base_time = Time.utc(2026, 9, 1, 12, 30)
    create_order(order_id: "order-b", status: "delivered", purchase_at: base_time - 1.day,
                 delivered_customer_at: base_time)
    first_order = create_order(order_id: "order-a", status: "shipped", purchase_at: base_time)
    add_item(first_order, order_item_id: 2, product_id: "product-two", seller_id: "seller-two",
                          price: "1.20", freight: "0.05")
    add_item(first_order, order_item_id: 1, product_id: "product-one", seller_id: "seller-one",
                          price: "19.90", freight: "3.40")
    add_payment(first_order, sequential: 2, payment_type: "voucher", installments: 1, value: "4.00")
    add_payment(first_order, sequential: 1, payment_type: "credit_card", installments: 3, value: "20.55")
    add_review(first_order, review_id: "review-z", score: 3, creation_at: base_time + 2.days)
    add_review(first_order, review_id: "review-b", score: 5, creation_at: base_time + 1.day)
    add_review(first_order, review_id: "review-a", score: 4, creation_at: base_time + 1.day)
    first_order.order_reviews.find_by!(review_id: "review-b").update!(comment_title: nil, comment_message: nil)

    before_state = persisted_order_graph_state
    graphs = SEARCH_STRATEGIES.to_h do |strategy|
      get orders_path(format: :json), params: { strategy: strategy }

      assert_response :success
      assert_equal "application/json", response.media_type
      payload = response.parsed_body
      assert_equal %w[orders strategy], payload.keys.sort
      assert_equal({ "requested" => strategy, "effective" => strategy, "implemented" => true },
                   payload.fetch("strategy"))
      assert_equal [ "order-a", "order-b" ], payload.fetch("orders").pluck("order_id")
      [ strategy, payload.fetch("orders") ]
    end

    assert_equal before_state, persisted_order_graph_state
    reference_graph = graphs.fetch("n_plus_one")
    graphs.each do |strategy, graph|
      assert_equal reference_graph, graph, "#{strategy} must serialize the exact same public graph"
    end

    order = reference_graph.first
    assert_equal %w[customer delivered_customer_at estimated_delivery_at items order_id payments purchase_at reviews status],
                 order.keys.sort
    assert_equal({ "customer_id" => "customer-one", "customer_unique_id" => "customer-unique-one",
                   "city" => "Sao Paulo", "state" => "SP" }, order.fetch("customer"))
    assert_equal [ 1, 2 ], order.fetch("items").pluck("order_item_id")
    assert_equal %w[freight_value order_item_id price product_id seller_id], order.fetch("items").first.keys.sort
    assert_equal "19.90", order.fetch("items").first.fetch("price")
    assert_equal "3.40", order.fetch("items").first.fetch("freight_value")
    assert_equal [ 1, 2 ], order.fetch("payments").pluck("payment_sequential")
    assert_equal %w[payment_installments payment_sequential payment_type payment_value],
                 order.fetch("payments").first.keys.sort
    assert_equal "20.55", order.fetch("payments").first.fetch("payment_value")
    assert_equal [ "review-a", "review-b", "review-z" ], order.fetch("reviews").pluck("review_id")
    assert_equal %w[answer_at comment_message comment_title creation_at review_id score],
                 order.fetch("reviews").first.keys.sort
    assert_equal "shipped", order.fetch("status")
    assert_nil order.fetch("reviews").second.fetch("comment_title")
    assert_nil order.fetch("reviews").second.fetch("comment_message")
    assert_equal "2026-09-01T12:30:00.000Z", order.fetch("purchase_at")
    assert_equal "2026-09-06T12:30:00.000Z", order.fetch("estimated_delivery_at")
    assert_nil order.fetch("delivered_customer_at")
    reference_graph.drop(1).each do |plain_order|
      assert_equal [], plain_order.fetch("items")
      assert_equal [], plain_order.fetch("payments")
      assert_equal [], plain_order.fetch("reviews")
    end
  end

  test "limits results to the first 250 deterministically ordered roots" do
    base_time = Time.utc(2026, 9, 1, 12, 30)
    251.times do |index|
      create_order(order_id: format("order-%03d", index), purchase_at: base_time - index.seconds)
    end

    get orders_path(format: :json), params: { strategy: "raw_sql" }

    assert_response :success
    orders = response.parsed_body.fetch("orders")
    assert_equal 250, orders.size
    assert_equal "order-000", orders.first.fetch("order_id")
    assert_equal "order-249", orders.last.fetch("order_id")
    assert_not_includes orders.pluck("order_id"), "order-250"
  end

  test "defaults missing and blank strategies to the implemented N plus one strategy" do
    [ nil, "", " \t " ].each do |strategy|
      get orders_path(format: :json), params: strategy.nil? ? {} : { strategy: strategy }

      assert_response :success
      assert_equal({ "requested" => "n_plus_one", "effective" => "n_plus_one", "implemented" => true },
                   response.parsed_body.fetch("strategy"))
    end
  end

  test "accepts only the exact allowlisted implemented strategies" do
    SEARCH_STRATEGIES.each do |strategy|
      get orders_path(format: :json), params: { strategy: strategy }

      assert_response :success
      assert_equal({
        "requested" => strategy,
        "effective" => strategy,
        "implemented" => true
      }, response.parsed_body.fetch("strategy"))
      assert_equal [], response.parsed_body.fetch("orders")
    end
  end

  test "rejects unknown strategies before selecting orders" do
    [ "N_PLUS_ONE", "includes ", "public_send" ].each do |strategy|
      selects = selects_during { get orders_path(format: :json), params: { strategy: strategy } }

      assert_response :unprocessable_content
      assert_equal({ "error" => "invalid_strategy" }, response.parsed_body)
      assert_empty selects.grep(/\bFROM\s+[\"`]orders[\"`]/i), "invalid strategies must not query orders"
    end
  end

  test "each strategy has its expected query profile as the graph grows" do
    first = create_order(order_id: "query-order-one")
    add_item(first, order_item_id: 1, product_id: "query-product-one", seller_id: "query-seller-one")

    one_root_counts = SEARCH_STRATEGIES.to_h do |strategy|
      one_order_selects = selects_during do
        get orders_path(format: :json), params: { strategy: strategy }
      end
      assert_response :success
      [ strategy, one_order_selects.size ]
    end

    second_customer = Customer.create!(customer_id: "customer-two", customer_unique_id: "customer-unique-two",
                                       zip_code_prefix: "01002", city: "Campinas", state: "SP")
    second = create_order(order_id: "query-order-two", purchase_at: first.purchase_at - 1.day,
                          customer: second_customer)
    add_item(second, order_item_id: 1, product_id: "query-product-two", seller_id: "query-seller-two")
    two_root_counts = SEARCH_STRATEGIES.to_h do |strategy|
      two_order_selects = selects_during do
        get orders_path(format: :json), params: { strategy: strategy }
      end
      assert_response :success
      [ strategy, two_order_selects.size ]
    end

    QUERY_PROFILES.each do |strategy, expected_counts|
      assert_equal expected_counts, [ one_root_counts.fetch(strategy), two_root_counts.fetch(strategy) ],
                   "unexpected SELECT profile for #{strategy}"
    end
  end

  test "joins uses an inner join only for the customer and leaves associations lazy" do
    order = create_order(order_id: "joined-order")
    add_item(order, order_item_id: 1, product_id: "joined-product", seller_id: "joined-seller")

    selects = selects_during do
      get orders_path(format: :json), params: { strategy: "joins" }
    end

    assert_response :success
    assert_equal 7, selects.size
    root_sql = selects.find { |sql| sql.match?(/\bFROM\s+"orders"/i) }
    assert root_sql, "joins must issue a root Order SELECT"
    assert_match(/\bINNER JOIN\s+"customers"/i, root_sql)
    assert_no_match(/\bLEFT OUTER JOIN\b/i, root_sql)
    assert_no_match(/\bJOIN\s+"(?:order_items|order_payments|order_reviews|products|sellers)"/i, root_sql)
  end

  test "raw SQL builds the complete graph in one static PostgreSQL select without AR instantiation" do
    order = create_order(order_id: "raw-sql-must-not-be-interpolated")
    add_item(order, order_item_id: 1, product_id: "raw-product", seller_id: "raw-seller")
    add_payment(order, sequential: 1, payment_type: "voucher", installments: 1, value: "12.30")
    add_review(order, review_id: "raw-review", score: 5, creation_at: order.purchase_at + 1.day)

    instantiated = []
    instantiation_subscriber = lambda do |_name, _started, _finished, _id, payload|
      instantiated << payload[:class_name]
    end
    selects = ActiveSupport::Notifications.subscribed(
      instantiation_subscriber,
      "instantiation.active_record"
    ) do
      selects_during do
        get orders_path(format: :json), params: { strategy: "raw_sql" }
      end
    end

    assert_response :success
    assert_equal 1, selects.size
    sql = selects.sole
    assert_match(/\ASELECT\b/i, sql)
    assert_match(/\bjsonb_build_object\b/i, sql)
    assert_match(/\bLEFT JOIN LATERAL\b/i, sql)
    assert_match(/\bLIMIT 250\b/i, sql)
    assert_no_match(/raw-sql-must-not-be-interpolated|raw-product|raw-seller|raw-review/, sql)
    assert_empty instantiated, "raw_sql must not instantiate Active Record models"
    assert_equal "raw_sql", response.parsed_body.dig("strategy", "requested")
    assert_equal "raw_sql", response.parsed_body.dig("strategy", "effective")
    assert_equal true, response.parsed_body.dig("strategy", "implemented")
  end

  test "raw SQL emits one studied query and one matching summary without schema noise" do
    create_order(order_id: "raw-log-order")

    logs = study_logs_during do
      get orders_path(format: :json), params: { strategy: "raw_sql" }
    end

    assert_response :success
    query_logs = logs.grep(/\[ORDERS_QUERY_STUDY\] query=/)
    assert_equal 1, query_logs.size
    assert_match(
      /\A\[ORDERS_QUERY_STUDY\] query=1 requested_strategy=raw_sql effective_strategy=raw_sql duration_ms=\d+\.\d{3} sql="SELECT\b.*"\z/,
      query_logs.sole
    )
    assert_no_match(/\bSCHEMA\b|schema_migrations/i, query_logs.sole)
    assert_match(
      /\A\[ORDERS_QUERY_STUDY\] summary=true status=ok requested_strategy=raw_sql effective_strategy=raw_sql query_count=1 db_duration_ms=\d+\.\d{3} total_duration_ms=\d+\.\d{3}\z/,
      logs.grep(/\[ORDERS_QUERY_STUDY\] summary=true/).sole
    )
  end

  test "logs each studied select and a timing summary for the effective strategy" do
    order = create_order(order_id: "private-order-value")
    add_item(order, order_item_id: 1, product_id: "private-product-value", seller_id: "private-seller-value")

    logs = study_logs_during do
      get orders_path(format: :json), params: { strategy: "includes" }
    end

    assert_response :success
    query_logs = logs.grep(/\[ORDERS_QUERY_STUDY\] query=/)
    summary_logs = logs.grep(/\[ORDERS_QUERY_STUDY\] summary=true/)
    assert_equal 7, query_logs.size
    assert_equal 1, summary_logs.size

    query_logs.each_with_index do |line, index|
      assert_match(/\A\[ORDERS_QUERY_STUDY\] query=#{index + 1} /, line)
      assert_match(/ requested_strategy=includes effective_strategy=includes /, line)
      assert_match(/ duration_ms=\d+\.\d{3} sql="SELECT\b.*"\z/, line)
      assert_no_match(/\\[nrt]/, line, "logged SQL must have normalized whitespace")
      assert_no_match(/private-(?:order|product|seller)-value|binds=|params=|result=|exception=/, line)
    end

    summary = summary_logs.sole
    assert_match(
      /\A\[ORDERS_QUERY_STUDY\] summary=true status=ok requested_strategy=includes effective_strategy=includes query_count=7 db_duration_ms=\d+\.\d{3} total_duration_ms=\d+\.\d{3}\z/,
      summary
    )
    assert_operator summary[/db_duration_ms=(\d+\.\d{3})/, 1].to_f, :>=, 0.0
    assert_operator summary[/total_duration_ms=(\d+\.\d{3})/, 1].to_f, :>=, 0.0
  end

  test "does not emit study logs for an invalid strategy" do
    create_order(order_id: "invalid-strategy-order")

    logs = study_logs_during do
      get orders_path(format: :json), params: { strategy: "not_allowed" }
    end

    assert_response :unprocessable_content
    assert_empty logs
  end

  test "logs only uncached selects from the study thread and fiber" do
    controller = OrdersController.new

    logs = study_logs_during do
      controller.send(
        :measure_order_queries,
        requested_strategy: "lazy_loading",
        effective_strategy: "lazy_loading"
      ) do
        emit_sql("SELECT  *\n FROM orders WHERE secret = ?", binds: [ "private-bind-value" ])
        emit_sql("SELECT cached", cached: true)
        emit_sql("SELECT schema", name: "SCHEMA")
        emit_sql("SELECT transaction", name: "TRANSACTION")
        emit_sql("UPDATE orders SET status = 'ignored'")
        Thread.new { emit_sql("SELECT another_thread") }.join
        Fiber.new { emit_sql("SELECT another_fiber") }.resume
      end
    end

    query_logs = logs.grep(/query=/)
    assert_equal 1, query_logs.size
    assert_match(/query=1 requested_strategy=lazy_loading effective_strategy=lazy_loading/, query_logs.sole)
    assert_match(/sql="SELECT \* FROM orders WHERE secret = \?"\z/, query_logs.sole)
    assert_no_match(/private-bind-value|cached|schema|transaction|UPDATE|another_/, query_logs.sole)
    assert_match(/summary=true status=ok .* query_count=1 /, logs.grep(/summary=true/).sole)
  end

  test "removes query instrumentation after successful and exceptional study blocks" do
    successful_logs = study_logs_during do
      get orders_path(format: :json)
      emit_study_candidate_select
    end
    assert_equal 1, successful_logs.grep(/summary=true status=ok/).size
    assert_empty successful_logs.grep(/SELECT leaked_success/)

    controller = OrdersController.new
    study_error = Class.new(StandardError).new("sensitive exception details")
    exceptional_logs = study_logs_during do
      raised = assert_raises(study_error.class) do
        controller.send(
          :measure_order_queries,
          requested_strategy: "includes",
          effective_strategy: "includes"
        ) { raise study_error }
      end
      assert_same study_error, raised
      emit_study_candidate_select("leaked_exception")
    end

    assert_equal 1, exceptional_logs.size
    assert_match(
      /\A\[ORDERS_QUERY_STUDY\] summary=true status=error requested_strategy=includes effective_strategy=includes query_count=0 db_duration_ms=0\.000 total_duration_ms=\d+\.\d{3}\z/,
      exceptional_logs.sole
    )
    assert_no_match(/sensitive exception details|leaked_exception/, exceptional_logs.sole)
  end

  private

  def persisted_order_graph_state
    [
      Order.order(:id).pluck(:id, :updated_at),
      Customer.order(:id).pluck(:id, :updated_at),
      OrderItem.order(:id).pluck(:id, :updated_at),
      OrderPayment.order(:id).pluck(:id, :updated_at),
      OrderReview.order(:id).pluck(:id, :updated_at),
      Product.order(:id).pluck(:id, :updated_at),
      Seller.order(:id).pluck(:id, :updated_at)
    ]
  end

  def create_order(order_id:, status: "created", purchase_at: Time.utc(2026, 9, 1, 12, 30),
                   delivered_customer_at: nil, customer: @customer)
    Order.create!(order_id: order_id, customer: customer, status: status, purchase_at: purchase_at,
                  estimated_delivery_at: purchase_at + 5.days, delivered_customer_at: delivered_customer_at)
  end

  def add_item(order, order_item_id:, product_id:, seller_id:, price: "10.00", freight: "2.00")
    product = Product.create!(product_id: product_id)
    seller = Seller.create!(seller_id: seller_id, zip_code_prefix: "01001", city: "Sao Paulo", state: "SP")
    OrderItem.create!(order: order, order_item_id: order_item_id, product: product, seller: seller,
                      shipping_limit_at: order.purchase_at + 1.day, price: price, freight_value: freight)
  end

  def add_payment(order, sequential:, payment_type:, installments:, value:)
    OrderPayment.create!(order: order, payment_sequential: sequential, payment_type: payment_type,
                         payment_installments: installments, payment_value: value)
  end

  def add_review(order, review_id:, score:, creation_at:)
    OrderReview.create!(order: order, review_id: review_id, score: score, comment_title: "Titulo #{review_id}",
                        comment_message: "Comentario #{review_id}", creation_at: creation_at,
                        answer_at: creation_at + 1.hour)
  end

  def selects_during
    sql = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])

      sql << payload[:sql] if payload[:sql].match?(/\ASELECT\b/i)
    end
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    end
    sql
  end

  def study_logs_during
    logs = []
    capture = ActiveSupport::Logger.new(StringIO.new)
    capture.formatter = proc do |_severity, _time, _program_name, message|
      logs << message.to_s
      ""
    end
    Rails.logger.broadcast_to(capture)
    yield
    logs.grep(/\A\[ORDERS_QUERY_STUDY\]/)
  ensure
    Rails.logger.stop_broadcasting_to(capture) if capture
  end

  def emit_study_candidate_select(label = "leaked_success")
    emit_sql("SELECT #{label}", binds: [ "sensitive bind" ])
  end

  def emit_sql(sql, name: "Order Load", cached: false, binds: [])
    ActiveSupport::Notifications.instrument(
      "sql.active_record",
      sql: sql,
      name: name,
      cached: cached,
      binds: binds
    )
  end
end
