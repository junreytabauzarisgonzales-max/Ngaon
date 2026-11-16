# Ngaon API contract (v1)

This is the single source of truth for the Golang backend and the three Flutter apps (Ngaon, Ngaon Rider, Ngaon Merchant).
Everything here is implemented by the apps' HTTP repositories (`packages/go_core/lib/repositories/http/`) and simulated by the mock backend (`packages/go_core/lib/repositories/mock/`).

Example payloads for every model live in [`packages/go_core/assets/mock/*.json`](packages/go_core/assets/mock). The Dart test suite round-trips each fixture through the models (`fromJson → toJson` must be identical), so **the fixtures are the canonical JSON examples**.

Items marked **ADDED** are not in the original brief and were needed to build the apps. Items marked **CLARIFIED** pin down behaviour the brief left open. Both are summarized in [§9](#9-additions-and-open-questions).

---

## 1. Conventions

| Topic | Rule |
| --- | --- |
| Base URL | `${API_BASE_URL}/api/v1` |
| WebSocket | `${WS_URL}/ws?token=<access_token>` |
| JSON keys | `snake_case` |
| IDs | UUID strings |
| Timestamps | ISO 8601 UTC, **no milliseconds**: `2026-11-14T14:05:00Z`. Apps display them in Asia/Manila (UTC+8). |
| Dates (`from`, `to`, `date`) | `YYYY-MM-DD`, interpreted as **Asia/Manila calendar days** (CLARIFIED) |
| Money | integer **centavos** (`15000` = ₱150.00). Never floats. |
| Coordinates | `{ "lat": 5.0294, "lng": 119.7730 }` |
| Phones | E.164 `+639XXXXXXXXX` |
| Optional fields | **omitted** when absent (the apps also accept `null`) |

### Headers (every request)

| Header | Value |
| --- | --- |
| `Authorization` | `Bearer <access_token>` (not on `/auth/otp/*`, `/auth/refresh`) |
| `X-App` | `customer` \| `rider` \| `merchant` |
| `X-App-Version` | e.g. `1.0.0` |
| `Accept-Language` | `en` \| `fil` (server-generated labels such as quote `breakdown[].label` should follow it) |
| `Idempotency-Key` | UUID v4 on `POST /jobs` and `POST /rider/wallet/topups`. The client reuses the same key when retrying the same intent. The server must return the original result for a repeated key. |

### Tokens

* Access token TTL 15 min, refresh token TTL 30 days.
* On `401` with `error.code = token_expired`, the client calls `POST /auth/refresh` **once** (concurrent requests wait for the same refresh), then retries. If refresh fails, it logs out.
* Refresh tokens rotate: `/auth/refresh` returns a new pair.

### Envelopes

Success:

```json
{ "data": { }, "meta": { } }
```

Lists use `meta.next_cursor` (`null` on the last page). Query `?cursor=<opaque>&limit=<n>`. The apps send `limit=20`, or `limit=50` for chat messages and merchant orders.

Error (4xx/5xx):

```json
{ "error": { "code": "validation_failed", "message": "Human readable", "fields": { "phone": "invalid" } } }
```

`fields` is optional. The apps show a translated message per `code`, and fall back to `message`.

### Error codes

| Code | Typical HTTP | When |
| --- | --- | --- |
| `validation_failed` | 422 | Bad input; `fields` tells which |
| `token_expired` | 401 | Access token expired → client refreshes |
| `unauthorized` | 401 | No / bad token, bad refresh token |
| `forbidden` | 403 | Wrong role (e.g. `/merchant/me` for a non-merchant number) |
| `not_found` | 404 | |
| `otp_invalid` / `otp_expired` | 400 | |
| `rate_limited` | 429 | |
| `out_of_service_area` | 422 | Quote pickup/drop-off outside `/service-area` |
| `merchant_closed` | 409 | Food quote for a closed or paused merchant |
| `item_unavailable` | 409 | Sold-out item or add-on option |
| `quote_expired` | 409 | `POST /jobs` with an expired quote |
| `job_not_cancellable` | 409 | |
| `invalid_status_transition` | 409 | Rider/merchant action not allowed now |
| `insufficient_balance` | 402 | Rider going online below `min_balance_centavos` |
| `rider_not_approved` | 403 | |
| `offer_expired` | 409 | Accepting an expired / taken offer |
| `order_already_handled` | 409 | Merchant accept/reject twice |
| `payment_failed` | 402 | |
| `server_error` | 500 | |

---

## 2. Endpoints

### 2.1 Auth (all apps)

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `/auth/otp/request` | `{ phone }` | `{ expires_in_seconds, resend_after_seconds }` |
| POST | `/auth/otp/verify` | `{ phone, code, app }` | `{ access_token, refresh_token, user: User, is_new_user }` |
| POST | `/auth/refresh` | `{ refresh_token }` | `{ access_token, refresh_token }` |
| POST | `/auth/logout` | `{ refresh_token }` | `{}` |
| GET | `/me` | | `User` |
| PATCH | `/me` | `{ name?, email?, language? }` | `User` |
| DELETE | `/me` | | `{}` |
| POST | `/me/devices` | `{ fcm_token, platform: "android", app }` | `{}` |

* After `verify` with `is_new_user = true` (or an empty `name`), the apps ask for a name and call `PATCH /me`.
* `/auth/otp/verify` succeeds for any phone. **Role checks happen later**, e.g. `GET /merchant/me` returns `forbidden` (CLARIFIED, matches the merchant "not registered" screen).
* `fcm_token` is a classic FCM registration token. See the FCM note in §9.

### 2.2 Places and geo (customer, rider)

| Method | Path | Body / query | Returns |
| --- | --- | --- | --- |
| GET | `/me/places` | | `[SavedPlace]` |
| POST | `/me/places` | `{ label, address, location }` | `SavedPlace` |
| DELETE | `/me/places/{id}` | | `{}` |
| GET | `/geo/reverse` | `?lat=&lng=` | `{ address }` |
| GET | `/geo/search` | `?q=&lat=&lng=` | `[ { name, address, location } ]` (nearest first, max 10) |
| GET | `/service-area` | | `{ zones: [ { id, name, polygon: [LatLng] } ] }` |

### 2.3 Merchants, public view (customer)

| Method | Path | Query | Returns |
| --- | --- | --- | --- |
| GET | `/merchants` | `?lat=&lng=&q=&cursor=&limit=` | `[Merchant]` (no `menu`; includes `distance_m`; open first, then nearest) |
| GET | `/merchants/{id}` | | `Merchant` with `menu: [MenuCategory]` (sold-out items included with `is_available=false`) |

`q` matches merchant names **and menu item names** (CLARIFIED).

### 2.4 Quotes and jobs (customer)

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `/quotes` | `QuoteRequest` | `Quote` (valid ~5 min, `expires_at`) |
| POST | `/jobs` | `{ quote_id, payment_method, notes? }` + `Idempotency-Key` | `Job` |
| GET | `/jobs` | `?status=active\|past&cursor=&limit=` | `[Job]` (newest first) |
| GET | `/jobs/{id}` | | `Job` |
| POST | `/jobs/{id}/cancel` | `{ reason }` | `Job` |
| POST | `/jobs/{id}/confirm-items` | `{ approved: bool }` | `Job` |
| POST | `/jobs/{id}/rate` | `{ rider_rating, rider_tags, comment?, merchant_rating? }` | `{}` |
| POST | `/jobs/{id}/share` | | `{ url, expires_at }` |
| POST | `/jobs/{id}/sos` | `{ location }` | `{}` |
| POST | `/jobs/{id}/call` | | `{ masked_number }` (also used by the rider) |

Notes:

* `notes` from `POST /jobs` is stored as `dropoff.notes` (CLARIFIED). That's where the rider app shows it.
* Online payments (`gcash`, `maya`): the job starts in `pending_payment` with `payment.checkout_url`. The app opens it in an in-app browser tab, then polls `GET /jobs/{id}` every 4 s (and listens to `job.updated`) until `payment.status` is `paid` or `failed`.
* `confirm-items` with `approved=false` (dispute): see §9, open question 1.
* After a successful `rate`, the server removes `rate` from `allowed_actions` (CLARIFIED).
* Pabili quote: `estimated_item_total_centavos` greater than the server's `max_item_budget_centavos` → `validation_failed` with `fields.estimated_item_total_centavos`. The quote's `total_centavos` is **fees only**. When the rider uploads the receipt, the job's `fare.breakdown` gains an `Items (receipt)` line and `fare.total_centavos` includes it (CLARIFIED).
* **Pabili without a store pin** (CLARIFIED): the app sends `pickup.address = store_name` and `pickup.location = dropoff.location`. The rider shops near the customer.
* Padala: the app copies the recipient into `dropoff.contact_name` / `dropoff.contact_phone` (E.164).

### 2.5 Chat (customer, rider)

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| GET | `/jobs/{id}/messages` | `?cursor=&limit=` | `[ChatMessage]` (oldest first) |
| POST | `/jobs/{id}/messages` | `{ text?, image_key? }` | `ChatMessage` |

The sender is derived from `X-App`. New messages from the other party arrive as `chat.message`.

### 2.6 Uploads (all apps)

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `/uploads` | `{ purpose, content_type: "image/jpeg" }` | `{ upload_url, key, expires_at }` |

`purpose` ∈ `rider_license`, `rider_orcr`, `rider_selfie`, `rider_clearance`, `receipt`, `proof_of_delivery`, `parcel_photo`, `chat_image`, `menu_item_photo`, `merchant_logo`, `merchant_cover`.

Flow:

1. The client compresses to max 1280 px, ~70 % JPEG.
2. `POST /uploads`.
3. `PUT` the bytes to `upload_url` with `Content-Type: image/jpeg` and **no auth header**.
4. The client sends only `key` to the related endpoint.

### 2.7 Rider

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| GET | `/rider/me` | | `RiderProfile` |
| PUT | `/rider/me` | `{ vehicle: { plate, make_model, color }, documents: { license_key, orcr_key, selfie_key, clearance_key } }` | `RiderProfile` (→ `pending_review`) |
| POST | `/rider/status` | `{ online, location }` | `RiderProfile` |
| POST | `/rider/location` | `{ location, heading?, speed_kph?, recorded_at }` | `{}` (fallback when WS is down) |
| GET | `/rider/offers/current` | | `JobOffer` or `null` |
| POST | `/rider/offers/{id}/accept` | | `Job` |
| POST | `/rider/offers/{id}/decline` | `{ reason? }` (`"timeout"` when the 15 s countdown ends) | `{}` |
| GET | `/rider/jobs/active` | | `Job` or `null` |
| GET | `/rider/jobs` | `?cursor=&from=&to=&limit=` | `[Job]` |
| POST | `/rider/jobs/{id}/status` | `{ status, location, proof_key?, receipt_key?, item_total_centavos? }` | `Job` |
| GET | `/rider/earnings` | `?from=YYYY-MM-DD&to=YYYY-MM-DD` | `{ total_centavos, jobs_count, days: [ { date, total_centavos, jobs_count } ] }` |
| GET | `/rider/wallet` | | `{ balance_centavos, min_balance_centavos }` |
| GET | `/rider/wallet/transactions` | `?cursor=&limit=` | `[WalletTransaction]` (newest first) |
| POST | `/rider/wallet/topups` | `{ amount_centavos, method }` + `Idempotency-Key` | `{ topup_id, checkout_url }` |

* `POST /rider/status {online:true}` fails with `rider_not_approved` or `insufficient_balance`.
* `items_purchased` requires `receipt_key` + `item_total_centavos`. `completed` for food/padala/pabili requires `proof_key`. Otherwise `validation_failed` with `fields`.
* Location cadence: every 5 s while moving, every 20 s when stationary, over WS `rider.location`. The fallback is `POST /rider/location`.
* When a top-up is credited (or the balance changes for any reason), the server emits `rider.profile_updated` with the new `balance_centavos` (CLARIFIED, so no extra event type is needed).

### 2.8 Merchant

| Method | Path | Body / query | Returns |
| --- | --- | --- | --- |
| GET | `/merchant/me` | | `MerchantAccount` (`forbidden` if the user is not a merchant) |
| PATCH | `/merchant/store` | `{ is_open?, paused_until?, prep_time_minutes?, min_order_centavos?, hours?, logo_key?, cover_key?, name? }` | `Merchant` |
| GET | `/merchant/orders` | `?status=new\|preparing\|ready\|done&from=&to=&cursor=&limit=` | `[MerchantOrder]` (newest first) |
| GET | `/merchant/orders/{id}` | | `MerchantOrder` |
| POST | `/merchant/orders/{id}/accept` | `{ prep_time_minutes }` (5–60) | `MerchantOrder` |
| POST | `/merchant/orders/{id}/reject` | `{ reason: "out_of_stock"\|"too_busy"\|"closing_soon"\|"other", note? }` | `MerchantOrder` |
| POST | `/merchant/orders/{id}/ready` | | `MerchantOrder` |
| GET | `/merchant/menu` | | `[MenuCategory]` (includes unavailable items, sorted by `sort_order`) |
| POST | `/merchant/menu/categories` | `{ name }` | `MenuCategory` |
| PATCH | `/merchant/menu/categories/{id}` | `{ name? }` | `MenuCategory` |
| DELETE | `/merchant/menu/categories/{id}` | | `{}` (`validation_failed` if not empty) |
| PUT | `/merchant/menu/categories/order` | `{ category_ids: [id] }` | `{}` |
| POST | `/merchant/menu/items` | `MenuItemInput` | `MenuItem` |
| PUT | `/merchant/menu/items/{id}` | `MenuItemInput` | `MenuItem` |
| DELETE | `/merchant/menu/items/{id}` | | `{}` |
| PATCH | `/merchant/menu/items/{id}/availability` | `{ is_available }` | `MenuItem` |
| PATCH | `/merchant/menu/addon-options/{id}/availability` | `{ is_available }` | `{}` |
| GET | `/merchant/reports/sales` | `?from=&to=` | `SalesReport` |
| GET | `/merchant/payouts` | `?cursor=&limit=` | `[Payout]` |

* **`status=done`** (CLARIFIED) returns orders with `MerchantOrder.status` ∈ `picked_up`, `completed`, `rejected`, `cancelled`. The board's "Done today" column sends `from=to=<today in Manila>`, filtered on `created_at`.
* **Resuming orders** (CLARIFIED): `PATCH /merchant/store` with an explicit `"paused_until": null` clears a pause. A missing key means "unchanged".
* `hours` replaces the whole week. Weekdays missing from the array are closed.
* `MenuItemInput`: `id` present on a group/option = update, absent = create. Groups/options not in the list are deleted.

---

## 3. Models

All timestamps are UTC ISO strings. `?` = optional (omitted when absent).

```
User            { id, phone, name, email?, language: "en"|"fil", roles: ["customer"|"rider"|"merchant"], created_at }
LatLng          { lat, lng }
SavedPlace      { id, label, address, location: LatLng }
Stop            { address, location: LatLng, contact_name?, contact_phone?, notes? }

Merchant        { id, name, logo_url?, cover_url?, address, location, is_open, paused_until?,
                  hours: [OpeningHours], prep_time_minutes, rating?, min_order_centavos, distance_m?,
                  menu?: [MenuCategory] }
OpeningHours    { weekday: 0-6 (0 = Sunday), opens: "HH:mm", closes: "HH:mm" }
MenuCategory    { id, name, sort_order, items: [MenuItem] }
MenuItem        { id, category_id, name, description?, photo_url?, price_centavos, is_available, addon_groups: [AddonGroup] }
AddonGroup      { id, name, min_select, max_select, options: [AddonOption] }
AddonOption     { id, name, price_centavos, is_available }
MenuItemInput   { category_id, name, description?, photo_key?, price_centavos, is_available,
                  addon_groups: [ { id?, name, min_select, max_select,
                                    options: [ { id?, name, price_centavos, is_available } ] } ] }

QuoteRequest    { service: "ride"|"food"|"pabili"|"padala", pickup: Stop, dropoff: Stop,
                  food?:   { merchant_id, items: [ { item_id, quantity, addon_option_ids: [id], note? } ] },
                  pabili?: { store_name, items: [ { name, quantity, note? } ], estimated_item_total_centavos },
                  padala?: { size: "small"|"medium"|"large", description, recipient_name, recipient_phone, photo_key? } }
Quote           { id, service, distance_m, duration_s, expires_at,
                  breakdown: [ { label, amount_centavos } ], total_centavos, max_item_budget_centavos? }

Job             { id, code ("NG-4821"), service, status, created_at, updated_at,
                  pickup: Stop, dropoff: Stop,
                  rider?: { id, name, photo_url?, phone_masked, plate, make_model, color, rating?, location?: LatLng },
                  merchant?: { id, name, phone_masked },
                  food?: { items: [ { name, quantity, addons: [string], note?, line_total_centavos } ],
                           subtotal_centavos, prep_time_minutes?, ready_at?, is_ready,
                           rider_pays_merchant_centavos? },                       // ADDED
                  pabili?: { store_name, items: [ { name, quantity, note? } ], receipt_url?, item_total_centavos? },
                  padala?: { size, description, recipient_name, recipient_phone, photo_url? },
                  fare: { breakdown: [ { label, amount_centavos } ], total_centavos },
                  payment: { method: "cash"|"gcash"|"maya", status: "pending"|"paid"|"failed"|"refunded", checkout_url? },
                  proof_url?, cancel_reason?, cancelled_by?: "customer"|"rider"|"merchant"|"system",
                  allowed_actions: [string],                                       // see §4
                  timeline: [ { status, at } ] }

JobOffer        { id, job: Job, earnings_centavos, pickup_distance_m, expires_at }
RiderProfile    { id, user_id, status: "incomplete"|"pending_review"|"approved"|"rejected"|"suspended",
                  rejection_reason?, is_online, vehicle?: { plate, make_model, color }, rating?,
                  balance_centavos, min_balance_centavos }
WalletTransaction { id, type: "topup"|"commission"|"earning"|"adjustment"|"payout",
                  amount_centavos (signed), balance_after_centavos, job_id?, note?, created_at }

MerchantAccount { merchant: Merchant, role: "owner"|"staff", staff_name }
MerchantOrder   { id, job_id, code, status: "new"|"preparing"|"ready"|"picked_up"|"completed"|"rejected"|"cancelled",
                  created_at, merchant_accept_deadline?, prep_time_minutes?, ready_at?,
                  items: [ { name, quantity, addons: [string], note?, line_total_centavos } ],
                  subtotal_centavos, commission_centavos, net_centavos,
                  payment_method: "cash"|"gcash"|"maya",
                  rider_pays_at_pickup_centavos?,            // present for cash orders
                  rider?: { name, photo_url?, plate, phone_masked },
                  customer_first_name, notes?, reject_reason?, allowed_actions: [string] }
SalesReport     { from, to, orders_count, gross_centavos, commission_centavos, net_centavos,
                  days: [ { date, orders_count, gross_centavos, net_centavos } ] }
Payout          { id, period_from, period_to, amount_centavos, type: "payout"|"commission_invoice",
                  status: "pending"|"paid"|"overdue", paid_at? }

ChatMessage     { id, job_id, sender: "customer"|"rider"|"system", text?, image_url?, created_at }
```

**ADDED: `Job.food.rider_pays_merchant_centavos`.** For cash food orders, this is what the rider hands the merchant at pickup. It must equal `MerchantOrder.rider_pays_at_pickup_centavos`. The rider app shows "Pay merchant ₱X" from it. The original `Job` had no field for this amount (`subtotal_centavos` is the customer price before commission).

Privacy: other parties' phones are only ever `phone_masked`. Calls go through `POST /jobs/{id}/call`. (`padala.recipient_phone` is the customer's own input.)

