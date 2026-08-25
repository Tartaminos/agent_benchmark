class OrdersController < ApplicationController
  ORDER_FIELDS = %i[order_id status purchase_at estimated_delivery_at delivered_customer_at].freeze
  SEARCH_STRATEGIES = %w[n_plus_one lazy_loading includes preload eager_load joins raw_sql].freeze
  DEFAULT_SEARCH_STRATEGY = "n_plus_one"
  ASSOCIATION_TREE = [
    :customer,
    :order_payments,
    :order_reviews,
    { order_items: %i[product seller] }
  ].freeze

  # PostgreSQL-specific on purpose: this study strategy builds the complete public
  # graph in one SELECT with JSONB aggregates instead of instantiating AR models.
  RAW_SQL_QUERY = <<~SQL.freeze
    SELECT
      jsonb_build_object(
        'order_id', selected_orders.order_id,
        'status', selected_orders.status,
        'purchase_at', to_char(selected_orders.purchase_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'estimated_delivery_at', to_char(selected_orders.estimated_delivery_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'delivered_customer_at', CASE
          WHEN selected_orders.delivered_customer_at IS NULL THEN NULL
          ELSE to_char(selected_orders.delivered_customer_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        END,
        'customer', CASE
          WHEN customers.id IS NULL THEN NULL
          ELSE jsonb_build_object(
            'customer_id', customers.customer_id,
            'customer_unique_id', customers.customer_unique_id,
            'city', customers.city,
            'state', customers.state
          )
        END,
        'items', items.data,
        'payments', payments.data,
        'reviews', reviews.data
      ) AS order_data
    FROM (
      SELECT
        id,
        customer_id,
        order_id,
        status,
        purchase_at,
        estimated_delivery_at,
        delivered_customer_at
      FROM orders
      ORDER BY purchase_at DESC, order_id ASC
      LIMIT 250
    ) AS selected_orders
    LEFT JOIN customers ON customers.id = selected_orders.customer_id
    LEFT JOIN LATERAL (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'order_item_id', order_items.order_item_id,
            'product_id', products.product_id,
            'seller_id', sellers.seller_id,
            'price', to_char(order_items.price, 'FM9999999990.00'),
            'freight_value', to_char(order_items.freight_value, 'FM9999999990.00')
          ) ORDER BY order_items.order_item_id ASC
        ),
        '[]'::jsonb
      ) AS data
      FROM order_items
      LEFT JOIN products ON products.id = order_items.product_id
      LEFT JOIN sellers ON sellers.id = order_items.seller_id
      WHERE order_items.order_id = selected_orders.id
    ) AS items ON TRUE
    LEFT JOIN LATERAL (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'payment_sequential', order_payments.payment_sequential,
            'payment_type', order_payments.payment_type,
            'payment_installments', order_payments.payment_installments,
            'payment_value', to_char(order_payments.payment_value, 'FM9999999990.00')
          ) ORDER BY order_payments.payment_sequential ASC
        ),
        '[]'::jsonb
      ) AS data
      FROM order_payments
      WHERE order_payments.order_id = selected_orders.id
    ) AS payments ON TRUE
    LEFT JOIN LATERAL (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'review_id', order_reviews.review_id,
            'score', order_reviews.score,
            'comment_title', order_reviews.comment_title,
            'comment_message', order_reviews.comment_message,
            'creation_at', to_char(order_reviews.creation_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'answer_at', to_char(order_reviews.answer_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          ) ORDER BY order_reviews.creation_at ASC, order_reviews.review_id ASC, order_reviews.id ASC
        ),
        '[]'::jsonb
      ) AS data
      FROM order_reviews
      WHERE order_reviews.order_id = selected_orders.id
    ) AS reviews ON TRUE
    ORDER BY selected_orders.purchase_at DESC, selected_orders.order_id ASC
  SQL
  private_constant :RAW_SQL_QUERY

  def index
    respond_to do |format|
      format.html
      format.json do
        requested_strategy = params[:strategy].presence || DEFAULT_SEARCH_STRATEGY

        unless SEARCH_STRATEGIES.include?(requested_strategy)
          render json: { error: "invalid_strategy" }, status: :unprocessable_content
          next
        end

        serialized_orders = measure_order_queries(
          requested_strategy: requested_strategy,
          effective_strategy: requested_strategy
        ) do
          case requested_strategy
          when "n_plus_one" then n_plus_one_query
          when "lazy_loading" then lazy_loading_query
          when "includes" then includes_query
          when "preload" then preload_query
          when "eager_load" then eager_load_query
          when "joins" then joins_query
          when "raw_sql" then raw_sql_query
          end
        end

        render json: {
          strategy: {
            requested: requested_strategy,
            effective: requested_strategy,
            implemented: true
          },
          orders: serialized_orders
        }
      end
    end
  end

  private

  def n_plus_one_query
    serialize_orders(base_order_scope)
  end

  def lazy_loading_query
    # O acesso às associações no serializer é lazy e reproduz o N+1 neste exemplo.
    serialize_orders(base_order_scope)
  end

  def includes_query
    serialize_orders(base_order_scope.includes(ASSOCIATION_TREE))
  end

  def preload_query
    serialize_orders(base_order_scope.preload(ASSOCIATION_TREE))
  end

  def eager_load_query
    serialize_orders(base_order_scope.eager_load(ASSOCIATION_TREE).reorder(purchase_at: :desc, order_id: :asc))
  end

  def joins_query
    serialize_orders(base_order_scope.joins(:customer))
  end

  def raw_sql_query
    ActiveRecord::Base.connection.select_all(RAW_SQL_QUERY).map do |row|
      order_data = row.fetch("order_data")
      order_data = JSON.parse(order_data) if order_data.is_a?(String)
      order_data.deep_stringify_keys
    end
  end

  def base_order_scope
    Order.order(purchase_at: :desc, order_id: :asc).limit(250)
  end

  def serialize_orders(orders)
    orders.map do |order|
      customer = order.customer
      items = order.order_items.sort_by(&:order_item_id).map do |item|
        product = item.product
        seller = item.seller

        {
          order_item_id: item.order_item_id,
          product_id: product&.product_id,
          seller_id: seller&.seller_id,
          price: format("%.2f", item.price),
          freight_value: format("%.2f", item.freight_value)
        }
      end
      payments = order.order_payments.sort_by(&:payment_sequential).map do |payment|
        {
          payment_sequential: payment.payment_sequential,
          payment_type: payment.payment_type,
          payment_installments: payment.payment_installments,
          payment_value: format("%.2f", payment.payment_value)
        }
      end
      reviews = order.order_reviews.sort_by { |review| [ review.creation_at, review.review_id, review.id ] }.map do |review|
        {
          review_id: review.review_id,
          score: review.score,
          comment_title: review.comment_title,
          comment_message: review.comment_message,
          creation_at: review.creation_at,
          answer_at: review.answer_at
        }
      end

      order.as_json(only: ORDER_FIELDS).merge(
        "customer" => customer&.as_json(only: %i[customer_id customer_unique_id city state]),
        "items" => items,
        "payments" => payments,
        "reviews" => reviews
      )
    end
  end

  def measure_order_queries(requested_strategy:, effective_strategy:)
    origin_thread = Thread.current
    origin_fiber = Fiber.current
    query_count = 0
    db_duration_ms = 0.0
    total_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    callback = lambda do |_name, started_at, finished_at, _event_id, payload|
      next unless Thread.current.equal?(origin_thread) && Fiber.current.equal?(origin_fiber)
      next if payload[:cached]
      next if payload[:name].to_s.match?(/SCHEMA|SchemaMigration/)
      next if payload[:name] == "TRANSACTION"

      normalized_sql = payload[:sql].to_s.gsub(/\s+/, " ").strip
      next unless normalized_sql.match?(/\ASELECT\b/i)

      duration_ms = (finished_at - started_at) * 1_000
      query_count += 1
      db_duration_ms += duration_ms
      Rails.logger.info(
        "[ORDERS_QUERY_STUDY] query=#{query_count} " \
          "requested_strategy=#{requested_strategy} effective_strategy=#{effective_strategy} " \
          "duration_ms=#{format('%.3f', duration_ms)} sql=#{normalized_sql.inspect}"
      )
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", monotonic: true) do
      yield
    end
  ensure
    if total_started_at
      total_duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - total_started_at) * 1_000
      Rails.logger.info(
        "[ORDERS_QUERY_STUDY] summary=true status=#{$! ? 'error' : 'ok'} " \
          "requested_strategy=#{requested_strategy} effective_strategy=#{effective_strategy} " \
          "query_count=#{query_count} db_duration_ms=#{format('%.3f', db_duration_ms)} " \
          "total_duration_ms=#{format('%.3f', total_duration_ms)}"
      )
    end
  end
end
