# Task 05 — Seller Performance Report

## Objective

Implement asynchronous CSV generation for an Olist seller performance report using the existing Rails application and imported dataset.

The seller must be identified by the external Olist `seller_id`. Report generation must run through `ActiveJob` rather than inside the HTTP request.

---

## Create Report

```text
POST /api/sellers/:seller_id/reports
```

Request body:

```json
{
  "start_date": "2018-01-01",
  "end_date": "2018-06-30"
}
```

For valid input return HTTP `202 Accepted` with at least:

```json
{
  "report_id": "...",
  "seller_id": "...",
  "status": "pending"
}
```

The request must enqueue background processing and return without generating the complete CSV synchronously.

---

## Report Status

```text
GET /api/reports/:report_id
```

Supported statuses:

```text
pending
processing
completed
failed
```

A completed report must expose a download URL. A report that is not completed must not expose a usable partial CSV.

---

## Download

```text
GET /api/reports/:report_id/download
```

For a completed report return HTTP `200` with `Content-Type: text/csv`.

---

## Validation

Both dates are required.

Reject with HTTP `422`:

- missing `start_date`;
- missing `end_date`;
- invalid dates;
- `start_date` later than `end_date`.

If the external seller does not exist, return HTTP `404` with:

```json
{
  "error": "seller_not_found"
}
```

Orders are selected by `purchase_at` within the requested date range, inclusive of both boundary dates.

---

## CSV Contract

Aggregate the seller's performance by calendar month.

Required columns:

```text
month
orders
items
gross_value
freight
average_order_value
late_orders
late_percentage
```

Example:

```csv
month,orders,items,gross_value,freight,average_order_value,late_orders,late_percentage
2018-01,42,51,7250.30,632.10,172.63,4,9.52
2018-02,38,44,6811.90,590.20,179.26,2,5.26
```

Rows must be ordered by month ascending.

Only months containing qualifying orders need to be included.

---

## Metric Definitions

### orders

Count distinct orders containing at least one item sold by the requested seller.

### items

Count order items belonging to the requested seller.

### gross_value

Sum the `price` of the requested seller's order items.

### freight

Sum the `freight_value` of the requested seller's order items.

### average_order_value

```text
gross_value / orders
```

This uses only the requested seller's item value, even if an order contains items from other sellers.

### late_orders

Count distinct qualifying orders where:

```text
delivered_customer_at IS NOT NULL
AND delivered_customer_at > estimated_delivery_at
```

Undelivered orders are not late.

### late_percentage

```text
(late_orders / orders) * 100
```

If `orders` is zero, return `0.00`.

---

## Formatting

These values must use exactly two decimal places:

- `gross_value`
- `freight`
- `average_order_value`
- `late_percentage`

Monetary calculations must avoid floating-point precision errors.

---

## Background Processing

The lifecycle must support:

```text
pending -> processing -> completed
```

and on processing failure:

```text
pending/processing -> failed
```

A report must only become `completed` after the CSV is fully available.

A failed report must remain identifiable as failed through the status endpoint. API responses must not expose internal exception details.

---

## Performance Constraints

The implementation must:

- filter seller and date range in the database;
- perform aggregation primarily in the database where appropriate;
- avoid N+1 queries;
- avoid one aggregate query per order;
- avoid loading the complete matching dataset into Ruby solely to calculate aggregates;
- avoid generating the report synchronously inside the POST request.

The solution may introduce persistence needed to represent report requests and their state, but must not modify the semantic meaning of imported Olist records.

---

## Constraints

- Use the existing Rails application and Olist database.
- Use `ActiveJob` for generation.
- Do not modify imported Olist records.
- Do not expose internal Rails IDs as public identifiers.
- Do not hardcode seller-specific values.
- Existing application behavior must continue working.
- Automated tests must cover the introduced behavior.

---

## Acceptance Criteria

The task is complete when:

1. A valid report request returns HTTP `202`.
2. Report creation enqueues an `ActiveJob`.
3. Seller lookup uses external `seller_id`.
4. Unknown sellers return the specified `404` response.
5. Invalid date input returns HTTP `422`.
6. Report status exposes `pending`, `processing`, `completed`, or `failed`.
7. Completed reports are downloadable as CSV.
8. Incomplete reports do not expose partial CSV output.
9. CSV columns and ordering follow the specified contract.
10. Monthly aggregation is correct.
11. Distinct order count is correct.
12. Seller item count, gross value, and freight are correct.
13. Average order value is correct.
14. Late-order classification follows the specified rule.
15. Late percentage is correct.
16. Required numeric values use exactly two decimal places.
17. Monetary calculations avoid floating-point precision errors.
18. Aggregation avoids N+1 behavior and per-order aggregate queries.
19. Background failures transition the report to `failed`.
20. Internal Rails IDs and internal exception details are not exposed.
21. Automated tests cover requests, jobs, calculations, CSV output, and failure behavior.
22. The application test suite passes.