---

## 4. `allowed_actions`

The apps never hard-code business rules. They show buttons only from `allowed_actions` plus the status.

**CLARIFIED: `Job.allowed_actions` depends on the requesting app (`X-App`).**

| App | Possible values |
| --- | --- |
| customer | `cancel`, `chat`, `call`, `sos`, `share`, `confirm_items`, `rate` |
| rider (**ADDED**) | the **target status** the rider may set next via `POST /rider/jobs/{id}/status` (`arrived_pickup`, `items_purchased`, `picked_up`, `arrived_dropoff`, `completed`), plus `chat`, `call` |

Rider examples:

* Food at `arrived_pickup` while `food.is_ready = false` → `["chat","call"]`. The app shows "Waiting for the restaurant…".
* Then `food.is_ready = true` → `["picked_up","chat","call"]`.
* Pabili at `items_purchased` → `["chat","call"]`. The rider waits for the customer to confirm.

`MerchantOrder.allowed_actions` ⊆ `accept`, `reject`, `ready`.

Mock reference behaviour (customer): `cancel` while `pending_payment … rider_assigned`; `chat`/`call` while a rider is assigned and the job is not final; `sos`/`share` only for rides with a rider; `confirm_items` at `items_purchased`; `rate` after `completed` until rated.

---

## 5. Job statuses

