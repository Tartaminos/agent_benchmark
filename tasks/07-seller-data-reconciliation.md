# Task 07 — Seller Data Reconciliation

## Objective

Implement an asynchronous reconciliation workflow for orders associated with an Olist seller over a requested purchase-date range.

The purpose of the reconciliation is to identify orders whose total item-and-freight value does not agree with the total recorded payment value, while producing a queryable summary and paginated discrepancy details.

The seller must be identified by the external Olist `seller_id`.

The initial HTTP request must return before the reconciliation has examined the complete matching dataset.

This task defines observable behavior, consistency requirements, and performance constraints, but does not prescribe the internal processing, persistence, coordination, locking, or query architecture.

---

## Create Reconciliation

```text
POST /api/sellers/:seller_id/reconciliations
```

Request body:

```json
{
  "start_date": "2018-01-01",
  "end_date": "2018-06-30"
}
```

Both dates are required and use ISO `YYYY-MM-DD` format.

For valid input return HTTP `202 Accepted` with at least:

```json
{
  "reconciliation_id": "...",
  "seller_id": "...",
  "status": "pending"
}
```

`reconciliation_id` is a public identifier and must not expose an internal Rails database ID.

The request must return before the complete reconciliation has been calculated.

If the external seller does not exist, return HTTP `404` with:

```json
{
  "error": "seller_not_found"
}
```

Reject with HTTP `422`:

- missing `start_date`;
- missing `end_date`;
- invalid dates;
- `start_date` later than `end_date`.

Orders qualify when:

- the order contains at least one `order_item` belonging to the requested seller; and
- `orders.purchase_at` falls within the requested date range, inclusive of both boundary dates.

Each qualifying order is reconciled once, even if that seller has multiple items in the order.

---

## Reconciliation Status

```text
GET /api/reconciliations/:reconciliation_id
```

Supported statuses:

```text
pending
processing
completed
failed
```

The response must always include at least:

```json
{
  "reconciliation_id": "...",
  "seller_id": "...",
  "status": "...",
  "start_date": "...",
  "end_date": "..."
}
```

For a completed reconciliation, also return a summary containing:

```json
{
  "orders_checked": 120,
  "matched_orders": 113,
  "inconsistent_orders": 7,
  "missing_payment_orders": 2,
  "amount_mismatch_orders": 5,
  "expected_value": "18450.30",
  "paid_value": "18391.10",
  "difference": "-59.20",
  "discrepancies_url": "..."
}
```

An incomplete reconciliation must not expose a partially calculated summary as if it were final.

A failed reconciliation must remain queryable and must not expose internal exception details.

Unknown reconciliation identifiers must return HTTP `404`.

---

## Reconciliation Rules

For each qualifying order, calculate values across the complete order, not only the requested seller's own items.

This is intentional: the seller identifies which orders are included in the reconciliation, while the reconciliation checks whether each included order is internally financially consistent.

### expected_value

For one qualifying order:

```text
sum(all order item price)
+
sum(all order item freight_value)
```

### paid_value

For one qualifying order:

```text
sum(all order payment payment_value)
```

If the order has no payment rows, `paid_value` is `0.00` and the order is classified as `missing_payment`.

### difference

For one qualifying order:

```text
paid_value - expected_value
```

### matched order

An order is matched when it has at least one payment row and its `difference`, rounded to two decimal places using decimal-safe arithmetic, is exactly `0.00`.

### amount mismatch

An order with at least one payment row is an `amount_mismatch` when its two-decimal `difference` is not `0.00`.

### inconsistent order

An inconsistent order is either:

```text
missing_payment
```

or:

```text
amount_mismatch
```

Each qualifying order may contribute to only one discrepancy type.

---

## Summary Definitions

### orders_checked

Count distinct qualifying orders.

### matched_orders

Count qualifying orders classified as matched.

### inconsistent_orders

Count qualifying orders classified as either `missing_payment` or `amount_mismatch`.

The following invariant must hold:

```text
orders_checked = matched_orders + inconsistent_orders
```

### missing_payment_orders

Count qualifying orders with no payment rows.

### amount_mismatch_orders

Count qualifying orders with at least one payment row and a non-zero two-decimal difference.

The following invariant must hold:

```text
inconsistent_orders = missing_payment_orders + amount_mismatch_orders
```

### expected_value

Sum `expected_value` across all qualifying orders.

### paid_value

Sum `paid_value` across all qualifying orders.

### difference

```text
paid_value - expected_value
```

Summary monetary values must use exactly two decimal places and decimal-safe arithmetic.

A valid reconciliation with no qualifying orders must complete successfully with zero counts and:

```text
expected_value = 0.00
paid_value     = 0.00
difference     = 0.00
```

---

## Discrepancy Details

Completed reconciliations expose:

