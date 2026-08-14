# Task 02 — Seller Orders Performance

## Objective

Implement a read-only HTTP endpoint that lists orders associated with an Olist seller while keeping database access efficient as the number of returned orders grows.

This task is intended to evaluate ActiveRecord query design, pagination, aggregation, and N+1 prevention.

The endpoint must use the external Olist `seller_id` as its public identifier.

---

## Endpoint

```text
GET /api/sellers/:seller_id/orders
```

Supported query parameters:

```text
page
per_page
```

Example:

```text
GET /api/sellers/3442f8959a84dea7ee197c632cb2df15/orders?page=1&per_page=20
```

---

## Pagination

Defaults:

```text
page = 1
per_page = 20
```

Rules:

- `page` must be a positive integer.
- `per_page` must be a positive integer.
- `per_page` must not exceed `100`.
- Invalid pagination parameters must return HTTP `422`.
- Orders must be sorted by `purchase_at` descending.
- Orders with the same `purchase_at` must be sorted by external `order_id` ascending to keep pagination deterministic.

---

## Successful Response

For an existing seller, return HTTP `200` with JSON in the following structure:

```json
{
  "seller_id": "3442f8959a84dea7ee197c632cb2df15",
  "page": 1,
  "per_page": 20,
  "total_orders": 35,
  "orders": [
    {
      "order_id": "4a90af3e85dd563884e2afeab1091394",
      "status": "delivered",
      "purchase_at": "2017-08-21T20:35:44.000Z",
      "item_count": 2,
      "items_value": "149.80",
      "freight_value": "31.40",
      "total_value": "181.20",
      "products": [
        {
          "product_id": "f422d0d9f8b5e7d4d8e84de3f7c5f7c1",
          "category_name": "moveis_decoracao"
        }
      ]
    }
  ]
}
```

The values above are examples only. The response must reflect the actual data stored in the database.

---

## Business Rules

### Seller identification

The seller must be located using the external Olist `seller_id`.

Internal Rails IDs must not be exposed in the response.

### Orders

Return each distinct order that contains at least one item sold by the requested seller.

An order must appear only once even when the seller has multiple items in that order.

Only items belonging to the requested seller may contribute to the seller-specific aggregates returned by this endpoint.

For each order return:

- `order_id`
- `status`
- `purchase_at`
- `item_count`
- `items_value`
- `freight_value`
- `total_value`
- `products`

### Aggregates

For each order:

```text
item_count    = number of order items belonging to the requested seller
items_value   = sum of price for those items
freight_value = sum of freight_value for those items
total_value   = items_value + freight_value
```

All monetary values must be represented with exactly two decimal places.

### Products

`products` must contain the distinct products sold by the requested seller in that order.

Each product must include:

- `product_id`
- `category_name`

Products must not be duplicated within the same order response.

---

## Missing Seller

If the provided `seller_id` does not exist, return HTTP `404` with:

```json
{
  "error": "seller_not_found"
}
```

---

## Invalid Pagination

Invalid pagination parameters must return HTTP `422` with:

```json
{
  "error": "invalid_pagination"
}
```

Examples of invalid values include:

```text
page=0
page=-1
page=abc
per_page=0
per_page=-10
per_page=101
per_page=abc
```

---

## Performance Requirements

The implementation must not introduce N+1 queries.

Database query count must remain effectively constant as `per_page` increases.

When measured using Rails SQL instrumentation while ignoring schema and cached queries:

```text
GET /api/sellers/:seller_id/orders?page=1&per_page=5
```

and:

```text
GET /api/sellers/:seller_id/orders?page=1&per_page=50
```

must differ by no more than **1 SQL SELECT statement** for a seller with at least 50 orders.

The implementation must not execute one additional query per order, per item, or per product.

Performance must be achieved through appropriate query design and ActiveRecord/database capabilities rather than application-level caching of benchmark results.

---

## Constraints

- Use the existing Rails application and imported Olist database.
- Do not modify imported Olist records.
- Do not change the meaning of the existing database schema.
- Database indexes may be added when justified by the implementation.
- Do not hardcode seller IDs or benchmark-specific response values.
- Do not cache complete endpoint responses or precompute benchmark-specific answers.
- Do not expose internal Rails IDs.
- Existing application behavior must continue working.
- The implementation must include automated tests for the behavior introduced by this task.

---

## Acceptance Criteria

The task is considered complete when:

1. `GET /api/sellers/:seller_id/orders` returns HTTP `200` for an existing seller.
2. The seller is located using its external Olist `seller_id`.
3. Each distinct seller order appears at most once in the response.
4. Only items belonging to the requested seller contribute to aggregates.
5. `item_count` is correct for every returned order.
6. `items_value` is correct for every returned order.
7. `freight_value` is correct for every returned order.
8. `total_value` equals `items_value + freight_value`.
9. Monetary values contain exactly two decimal places.
10. Distinct products for the seller are returned without duplication.
11. Pagination defaults to `page=1` and `per_page=20`.
12. `per_page` cannot exceed `100`.
13. Pagination ordering is deterministic.
14. Invalid pagination returns HTTP `422` with `{"error":"invalid_pagination"}`.
15. An unknown seller returns HTTP `404` with `{"error":"seller_not_found"}`.
16. Internal Rails IDs are not exposed.
17. SQL SELECT count for `per_page=5` and `per_page=50` differs by no more than one query for the same qualifying seller.
18. The implementation does not perform per-order, per-item, or per-product queries.
19. Automated tests cover the introduced behavior.
20. The application test suite passes.