```
pending_payment      -> searching | merchant_pending   (online payment confirmed; cash jobs skip this status)
merchant_pending     -> merchant_preparing   (MERCHANT accept)        | cancelled (MERCHANT reject, or deadline passed)
merchant_preparing   -> searching            (backend starts dispatch before prep ends)
searching            -> rider_assigned       (RIDER accepts offer)    | cancelled (no rider in 5 min)
rider_assigned       -> arrived_pickup       (RIDER)
arrived_pickup       -> picked_up            (RIDER; Ride/Food/Padala)
arrived_pickup       -> items_purchased      (RIDER; Pabili, needs receipt_key + item_total_centavos)
items_purchased      -> picked_up            (backend, after CUSTOMER confirm-items approved = true)
picked_up            -> arrived_dropoff      (RIDER)
arrived_dropoff      -> completed            (RIDER; Food/Padala/Pabili need proof_key)
any non-final        -> cancelled            (per allowed_actions)
```

Final statuses: `completed`, `cancelled`. Merchant "Mark ready" does **not** change the job status. It sets `food.is_ready = true` and `food.ready_at`, and `MerchantOrder.status = ready`.

`MerchantOrder.status` mapping (implemented and unit-tested in `go_core/lib/utils/job_flow.dart → merchantOrderStatusFor`):

