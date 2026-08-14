# Task 01 — Order Details API

## Objective

Implement a read-only HTTP endpoint that exposes detailed information about an Olist order using the data already available in the application.

The endpoint must use the external Olist `order_id` as its public identifier.

---

## Endpoint

```text
GET /api/orders/:order_id
```

Example:

```text
GET /api/orders/e481f51cbdc54678b7cc49136f2d6af7
```

---

## Successful Response

For an existing order, return HTTP `200` with JSON in the following structure:

```json
{
  "order_id": "e481f51cbdc54678b7cc49136f2d6af7",
  "status": "delivered",
  "purchase_at": "2017-10-02T10:56:33.000Z",
  "approved_at": "2017-10-02T11:07:15.000Z",
  "delivered_carrier_at": "2017-10-04T19:55:00.000Z",
  "delivered_customer_at": "2017-10-10T21:25:13.000Z",
  "estimated_delivery_at": "2017-10-18T00:00:00.000Z",
  "customer": {
    "customer_id": "9ef432eb6251297304e76186b10a928d",
    "customer_unique_id": "7c396fd4830fd04220f754e42b4e5bff",
    "city": "sao paulo",
    "state": "SP"
  },
  "items": [
    {
      "order_item_id": 1,
      "product_id": "87285b34884572647811a353c7ac498a",
      "seller_id": "3504c0cb71d7fa48d967e0e4c94d59d9",
      "price": "29.99",
      "freight_value": "8.72"
    }
  ],
  "payments": [
    {
      "payment_sequential": 1,
      "payment_type": "credit_card",
      "payment_installments": 1,
      "payment_value": "18.12"
    }
  ],
  "reviews": [
    {
      "review_id": "a54f0611adc9ed256b57ede6b6eb5114",
      "score": 4,
      "comment_title": null,
      "comment_message": null,
      "creation_at": "2017-10-11T00:00:00.000Z",
      "answer_at": "2017-10-12T03:43:48.000Z"
    }
  ],
  "totals": {
    "items": "29.99",
    "freight": "8.72",
    "order": "38.71",
    "paid": "38.71"
  }
}
```

The values above are examples only. The response must reflect the actual data stored in the database.

---

## Business Rules

### Order identification

The endpoint must search by the external Olist `order_id`.

The internal Rails database ID must not be exposed as the public order identifier.

### Customer

Return the customer associated with the order.

The response must include:

- `customer_id`
- `customer_unique_id`
- `city`
- `state`

### Items

Return every item associated with the order.

Each item must include:

- `order_item_id`
- `product_id`
- `seller_id`
- `price`
- `freight_value`

Items must be ordered by `order_item_id` ascending.

### Payments

Return every payment associated with the order.

Each payment must include:

- `payment_sequential`
- `payment_type`
- `payment_installments`
- `payment_value`

Payments must be ordered by `payment_sequential` ascending.

### Reviews

Return every review associated with the order.

Do not assume that an order has exactly one review.

Each review must include:

- `review_id`
- `score`
- `comment_title`
- `comment_message`
- `creation_at`
- `answer_at`

If the order has no reviews, return:

```json
"reviews": []
```

### Totals

Calculate:

```text
items   = sum of all item prices
freight = sum of all freight values
order   = items + freight
paid    = sum of all payment values
```

All monetary values in the JSON response must be represented with exactly two decimal places.

---

## Missing Order

If the provided `order_id` does not exist, return:

```text
HTTP 404
```

with:

```json
{
  "error": "order_not_found"
}
```

---

## Constraints

- Use the existing Rails application and imported Olist database.
- Do not modify the imported Olist records.
- Do not change the meaning of the existing database schema.
- Do not expose internal Rails IDs in the API response.
- Do not hardcode order-specific values.
- Existing application behavior must continue working.
- The implementation must include automated tests for the behavior introduced by this task.

---

## Acceptance Criteria

The task is considered complete when:

1. `GET /api/orders/:order_id` returns HTTP `200` for an existing order.
2. The order is located using its external Olist `order_id`.
3. The response follows the specified JSON contract.
4. Customer data belongs to the requested order.
5. All order items are returned.
6. Items are ordered by `order_item_id`.
7. All payments are returned.
8. Payments are ordered by `payment_sequential`.
9. All reviews are returned without assuming a one-to-one relationship.
10. Orders without reviews return an empty array.
11. Item, freight, order and paid totals are calculated correctly.
12. Monetary values contain exactly two decimal places.
13. An unknown `order_id` returns HTTP `404`.
14. The `404` response contains `{"error":"order_not_found"}`.
15. Internal Rails IDs are not exposed.
16. Automated tests cover the introduced behavior.
17. The application test suite passes.