```text
GET /api/reconciliations/:reconciliation_id/discrepancies
```

The endpoint must be paginated.

Supported query parameters:

```text
page
per_page
```

Defaults:

```text
page = 1
per_page = 25
```

Maximum:

```text
per_page = 100
```

Invalid pagination values must return HTTP `422` rather than silently accepting malformed values.

The response must include pagination metadata and one entry per inconsistent order in that page.

Each discrepancy must include at least:

```json
{
  "order_id": "external-olist-order-id",
  "issue_type": "amount_mismatch",
  "expected_value": "120.50",
  "paid_value": "110.50",
  "difference": "-10.00"
}
```

`issue_type` must be one of:

```text
missing_payment
amount_mismatch
```

Discrepancies must be deterministically ordered by:

```text
order_id ASC
```

Internal Rails IDs must not be exposed.

For an existing reconciliation that is not completed, the discrepancy endpoint must not expose partial results as final data.

---

## Processing Semantics

The lifecycle must support:

```text
pending -> processing -> completed
```

and on processing failure:

```text
pending/processing -> failed
```

A reconciliation becomes `completed` only when its final summary and complete discrepancy result are mutually consistent and available for querying.

Processing may be retried or invoked more than once.

Duplicate or concurrent attempts to process the same `reconciliation_id` must not:

- create duplicated discrepancy entries;
- produce contradictory summaries;
- overwrite a valid completed result with a partial result;
- publish `completed` before all final data is available;
- produce conflicting terminal states.

A successful completed reconciliation must be stable when read repeatedly.

---

## Failure Behavior

If processing fails after work has begun:

- the reconciliation must become queryable as `failed`;
- incomplete calculations must not be presented as a completed summary;
- partial discrepancy data must not be exposed as final results;
- API responses must not expose internal exception details.

The implementation must remain safe if execution is attempted again after an infrastructure-level retry or duplicate delivery.

---

## Performance Constraints

The reconciliation operates against the full imported Olist dataset.

The implementation must:

- identify qualifying seller orders in the database;
- apply the purchase-date range in the database;
- calculate order item and payment aggregates primarily in the database where appropriate;
- avoid N+1 queries;
- avoid one aggregate query per qualifying order;
- avoid loading the complete matching order graph into Ruby solely to calculate reconciliation totals;
- support large sellers and broad date ranges without requiring all discrepancies to be returned in one response;
- paginate discrepancy results at the database level or through an equivalently bounded persistent/queryable result representation;
- avoid performing the complete reconciliation inside the initial POST request.

The solution may introduce state needed to represent reconciliation requests and their results, but must not modify imported Olist records or change their semantic meaning.

---

## Constraints

- Use the existing Rails application and Olist database.
- Use external Olist `seller_id` and `order_id` values at public boundaries.
- Do not modify imported Olist records.
- Do not expose internal Rails IDs.
- Do not hardcode seller-specific or order-specific values.
- Existing application behavior must continue working.
- Automated tests must cover the behavior introduced by this task.

---

## Acceptance Criteria

The task is complete when:

1. A valid reconciliation request returns HTTP `202` before complete processing finishes.
2. Seller lookup uses external `seller_id`.
3. Unknown sellers return the specified HTTP `404` response.
4. Missing, invalid, or inverted date ranges return HTTP `422`.
5. Qualifying orders are distinct orders containing at least one item from the requested seller within the inclusive purchase-date range.
6. Each qualifying order is reconciled using totals across the complete order.
7. `expected_value`, `paid_value`, and `difference` follow the specified definitions.
8. Missing-payment orders and amount mismatches are classified correctly and exclusively.
9. Summary count invariants hold.
10. Summary monetary invariants hold.
11. All public monetary values use exactly two decimal places without floating-point precision errors.
12. A no-orders reconciliation completes successfully with the specified zero summary.
13. Status exposes `pending`, `processing`, `completed`, or `failed` through the public reconciliation identifier.
14. Completed status is published only after the final summary and discrepancy result are both available and consistent.
15. Processing failures produce a queryable failed state without exposing internal exception details.
16. Duplicate or concurrent processing cannot duplicate discrepancies or corrupt a completed result.
17. Completed reconciliations expose paginated discrepancy details.
18. Invalid discrepancy pagination returns HTTP `422`.
19. Discrepancies are ordered by external `order_id` and expose no internal Rails IDs.
20. Incomplete reconciliations do not expose partial summary or discrepancy data as final output.
21. Database work avoids N+1 behavior and one aggregate query per qualifying order.
22. Large matching result sets are not loaded as complete Active Record object graphs solely to calculate reconciliation aggregates.
23. Automated tests cover request validation, reconciliation calculations, summary invariants, discrepancy pagination, processing lifecycle, failure behavior, retry/concurrency safety, and relevant performance behavior.
24. The application test suite passes.