| Job status | MerchantOrder.status |
| --- | --- |
| `pending_payment`, `merchant_pending` | `new` |
| `merchant_preparing`, `searching`, `rider_assigned`, `arrived_pickup` (`items_purchased`) | `preparing`, or `ready` once marked |
| `picked_up`, `arrived_dropoff` | `picked_up` |
| `completed` | `completed` |
| `cancelled` by merchant | `rejected` |
| `cancelled` otherwise (incl. accept deadline passed, `cancelled_by = system`) | `cancelled` |

---

## 6. WebSocket

* Connect `${WS_URL}/ws?token=<access_token>`. The server closes with **4001** on token expiry. The client refreshes, then reconnects immediately.
* Message frame: `{ "type": "<event>", "id": "<uuid>", "data": { … } }`.
* Reconnect: exponential backoff 1, 2, 4 … max 30 s, + up to 30 % jitter. After reconnecting, the apps refetch over REST:
  * customer: active jobs
  * rider: profile, active job, current offer
  * merchant: new / preparing / ready / done-today orders

Client → server:

| Type | Data | App |
| --- | --- | --- |
| `ping` (every 25 s; server replies `pong`) | `{}` | all |
| `rider.location` | `{ location, heading?, speed_kph?, recorded_at }` | rider |
| `job.subscribe` / `job.unsubscribe` | `{ job_id }` | customer tracking screen |

