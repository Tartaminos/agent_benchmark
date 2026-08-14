# Task 04 — Admin Orders Dashboard

## Objective

Implement a server-rendered administrative dashboard for browsing and inspecting Olist orders using the existing Rails application and imported dataset.

The implementation must follow the provided visual reference named:

```text
task_4_image_reference
```

The reference image defines the intended information hierarchy, general layout, filter area, table structure, status presentation and order-details panel. Pixel-perfect reproduction is not required, but the final interface should clearly preserve the same structure and usability.

---

## Route

```text
GET /admin/orders
```

The page must be implemented using the existing Rails stack.

Prefer Rails-native server rendering and the Hotwire stack already available in the project. Do not introduce React, Vue or another frontend framework solely for this task.

---

## Orders List

The main page must display a paginated list of orders.

Each order row must include at least:

- external `order_id`
- customer state
- order status
- delivery status
- purchase date
- estimated delivery date
- delivered customer date
- total order amount
- an action for viewing order details

Internal Rails database IDs must not be exposed in the interface.

---

## Delivery Status

Derive the delivery status directly from the order data:

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

The value must be derived from order data and must not be stored as duplicated imported data.

---

## Filters

The dashboard must support the following filters:

### Order ID

Search using the external Olist `order_id`.

### Order Status

Filter by the existing Olist order status.

### Delivery Status

Allow filtering by:

```text
pending
on_time
late
```

### Customer State

Allow filtering orders by the state of the associated customer.

### Purchase Date

Allow filtering by purchase date range.

All filters must be combinable.

---

## Filter Behavior

- Applying filters must update the displayed order list.
- Applied filters must be preserved when navigating between pages.
- Applied filters must be preserved when changing sort order.
- A clear-filters action must restore the unfiltered listing.
- A filter combination with no matching records must display an explicit empty state.

---

## Sorting

Orders must support sorting by purchase date.

The user must be able to choose:

```text
ascending
descending
```

The default ordering must be purchase date descending.

---

## Pagination

The order list must be paginated.

The interface must clearly expose:

- current page
- navigation to previous and next pages when available
- the ability to navigate through the result set

Pagination must preserve active filters and sorting.

Do not load the entire orders table into memory in order to paginate it.

---

## Order Total

For every row, display the total value of the order as:

```text
sum(order item price) + sum(order item freight_value)
```

The value must be calculated from the associated order items.

The implementation must avoid introducing an N+1 query pattern when calculating totals for the paginated list.

---

## Order Details

The user must be able to inspect an order from the dashboard.

The interaction may use a details page, Turbo Frame, Turbo Stream, modal or side panel, as long as it follows the interaction represented by the visual reference and does not require a full frontend framework.

The details view must include at least:

### Order Summary

- external order ID
- order status
- delivery status
- purchase date
- estimated delivery date
- delivered customer date

### Customer

- external customer ID
- customer unique ID
- city
- state

### Totals

- item total
- freight total
- order total
- paid total

The interface may include additional useful order information when appropriate.

---

## UI States

The implementation must provide clear user-facing states for:

- normal loaded results
- empty result set
- filter combination with no results
- invalid or unavailable order details
- loading or transition state when asynchronous Hotwire behavior is used

---

## Responsive Behavior

The page must remain usable on narrower screens.

Exact breakpoint values are not prescribed, but:

- filters must remain understandable and operable;
- table content must remain accessible;
- the order details interaction must remain usable;
- controls must not overlap or become inaccessible.

---

## Accessibility

The implementation must provide basic accessibility appropriate for an administrative interface.

At minimum:

- form controls must have associated labels;
- interactive elements must be keyboard accessible;
- status must not depend exclusively on color;
- buttons and links must have understandable labels;
- semantic HTML should be used where appropriate.

---

## Performance Constraints

The dashboard operates against the full imported Olist dataset.

The implementation must:

- perform filtering in the database;
- perform sorting in the database;
- paginate at the database level;
- avoid N+1 queries for customer information and order totals;
- avoid loading all matching records into Ruby memory;
- avoid performing one aggregate query per displayed order.

---

## Constraints

- Use the existing Rails application and Olist database.
- Do not modify imported Olist records.
- Do not change the semantic meaning of the existing schema.
- Do not hardcode order-specific values.
- Do not expose internal Rails IDs.
- Do not introduce a separate frontend framework solely for this task.
- Existing application behavior must continue working.
- Automated tests must cover the behavior introduced by this task.

---

## Acceptance Criteria

The task is considered complete when:

1. `/admin/orders` renders successfully.
2. The page follows the structure and interaction intent of `task_4_image_reference`.
3. Orders are paginated.
4. The default order is purchase date descending.
5. Orders can be sorted by purchase date ascending or descending.
6. Search by external `order_id` works.
7. Filtering by order status works.
8. Filtering by delivery status works.
9. Filtering by customer state works.
10. Filtering by purchase date range works.
11. Multiple filters can be combined.
12. Filters and sorting are preserved during pagination.
13. Clear filters restores the unfiltered listing.
14. A no-results condition renders an explicit empty state.
15. Each row displays the required order information.
16. Order totals are calculated correctly from item price and freight values.
17. Order details can be opened from the listing.
18. The details view contains the required order, customer and totals information.
19. Internal Rails IDs are not exposed.
20. Filtering, sorting and pagination occur at database level.
21. The listing does not introduce an N+1 pattern for customer data or totals.
22. The interface remains usable on narrower screens.
23. Basic accessibility requirements are satisfied.
24. Automated tests cover the introduced behavior.
25. The application test suite passes.
