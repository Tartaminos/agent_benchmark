# Task 06 — Bulk Orders Export

## Objective

Implement bulk CSV export of Olist orders using the existing Rails application and imported dataset.

An administrative client must be able to request an export using order filters, receive a public export identifier immediately, check the export later, and download the CSV when generation has completed.

The initial HTTP request must not wait for the complete CSV to be generated.

This task defines required behavior and constraints, but does not prescribe how processing state, execution, coordination, or generated files are represented internally.

---

## Create Export

```text
POST /api/order_exports
```

Request body may contain any combination of:

```json
{
  "order_status": "delivered",
  "delivery_status": "late",
  "customer_state": "SP",
  "purchase_from": "2018-01-01",
  "purchase_to": "2018-06-30"
}
```

All filters are optional and combinable.

For valid input return HTTP `202 Accepted` with at least:

```json
{
  "export_id": "...",
  "status": "pending"
}
```

`export_id` is a public identifier and must not expose an internal Rails database ID.

The request must return before the complete CSV has been generated.

---

## Export Status

```text
GET /api/order_exports/:export_id
```

Supported statuses:

```text
pending
processing
completed
failed
```

The response must include at least:

```json
{
  "export_id": "...",
  "status": "..."
}
```

A completed export must expose a download URL.

An export that has not completed must not expose a usable partial CSV.

Unknown export identifiers must return HTTP `404`.

---

## Download

```text
GET /api/order_exports/:export_id/download
```

For a completed export return HTTP `200` with `Content-Type: text/csv`.

For an export that exists but is not completed, return a non-success response and do not return partial CSV contents.

Unknown export identifiers must return HTTP `404`.

---

## Filters

### Order Status

Filter by the existing Olist order status.

Invalid order statuses must return HTTP `422`.

### Delivery Status

Allow:

```text
pending
on_time
late
```

Use the same derived meaning already established by the application:

```text
pending
→ delivered_customer_at IS NULL

on_time
→ delivered_customer_at IS NOT NULL
  AND delivered_customer_at <= estimated_delivery_at

late
→ delivered_customer_at IS NOT NULL
  AND delivered_customer_at > estimated_delivery_at
```

Invalid delivery statuses must return HTTP `422`.

### Customer State

Filter by the state of the associated customer.

Invalid state values must return HTTP `422`.

### Purchase Date Range

`purchase_from` and `purchase_to` use ISO dates in `YYYY-MM-DD` format.

Either boundary may be supplied independently.

When both are present, `purchase_from` must not be later than `purchase_to`.

The date range is inclusive of both boundary dates and applies to `orders.purchase_at`.

Invalid dates or an inverted range must return HTTP `422`.

---

## CSV Contract

The CSV must contain one row per qualifying order.

Required columns, in this order:

```text
order_id
customer_id
customer_state
order_status
delivery_status
purchase_at
estimated_delivery_at
delivered_customer_at
items_total
freight_total
order_total
paid_total
```

Only external Olist identifiers may be exposed.

### Totals

For each order:

```text
items_total
= sum(order item price)

freight_total
= sum(order item freight_value)

order_total
= items_total + freight_total

paid_total
= sum(order payment payment_value)
```

All four numeric total columns must use exactly two decimal places.

Monetary calculations must avoid floating-point precision errors.

### Ordering

Rows must be deterministic and ordered by:

```text
purchase_at ASC
order_id ASC
```

### Empty Export

A valid filter combination with no matching orders must still complete successfully and produce a CSV containing the header row and no data rows.

---

## Processing Semantics

Generation continues independently after the create request has returned.

The lifecycle must support:

```text
pending -> processing -> completed
```

and on processing failure:

```text
pending/processing -> failed
```

The export must only become `completed` after the complete CSV is available for download.

A failed export must remain queryable through the status endpoint, and API responses must not expose internal exception details.

Processing may be retried or invoked more than once. Duplicate or concurrent attempts to process the same `export_id` must not:

- publish conflicting final states;
- make a partial CSV downloadable;
- append duplicate CSV rows to an already completed export;
- corrupt a completed result.

The externally observable result for a successfully completed export must remain deterministic.

---

## Performance Constraints

The implementation operates against the full imported Olist dataset.

It must:

- apply filters in the database;
- avoid N+1 queries for customer information, order items, or payments;
- avoid one aggregate query per exported order;
- avoid loading all matching Active Record objects into Ruby solely to calculate totals;
- perform aggregation primarily in the database where appropriate;
- avoid generating the complete export inside the initial POST request;
- remain practical for exports containing many thousands of orders.

The implementation may introduce state or storage required by the feature, but must not change the semantic meaning of imported Olist records.

---

## Constraints

- Use the existing Rails application and Olist database.
- Do not modify imported Olist records.
- Do not expose internal Rails IDs.
- Do not hardcode order-specific values.
- Do not introduce a frontend framework for this task.
- Existing application behavior must continue working.
- Automated tests must cover the behavior introduced by this task.

---

## Acceptance Criteria

The task is complete when:

1. A valid export request returns HTTP `202` before complete CSV generation finishes.
2. The create response exposes a public `export_id` and initial status.
3. Export status can be queried later through the public identifier.
4. Unknown export identifiers return HTTP `404`.
5. Order-status filtering works and invalid values return HTTP `422`.
6. Delivery-status filtering uses the specified derived classification.
7. Customer-state filtering works.
8. Purchase-date filtering supports either or both inclusive boundaries.
9. Invalid dates and inverted ranges return HTTP `422`.
10. All filters can be combined.
11. The CSV contains exactly the specified columns in the specified order.
12. Each qualifying order appears exactly once.
13. CSV rows use deterministic `purchase_at`, then `order_id`, ordering.
14. Item, freight, order, and paid totals are correct.
15. Monetary values use exactly two decimal places without floating-point precision errors.
16. A no-results export completes with a header-only CSV.
17. Incomplete exports do not expose usable partial output.
18. Processing failure produces a queryable `failed` state without exposing internal exception details.
19. Duplicate or concurrent processing of the same export cannot corrupt or duplicate the completed output.
20. Filtering and aggregation avoid N+1 behavior and per-order aggregate queries.
21. Large matching result sets are not loaded as complete Active Record object graphs solely to calculate aggregates.
22. Internal Rails IDs are not exposed.
23. Automated tests cover requests, filtering, processing lifecycle, CSV contents, failure behavior, retry/concurrency safety, and relevant performance behavior.
24. The application test suite passes.