Server → client:

| Type | Data | App |
| --- | --- | --- |
| `pong` | `{}` | all |
| `job.updated` | `{ job: Job }` (with `allowed_actions` for the receiving app) | customer, rider |
| `rider.location` | `{ job_id, location, heading? }` | customer |
| `offer.new` | `{ offer: JobOffer }` | rider |
| `offer.expired` | `{ offer_id }` | rider |
| `rider.profile_updated` | `{ profile: RiderProfile }` (approval, rejection, balance changes) | rider |
| `chat.message` | `{ message: ChatMessage }` | customer, rider |
| `order.new` | `{ order: MerchantOrder }` | merchant |
| `order.updated` | `{ order: MerchantOrder }` (incl. rider assigned, picked up, auto-cancel at deadline) | merchant |
| `merchant.updated` | `{ merchant: Merchant }` | merchant |

## 7. Push (FCM)

* Same `type` names as the WebSocket. Payloads are **data-only** with IDs: `job_id`, `offer_id`, `order_id`. Always refetch over REST before showing details.
* `offer.new` and `order.new` must be sent as **high-priority data messages**. The apps show a full-screen alarm notification from the background handler.

## 8. Mock mode reference

`USE_MOCK_API=true` runs the same contract in memory (`MockBackend`):

* The OTP is always `123456`.
* Phones ending `1111` are new users: the customer is asked for a name, and the rider profile is `incomplete`.
* In the merchant app, phones ending `0000` get `forbidden` from `/merchant/me`.
* Simulated other parties: Section 8 of the brief. Timings live in `mock_backend.dart`.

