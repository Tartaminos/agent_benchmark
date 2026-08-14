# Task 03 — Delivery Status Classification

## Objective

Add a derived delivery classification to Olist orders using the delivery dates already stored in the application.

The classification must be exposed through a read-only HTTP endpoint that supports filtering and pagination.

---

## Endpoint

```text
GET /api/orders
```

The endpoint must support the optional query parameter:

```text
delivery_status
```

Supported values:

```text
pending
on_time
late
```

Examples:

```text
GET /api/orders?delivery_status=pending
GET /api/orders?delivery_status=on_time
GET /api/orders?delivery_status=late
```

---

## Delivery Classification Rules

For each order, derive `delivery_status` using the following rules.

### Pending

An order is `pending` when:

```text
delivered_customer_at is NULL
```

### On Time

An order is `on_time` when:

```text
delivered_customer_at <= estimated_delivery_at
```

### Late

An order is `late` when:

```text
delivered_customer_at > estimated_delivery_at
```

The classification must be derived from the existing data. Do not persist a duplicated delivery status column only to satisfy this task.

---

## Successful Response

Return HTTP `200` with a paginated JSON response.

Each order must contain at least:

```json
{
  "order_id": "e481f51cbdc54678b7cc49136f2d6af7",
  "status": "delivered",
  "purchase_at": "2017-10-02T10:56:33.000Z",
  "estimated_delivery_at": "2017-10-18T00:00:00.000Z",
  "delivered_customer_at": "2017-10-10T21:25:13.000Z",
  "delivery_status": "on_time"
}
```

The values above are examples only. The response must reflect the actual data stored in the database.

---

## Filtering

When `delivery_status` is provided, return only orders matching that classification.

Example:

```text
GET /api/orders?delivery_status=late
```

must return only orders where:

```text
delivered_customer_at > estimated_delivery_at
```

When no `delivery_status` is provided, return orders from all three classifications.

---

## Invalid Filter

If an unsupported `delivery_status` is provided, return HTTP `422` with:

```json
{
  "error": "invalid_delivery_status"
}
```

---

## Pagination

The endpoint must support:

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

The response must include pagination metadata containing at least:

- current page;
- per-page value;
- total number of matching records;
- total number of pages.

---

## Constraints

- Use the existing Rails application and imported Olist database.
- Do not modify the imported Olist records.
- Do not change the meaning of the existing database schema.
- Do not expose internal Rails IDs in the API response.
- Do not hardcode order-specific values.
- Do not persist duplicated classification data solely for this task.
- The filtering logic must be performed efficiently at the database/query layer rather than by loading all orders into Ruby memory.
- Existing application behavior must continue working.
- The implementation must include automated tests for the behavior introduced by this task.

---

## Acceptance Criteria

The task is considered complete when:

1. `GET /api/orders` returns HTTP `200`.
2. Every returned order includes a correct `delivery_status`.
3. Orders without `delivered_customer_at` are classified as `pending`.
4. Orders delivered on or before `estimated_delivery_at` are classified as `on_time`.
5. Orders delivered after `estimated_delivery_at` are classified as `late`.
6. `delivery_status=pending` returns only pending orders.
7. `delivery_status=on_time` returns only on-time orders.
8. `delivery_status=late` returns only late orders.
9. An unsupported `delivery_status` returns HTTP `422`.
10. The invalid-filter response contains `{"error":"invalid_delivery_status"}`.
11. Pagination works with `page` and `per_page`.
12. The default `per_page` is 25.
13. `per_page` cannot exceed 100.
14. Pagination metadata reflects the filtered result set.
15. Filtering is performed at the database/query layer.
16. Internal Rails IDs are not exposed.
17. Automated tests cover the introduced behavior and edge cases.
18. The application test suite passes.