---

## 9. Additions and open questions

| # | Kind | Item | Why |
| --- | --- | --- | --- |
| A1 | **ADDED** field | `Job.food.rider_pays_merchant_centavos?` | The rider app must show "Pay merchant ₱X" for cash food orders. `Job` had no such amount. |
| A2 | **ADDED** semantics | Rider `allowed_actions` = next target statuses + `chat`/`call` | The brief says all apps derive buttons from `allowed_actions`, but only defined customer values. |
| C1 | CLARIFIED | `GET /merchant/orders?status=done` = `picked_up`/`completed`/`rejected`/`cancelled`; `from`/`to` are Manila dates on `created_at` | The "Done today" column. |
| C2 | CLARIFIED | `PATCH /merchant/store` `"paused_until": null` resumes orders | Needed to cancel a pause early. |
| C3 | CLARIFIED | Pabili without a store pin: `pickup.location = dropoff.location`, `pickup.address = store_name` | `pickup` is required in `QuoteRequest`, but the pin is optional. |
| C4 | CLARIFIED | `POST /jobs` `notes` → `dropoff.notes` | So the rider sees it. |
| C5 | CLARIFIED | Balance changes are announced with `rider.profile_updated` | The wallet updates after a top-up without a new event type. |
| C6 | CLARIFIED | All `from`/`to`/`date` are Asia/Manila calendar dates | Avoids off-by-one days around midnight UTC+8. |
| C7 | CLARIFIED | `rate` disappears from `allowed_actions` after rating; `sos`/`share` only for rides | |
| C8 | CLARIFIED | Pabili quote `total_centavos` = fees only; the receipt total is added to `fare` at `items_purchased` | The customer pays items + fees. |
| Q1 | **OPEN** | `confirm-items` with `approved=false`: the mock cancels the job (`cancelled_by=customer`, reason "Item total disputed…"). | The brief doesn't define the dispute flow (refund the rider? support ticket?). Product decision needed. |
| Q2 | **OPEN** | FCM token type | `firebase_messaging` 17 deprecates `getToken()` in favour of Firebase Installation IDs ("direct send"). The apps still send a classic registration token as `fcm_token`. If the backend moves to FID direct-send, rename the field or add `fid`. |
| Q3 | OPEN | Rider cancel / "can't complete" | Not in the brief. The rider app offers no cancel button, so riders must contact support. |

### 9.1 Provider integrations (ADDED)

| # | Kind | Item | Why |
| --- | --- | --- | --- |
| A3 | **ADDED** field | `Quote.route_polyline?`, `Job.route_polyline?`: Google encoded polyline (precision 5) of the pickup → drop-off road route | Draw the route on maps. Present only when Google Maps is configured. |
| A4 | **ADDED** field | `RiderProfile.kyc_status?`: `not_started` \| `in_progress` \| `in_review` \| `approved` \| `declined` \| `expired` | Rider identity verification (Didit). Absent when KYC is not enabled. While present and not `approved`, the rider stays `pending_review`. `declined` moves the profile to `rejected`. |
| A5 | **ADDED** endpoint | `POST /rider/kyc/session` → `{ session_id, url, kyc_status }` | Starts (or resumes) a Didit session. The app opens `url` in an in-app browser, then polls `GET /rider/me`. |
| A6 | **ADDED** endpoints | `POST /webhooks/paymongo`, `POST /webhooks/didit` (provider → backend, not called by the apps) | Payment / KYC callbacks. The backend verifies signatures and re-fetches the payment or decision from the provider before acting. |
| C9 | CLARIFIED | `payment.checkout_url` is the PayMongo hosted checkout when PayMongo is configured. `GET /jobs/{id}` and `GET /rider/wallet` / `GET /rider/me` check PayMongo for pending payments, so polling works without webhooks. | LAN testing; webhook delivery delays |
| C10 | CLARIFIED | Booking codes are `NG-1234` | Brand |
