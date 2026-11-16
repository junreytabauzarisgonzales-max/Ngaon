# Go Delivery Backend (Go + PostgreSQL + Redis)

Production-ready Golang backend implementing the **Go** super-app contract (`API_CONTRACT.md`) for **Go Customer**, **Go Rider**, and **Go Merchant** across all four service verticals:
- **Ride** (`ride`) — Passenger motorcycle taxi / ride-hailing
- **Food** (`food`) — Restaurant food ordering and delivery
- **Pabili** (`pabili`) — Personal shopping / errand buying with receipt confirmation
- **Padala** (`padala`) — Point-to-point parcel and document courier

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Redis Integration & Key Schema](#2-redis-integration--key-schema)
3. [Security Implementation](#3-security-implementation)
4. [Configuration & Environment Variables](#4-configuration--environment-variables)
5. [Quick Start & Running Tests](#5-quick-start--running-tests)
6. [Complete API Endpoint Reference](#6-complete-api-endpoint-reference)
   - [6.1 Common Headers, Envelopes & Pagination](#61-common-headers-envelopes--pagination)
   - [6.2 System & Health Endpoints](#62-system--health-endpoints)
   - [6.3 Authentication & User Profile Endpoints](#63-authentication--user-profile-endpoints)
   - [6.4 Saved Places & Geolocation Endpoints](#64-saved-places--geolocation-endpoints)
   - [6.5 Merchants — Public Customer View](#65-merchants--public-customer-view)
   - [6.6 Quotes & Jobs (Bookings)](#66-quotes--jobs-bookings)
   - [6.7 Job Chat Endpoints](#67-job-chat-endpoints)
   - [6.8 File Uploads & Static File Serving](#68-file-uploads--static-file-serving)
   - [6.9 Rider Endpoints](#69-rider-endpoints)
   - [6.10 Merchant Portal Endpoints](#610-merchant-portal-endpoints)
   - [6.11 Real-Time WebSocket API](#611-real-time-websocket-api)
   - [6.12 Checkout, Live Share & Admin Pages](#612-checkout-live-share--admin-pages)

---

## 1. Architecture Overview

```
cmd/server/main.go               Entrypoint, HTTP server timeouts, graceful shutdown
internal/
  config/config.go               Environment-driven configuration loader
  domain/                        Core domain models (User, Job, Quote, Rider, Merchant, Wallet, Chat, Geo)
  repository/
    state.go                     In-memory operational state graph
    postgres/postgres.go         PostgreSQL relational persistence & schema migrations
    redis/redis.go               Redis cache, sessions, rate limiter, geo index, and Pub/Sub
    file/file.go                 Fallback JSON snapshot persistence (/data/state.json)
    seed/                        Initial Bongao merchants, menus, service areas, and landmarks
  service/
    service.go                   Core business orchestration, state locking, event emission
    jwt.go                       HS256 JWT signing/verification, token hashing, revocation & rate limiting
    dispatch.go                  Rider matching, offer lifecycle, background ticker
    view.go                      Role-specific projections & allowed_actions state machine
  api/
    router.go                    HTTP ServeMux route wiring & healthcheck
    middleware.go                Auth, Redis/memory rate limiting, CORS, security headers, panic recovery
    auth.go                      OTP auth, token refresh/logout, user profile, places & geocoding
    jobs.go                      Public merchants, quotes, job lifecycle, chat, signed JPEG uploads
    rider.go                     Rider KYC, online status, live location, offers, job steps, wallet
    merchant.go                  Store settings, incoming order board, menu CRUD, sales & payouts
    ws.go                        Authenticated WebSocket server (/ws)
    pages.go                     Dev payment checkout, live trip share page, and admin portal
  websocket/hub.go               Concurrent WebSocket connection hub per user & app
```

---

## 2. Redis Integration & Key Schema

When `REDIS_URL` is configured, the backend connects to Redis (`internal/repository/redis/redis.go`) for low-latency ephemeral state, distributed security controls, geospatial indexing, and multi-instance WebSocket fan-out. When `REDIS_URL` is unset (e.g. unit tests), the service seamlessly falls back to thread-safe in-memory equivalents.

| Redis Key Pattern | Type | TTL | Purpose |
| --- | --- | --- | --- |
| `goapp:rl:<scope>:<ip>` | `STRING` (Counter) | `60s` | Atomic Lua fixed-window rate limiter per IP (`auth_ip`, `api_ip`, `admin_ip`). |
| `goapp:otp:sent:<phone>` | `ZSET` | `10m` | Sliding-window log of OTP request timestamps (max 5 requests per 10 minutes per phone). |
| `goapp:otp:code:<phone>` | `STRING` | `5m` | HMAC-SHA256 hash of the active 6-digit OTP code for `<phone>`. |
| `goapp:otp:attempts:<phone>` | `STRING` (Counter) | `5m` | Failed OTP verification counter (locks out with `429 rate_limited` after 5 wrong attempts). |
| `goapp:refresh:<sha256_hash>` | `STRING` (JSON) | `30d` | Active refresh token metadata (`user_id`, `app`, `expires`) indexed by SHA-256 token hash. |
| `goapp:user:refresh:<user_id>` | `SET` | `30d` | Set of active refresh token hashes belonging to `<user_id>` for bulk session revocation. |
| `goapp:user:profile:<user_id>` | `STRING` (JSON) | `30d` | Cached user profile (`User`) for cross-instance session & profile resolution; deleted on `DELETE /me`. |
| `goapp:user:phone:<phone>` | `STRING` | `30d` | Phone-to-user-ID lookup index in Redis. |
| `goapp:jwt:revoked:<jti_or_hash>` | `STRING` | Remaining JWT exp (`≤15m`) | Revoked access token blacklist entry (`<jti>`), rotated/revoked refresh token tombstone (`rt:<hash>`), or deleted user session marker (`user:<uid>`). |
| `goapp:quote:<quote_id>` | `STRING` (JSON) | `5m` | Cached price quote and original `QuoteRequest` payload; deleted upon job creation. |
| `goapp:offer:<offer_id>` | `STRING` (JSON) | `15s` | Active rider dispatch offer with countdown TTL. |
| `goapp:rider:offer:<user_id>` | `STRING` | `15s` | Pointer from a rider's user ID to their currently active `<offer_id>`. |
| `goapp:idempotency:<uid>:<key>` | `STRING` | `24h` | Maps client `Idempotency-Key` header on `POST /jobs` and `POST /rider/wallet/topups` to created entity ID. |
| `goapp:riders:geo` | `GEO` (`ZSET`) | Persistent while online | Geospatial index (`GEOADD` / `GEOSEARCH`) of online riders' live coordinates; removed on offline/delete. |
| `goapp:rider:loc:<user_id>` | `STRING` (JSON) | `15m` | Rider's latest coordinates, heading, and timestamp. |
| `goapp:cache:merchant:<id>` | `STRING` (JSON) | `5m` | Cached public merchant details + full menu; automatically invalidated on store, menu, or rating updates. |
| `goapp:ws:events` | `PUBSUB` | Ephemeral | Real-time WebSocket event broadcast channel across API instances (deduplicated by `instance_id`). |

---

## 3. Security Implementation

### 3.1 Redis & Container Security
- **Authentication Required**: Redis runs with `--requirepass ${REDIS_PASSWORD}` and `--protected-mode yes`. Healthchecks authenticate via `REDISCLI_AUTH`.
- **Dangerous Commands Disabled**: `FLUSHALL`, `FLUSHDB`, `CONFIG`, and `DEBUG` are renamed to `""` in `docker-compose.yml` so they cannot be invoked even if a connection is compromised.
- **Memory & Eviction Safety**: Configured with `--maxmemory 256mb --maxmemory-policy volatile-lru` and AOF persistence (`--appendonly yes`).
- **Least Privilege Containers**: All services in `docker-compose.yml` enforce `security_opt: ["no-new-privileges:true"]`, and the Go binary runs as non-root user `go` (`UID 10001`) in a minimal Alpine image.

### 3.2 Authentication, JWT & Session Hardening
- **Algorithm Confusion Prevention**: `ParseJWT` explicitly decodes the JWT header and enforces `"alg": "HS256"`, rejecting `alg: none` or unexpected algorithms.
- **Access Token Revocation (JTI Blacklist)**: Every access token includes `jti` (UUID v4) and `iat`. Calling `POST /auth/logout` or `DELETE /me` immediately blacklists the caller's access token in Redis (`goapp:jwt:revoked:<jti>`) and memory until its natural expiry, and middleware verifies the user still exists.
- **Hashed Refresh Tokens at Rest**: Raw 256-bit refresh tokens are **never** stored in memory, `state.json`, PostgreSQL, or Redis. Only `SHA-256(raw_token)` is stored, and every `POST /auth/refresh` performs single-use rotation.
- **Cryptographic OTP Protection**: OTPs are generated via `crypto/rand`, stored as `HMAC-SHA256(JWTSecret, "otp:"+phone+":"+code)`, and verified using constant-time comparison (`crypto/subtle.ConstantTimeCompare`). Plaintext OTPs are redacted from logs when `DEV_OTP_CODE` is unset.

### 3.3 Distributed Rate Limiting
- Atomic Redis Lua script (`INCR` + `PEXPIRE`) enforces per-IP rate limits with automatic in-memory fallback:
  - `/api/v1/auth/*` and `/admin`: `AUTH_RATE_LIMIT_PER_MIN` (default `30` req/min per IP)
  - General `/api/v1/*`: `RATE_LIMIT_PER_MIN` (default `300` req/min per IP)
  - Per-phone OTP request limit: max `5` requests per `10` minutes (`goapp:otp:sent:<phone>`)
  - Per-OTP verification limit: max `5` attempts per code (`goapp:otp:attempts:<phone>`)
- Responses include `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `Retry-After` on `429 Too Many Requests`.

### 3.4 File Upload & HTTP Hardening
- **Upload Validation**: `PUT /upload/{key}` verifies the HMAC-SHA256 signature and expiration timestamp, restricts body size to `10 MB` (`http.MaxBytesReader`), verifies the file begins with JPEG SOI magic bytes (`\xff\xd8`) (returning `415 Unsupported Media Type` otherwise), cleans up partial files on error, and prevents directory traversal by verifying the resolved path stays inside `<DATA_DIR>/uploads/`.
- **Safe File Delivery**: `GET /files/{key}` serves files with `Content-Type: image/jpeg`, `X-Content-Type-Options: nosniff`, and `Content-Security-Policy: default-src 'none'`.
- **HTTP Security Headers & Timeouts**: Every response includes `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, `X-XSS-Protection: 0`, and `Permissions-Policy: geolocation=(), microphone=(), camera=()`. Auth/profile responses set `Cache-Control: no-store`. `http.Server` enforces `ReadHeaderTimeout` (10s), `ReadTimeout` (30s), `WriteTimeout` (30s), `IdleTimeout` (120s), `MaxHeaderBytes` (1 MB), and JSON body limit (1 MB). WebSocket connections enforce a 64 KB frame read limit.
- **Constant-Time Admin Auth**: `/admin` verifies the admin token using `subtle.ConstantTimeCompare` and accepts `?token=`, `X-Admin-Token`, or `Authorization: Bearer`.

---

## 4. Configuration & Environment Variables

Copy `.env.example` to `.env` before starting:

| Variable | Default | Description |
| --- | --- | --- |
| `PORT` | `8080` | HTTP/WebSocket listen port. |
| `PUBLIC_URL` | `http://localhost:8080` | Base URL reachable by phones (used in file URLs, payment checkout URLs, and share links). |
| `DATA_DIR` | `./data` | Directory for uploaded JPEGs (`uploads/`) and fallback `state.json`. |
| `DATABASE_URL` | *(empty)* | PostgreSQL connection string (`postgres://user:pass@host:5432/db?sslmode=disable`). |
| `REDIS_URL` | *(empty)* | Redis connection string (`redis://:password@host:6379/0` or `rediss://` for TLS). |
| `REDIS_PASSWORD` | `goapp_redis_secret` | Password required by the `go-redis` container in `docker-compose.yml`. |
| `REDIS_PORT` | `6379` | Host port mapped to Redis container port `6379`. |
| `JWT_SECRET` | `dev-only-change-me` | HMAC-SHA256 secret key for JWTs, OTP hashes, and upload URL signatures. **Change in production.** |
| `ADMIN_TOKEN` | `change-me` | Secret token for `/admin` rider approval portal. **Change in production.** |
| `DEV_OTP_CODE` | *(empty in prod, `123456` in `.env.example`)* | When set, this static OTP code is accepted for any phone and OTPs are logged. Unset in production. |
| `AUTO_APPROVE_RIDERS_SECONDS` | `0` | When `> 0`, pending rider KYC submissions auto-approve after `N` seconds. |
| `RIDER_START_BALANCE` | `0` | Initial wallet balance (in centavos) credited to newly registered riders in dev. |
| `DEV_ANY_LOCATION` | `false` | When `true`, accepts pickups/drop-offs anywhere outside Bongao. |
| `MAX_DISPATCH_M` | `15000` | Maximum rider-to-pickup distance in meters for job offers (`0` = unlimited). |
| `CORS_ALLOWED_ORIGINS` | `*` | Comma-separated list of allowed CORS origins, or `*`. |
| `TRUSTED_PROXIES` | *(empty)* | Comma-separated list of trusted reverse-proxy IPs or CIDRs (e.g. `127.0.0.1/32,10.0.0.0/8`) allowed to supply `X-Forwarded-For` / `X-Real-IP`. |
| `RATE_LIMIT_PER_MIN` | `300` | Max general `/api/v1/*` requests per minute per IP. |
| `AUTH_RATE_LIMIT_PER_MIN` | `30` | Max `/api/v1/auth/*` and `/admin` requests per minute per IP. |

---

## 5. Quick Start & Running Tests

### Run with Docker Compose (PostgreSQL + Redis + Go API)

```bash
cd go_apps/backend
cp .env.example .env
docker compose up -d --build
docker logs -f go-api
```

### Run Automated Tests

```bash
cd go_apps/backend

# Run end-to-end & security unit tests (in-memory + file store)
go test -v ./...

# Run full integration suite against live PostgreSQL and Redis containers
TEST_DATABASE_URL="postgres://goapp:goapp_secret@localhost:5433/go_delivery?sslmode=disable" \
TEST_REDIS_URL="redis://:goapp_redis_secret@localhost:6379/0" \
go test -v ./...
```

---

## 6. Complete API Endpoint Reference

### 6.1 Common Headers, Envelopes & Pagination

#### Request Headers
| Header | Required | Values / Description |
| --- | --- | --- |
| `Authorization` | On all `[Authed]` routes | `Bearer <access_token>` (15-minute JWT). |
| `Content-Type` | On `POST`/`PUT`/`PATCH` | `application/json` (or `image/jpeg` on `PUT /upload/{key}`). |
| `X-App` | Recommended | `customer` \| `rider` \| `merchant`. Determines `Job.allowed_actions` and chat sender role. |
| `X-App-Version` | Optional | Client version string, e.g. `1.0.0`. |
| `Accept-Language` | Optional | `en` \| `fil`. |
| `Idempotency-Key` | Optional (`POST /jobs`, `POST /rider/wallet/topups`) | Unique string/UUID v4. Repeated requests with the same key return the original result without duplicating bookings or top-ups. |

#### Response Envelopes
- **Success (`200 OK`)**:
  ```json
  {
    "data": { ... },
    "meta": {}
  }
  ```
- **Paginated List (`200 OK`)**:
  ```json
  {
    "data": [ ... ],
    "meta": {
      "next_cursor": "20"
    }
  }
  ```
  Pass `?cursor=<next_cursor>&limit=<1..100>` to fetch the next page (`next_cursor` is `null` on the final page).
- **Error (`4xx` / `5xx`)**:
  ```json
  {
    "error": {
      "code": "validation_failed",
      "message": "Invalid PH mobile number",
      "fields": { "phone": "invalid" }
    }
  }
  ```

---

### 6.2 System & Health Endpoints

#### 1. `GET /healthz`
- **Auth**: Public
- **Function**: Liveness and readiness probe. Pings PostgreSQL (if configured) and Redis (if configured).
- **Parameters**: None.
- **Responses**:
  - `200 OK`: `ok` (plain text)
  - `503 Service Unavailable`: `db_unhealthy` or `redis_unhealthy`
- **How to use**:
  ```bash
  curl -i http://localhost:8080/healthz
  ```

#### 2. `GET /`
- **Auth**: Public
- **Function**: Renders an HTML status dashboard showing total registered users, total/live jobs, online riders, active WebSocket connections, and the API base URL.
- **Parameters**: None.
- **How to use**: Open `http://localhost:8080/` in a browser.

---

### 6.3 Authentication & User Profile Endpoints

#### 3. `POST /api/v1/auth/otp/request`
- **Auth**: Public (Rate-limited: max 5 per 10 min per phone; `AUTH_RATE_LIMIT_PER_MIN` per IP)
- **Function**: Generates a 6-digit OTP for a Philippine mobile number (`+639XXXXXXXXX`), stores its HMAC-SHA256 hash in Redis/state with a 5-minute TTL, and logs the code in dev mode.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `phone` | `string` | Yes | E.164 Philippine mobile number matching `^\+639\d{9}$` (e.g. `"+639171234567"`). |
- **Response (`200 OK`)**:
  ```json
  { "data": { "expires_in_seconds": 300, "resend_after_seconds": 60 }, "meta": {} }
  ```
- **How to use**:
  ```bash
  curl -X POST http://localhost:8080/api/v1/auth/otp/request \
    -H "Content-Type: application/json" \
    -d '{"phone":"+639171234567"}'
  ```

#### 4. `POST /api/v1/auth/otp/verify`
- **Auth**: Public (Locked out with `429 rate_limited` after 5 wrong attempts)
- **Function**: Verifies the 6-digit OTP code (or `DEV_OTP_CODE` if enabled), creates the user account if new, assigns app-appropriate roles (`customer`, `rider`, or `merchant` if phone is in `merchant_staff`), and issues an `access_token` (15m JWT) and `refresh_token` (30d opaque token).
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `phone` | `string` | Yes | E.164 phone number (`^\+639\d{9}$`). |
  | `code` | `string` | Yes | 6-digit OTP code. |
  | `app` | `string` | Yes | Target app: `"customer"`, `"rider"`, or `"merchant"`. |
- **Response (`200 OK`)**:
  ```json
  {
    "data": {
      "access_token": "eyJhbGciOiJIUzI1NiIs...",
      "refresh_token": "8f4a2e...",
      "user": {
        "id": "uuid",
        "phone": "+639171234567",
        "name": "",
        "language": "en",
        "roles": ["customer"],
        "created_at": "2026-11-16T03:00:00Z"
      },
      "is_new_user": true
    },
    "meta": {}
  }
  ```
- **How to use**:
  ```bash
  curl -X POST http://localhost:8080/api/v1/auth/otp/verify \
    -H "Content-Type: application/json" \
    -d '{"phone":"+639171234567","code":"123456","app":"customer"}'
  ```

#### 5. `POST /api/v1/auth/refresh`
- **Auth**: Public
- **Function**: Exchanges a valid `refresh_token` for a new `access_token` and a new rotated `refresh_token`. The old refresh token is immediately invalidated.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `refresh_token` | `string` | Yes | The refresh token received from `/auth/otp/verify` or a prior `/auth/refresh`. |
- **Response (`200 OK`)**:
  ```json
  { "data": { "access_token": "...", "refresh_token": "..." }, "meta": {} }
  ```

#### 6. `POST /api/v1/auth/logout`
- **Auth**: Public / Bearer optional
- **Function**: Revokes the provided `refresh_token` in Redis/PostgreSQL/memory AND blacklists the caller's `Authorization: Bearer <access_token>` (if supplied) so neither token can be used again.
- **Headers**: `Authorization: Bearer <access_token>` (optional, recommended to immediately revoke the access token).
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `refresh_token` | `string` | No | Refresh token to revoke. |
- **Response (`200 OK`)**: `{ "data": {}, "meta": {} }`

#### 7. `GET /api/v1/me`
- **Auth**: `Bearer <access_token>`
- **Function**: Returns the authenticated user's profile (`User`).
- **Parameters**: None.
- **Response (`200 OK`)**: `{ "data": { "id": "...", "phone": "+639...", "name": "Aisha Tan", "email": "...", "language": "en", "roles": ["customer"], "created_at": "..." }, "meta": {} }`

#### 8. `PATCH /api/v1/me`
- **Auth**: `Bearer <access_token>`
- **Function**: Updates the authenticated user's display name, email address, or preferred language (`en` or `fil`).
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `name` | `string` | No | Full name (minimum 2 non-whitespace characters). |
  | `email` | `string` | No | Email address. |
  | `language` | `string` | No | `"en"` or `"fil"`. |
- **Response (`200 OK`)**: Updated `User` object.

#### 9. `DELETE /api/v1/me`
- **Auth**: `Bearer <access_token>`
- **Function**: Deletes the authenticated user's account, saved places, rider profile, and all active sessions, and revokes the current access token. Fails with `409 validation_failed` if the user has a live (in-progress) job.
- **Parameters**: None.
- **Response (`200 OK`)**: `{ "data": {}, "meta": {} }`

#### 10. `POST /api/v1/me/devices`
- **Auth**: `Bearer <access_token>`
- **Function**: Registers or updates an FCM push notification token for the authenticated user's device.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `fcm_token` | `string` | Yes | Non-empty Firebase Cloud Messaging registration token. |
  | `platform` | `string` | Yes | E.g. `"android"` or `"ios"`. |
  | `app` | `string` | Yes | `"customer"`, `"rider"`, or `"merchant"`. |
- **Response (`200 OK`)**: `{ "data": {}, "meta": {} }`

---

### 6.4 Saved Places & Geolocation Endpoints

#### 11. `GET /api/v1/me/places`
- **Auth**: `Bearer <access_token>`
- **Function**: Lists all saved addresses (`SavedPlace`) belonging to the authenticated user, sorted alphabetically by `label`.
- **Parameters**: None.
- **Response (`200 OK`)**: `{ "data": [ { "id": "uuid", "label": "Home", "address": "Lamion, Bongao", "location": { "lat": 5.0251, "lng": 119.7769 } } ], "meta": {} }`

#### 12. `POST /api/v1/me/places`
- **Auth**: `Bearer <access_token>`
- **Function**: Saves a new favorite place for the authenticated user.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `label` | `string` | Yes | Non-empty label (e.g. `"Home"`, `"Work"`). |
  | `address` | `string` | Yes | Human-readable street/area address. |
  | `location` | `LatLng` | Yes | `{ "lat": float64, "lng": float64 }`. |
- **Response (`200 OK`)**: Created `SavedPlace` object.

#### 13. `DELETE /api/v1/me/places/{id}`
- **Auth**: `Bearer <access_token>`
- **Function**: Deletes a saved place owned by the authenticated user.
- **Path Parameters**:
  - `id` (`string`, required): SavedPlace UUID.
- **Response (`200 OK`)**: `{ "data": {}, "meta": {} }` (`404 not_found` if not owned by user).

#### 14. `GET /api/v1/geo/reverse`
- **Auth**: `Bearer <access_token>`
- **Function**: Reverse-geocodes coordinates into the nearest known Bongao landmark or merchant address.
- **Query Parameters**:
  | Parameter | Type | Required | Description |
  | --- | --- | --- | --- |
  | `lat` | `float64` | Yes | Latitude (`-90` to `90`). |
  | `lng` | `float64` | Yes | Longitude (`-180` to `180`). |
- **Response (`200 OK`)**: `{ "data": { "address": "Near MSU Tawi-Tawi, Bongao" }, "meta": {} }`
- **How to use**:
  ```bash
  curl "http://localhost:8080/api/v1/geo/reverse?lat=5.0294&lng=119.7730" \
    -H "Authorization: Bearer $TOKEN"
  ```

#### 15. `GET /api/v1/geo/search`
- **Auth**: `Bearer <access_token>`
- **Function**: Searches Bongao landmarks and merchants by name/address, ordered by distance from `(lat, lng)` (returns up to 10 results).
- **Query Parameters**:
  | Parameter | Type | Required | Description |
  | --- | --- | --- | --- |
  | `lat` | `float64` | Yes | Reference latitude for proximity sorting. |
  | `lng` | `float64` | Yes | Reference longitude for proximity sorting. |
  | `q` | `string` | No | Case-insensitive search query (empty returns nearest places). |
- **Response (`200 OK`)**: `{ "data": [ { "name": "Bongao Public Market", "address": "Datu Halun St, Bongao", "location": { "lat": 5.0294, "lng": 119.7730 } } ], "meta": {} }`

#### 16. `GET /api/v1/service-area`
- **Auth**: `Bearer <access_token>`
- **Function**: Returns the active service area polygons (`zones`) where pickups and drop-offs are permitted.
- **Parameters**: None.
- **Response (`200 OK`)**: `{ "data": { "zones": [ { "id": "bongao", "name": "Bongao", "polygon": [ { "lat": ..., "lng": ... } ] } ] }, "meta": {} }`

---

### 6.5 Merchants — Public Customer View

#### 17. `GET /api/v1/merchants`
- **Auth**: `Bearer <access_token>`
- **Function**: Lists merchants with computed `distance_m` from the caller's coordinates. Open/accepting merchants appear first, sorted by nearest distance. Supports searching by merchant name or menu item name via `q`. Does not include `menu` in list items.
- **Query Parameters**:
  | Parameter | Type | Required | Description |
  | --- | --- | --- | --- |
  | `lat` | `float64` | Yes | Customer latitude (`-90` to `90`). |
  | `lng` | `float64` | Yes | Customer longitude (`-180` to `180`). |
  | `q` | `string` | No | Filter by merchant name or menu item name. |
  | `cursor` | `int` | No | Pagination offset cursor (default `0`). |
  | `limit` | `int` | No | Page size (`1..100`, default `20`). |
- **Response (`200 OK`)**: Paginated list of `Merchant` objects.

#### 18. `GET /api/v1/merchants/{id}`
- **Auth**: `Bearer <access_token>`
- **Function**: Returns a single merchant's details along with its complete `menu` (`[MenuCategory]` with items and `addon_groups`). Cached in Redis (`goapp:cache:merchant:<id>`) for 5 minutes and automatically invalidated on store/menu updates.
- **Path Parameters**:
  - `id` (`string`, required): Merchant UUID.
- **Response (`200 OK`)**: Full `Merchant` object including `menu`.

---

### 6.6 Quotes & Jobs (Bookings)

#### 19. `POST /api/v1/quotes`
- **Auth**: `Bearer <access_token>`
- **Function**: Validates service area, merchant availability, item prices/add-ons, or Pabili/Padala constraints, and calculates a fare breakdown and total in centavos. Caches the resulting `Quote` (valid for 5 minutes) in Redis (`goapp:quote:<id>`) and memory.
- **Body Parameters** (`application/json` — `QuoteRequest`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `service` | `string` | Yes | `"ride"`, `"food"`, `"pabili"`, or `"padala"`. |
  | `pickup` | `Stop` | Yes | `{ "address": string, "location": { "lat": float64, "lng": float64 }, "contact_name"?: string, "contact_phone"?: string, "notes"?: string }`. (For `"food"`, overwritten with the merchant's store location). |
  | `dropoff` | `Stop` | Yes | Customer destination `Stop`. |
  | `food` | `object` | Required if `service="food"` | `{ "merchant_id": string, "items": [ { "item_id": string, "quantity": 1..50, "addon_option_ids": [string], "note"?: string } ] }`. |
  | `pabili` | `object` | Required if `service="pabili"` | `{ "store_name": string, "items": [ { "name": string, "quantity": int, "note"?: string } ], "estimated_item_total_centavos": int (≤300000) }`. |
  | `padala` | `object` | Required if `service="padala"` | `{ "size": "small"\|"medium"\|"large", "description": string, "recipient_name": string, "recipient_phone": "+639XXXXXXXXX", "photo_key"?: string }`. |
- **Response (`200 OK`)**:
  ```json
  {
    "data": {
      "id": "quote-uuid",
      "service": "ride",
      "distance_m": 1612,
      "duration_s": 263,
      "expires_at": "2026-11-16T03:20:00Z",
      "breakdown": [
        { "label": "Base fare", "amount_centavos": 4000 },
        { "label": "Distance 1.6 km", "amount_centavos": 1500 }
      ],
      "total_centavos": 5500
    },
    "meta": {}
  }
  ```

#### 20. `POST /api/v1/jobs`
- **Auth**: `Bearer <access_token>`
- **Function**: Books a job from a valid, unconsumed `quote_id`. Supports idempotent retries via the `Idempotency-Key` header (persisted in Redis + PostgreSQL).
  - If `payment_method` is `"cash"`: Food jobs transition to `merchant_pending` (and notify merchant via WebSocket `order.new`); Ride/Pabili/Padala jobs transition to `searching` and dispatch to the nearest online rider.
  - If `payment_method` is `"gcash"` or `"maya"`: Job starts in `pending_payment` and returns `payment.checkout_url`.
- **Headers**:
  - `Idempotency-Key` (`string`, optional): Client idempotency token.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `quote_id` | `string` | Yes | UUID of an unexpired quote created by the same user. |
  | `payment_method` | `string` | Yes | `"cash"`, `"gcash"`, or `"maya"`. |
  | `notes` | `string` | No | Delivery instructions (stored on `dropoff.notes`). |
- **Response (`200 OK`)**: Created `Job` object formatted for `"customer"`.

#### 21. `GET /api/v1/jobs`
- **Auth**: `Bearer <access_token>`
- **Function**: Lists the authenticated customer's jobs (newest first), filtered by active or past status.
- **Query Parameters**:
  | Parameter | Type | Required | Description |
  | --- | --- | --- | --- |
  | `status` | `string` | No | `"active"` (default, live bookings) or `"past"` (`completed` and `cancelled`). |
  | `cursor` | `int` | No | Pagination offset. |
  | `limit` | `int` | No | Page size (`1..100`, default `20`). |
- **Response (`200 OK`)**: Paginated list of `Job` objects.

#### 22. `GET /api/v1/jobs/{id}`
- **Auth**: `Bearer <access_token>`
- **Function**: Returns the current state of a job for the customer or assigned rider, with `allowed_actions` tailored to the caller's app (`X-App` / JWT `app` claim).
- **Path Parameters**:
  - `id` (`string`, required): Job UUID.
- **Response (`200 OK`)**: `Job` object (`404 not_found` if caller is neither customer nor assigned rider).

#### 23. `POST /api/v1/jobs/{id}/cancel`
- **Auth**: `Bearer <access_token>`
- **Function**: Cancels an active booking if `"cancel"` is currently in the customer's `allowed_actions` (`pending_payment` through `rider_assigned`). Refunds online-paid jobs (`payment.status = "refunded"`) and expires any pending rider offers.
- **Path Parameters**:
  - `id` (`string`, required): Job UUID.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `reason` | `string` | No | Cancellation reason (defaults to `"Cancelled by customer"`). |
- **Response (`200 OK`)**: Updated `Job` object (`409 job_not_cancellable` if past the cancellable stage).

#### 24. `POST /api/v1/jobs/{id}/confirm-items`
- **Auth**: `Bearer <access_token>`
- **Function**: Used by the customer on a **Pabili** job in `items_purchased` status after the rider uploads the store receipt photo and item total.
  - `approved: true` transitions the job to `picked_up` so the rider can deliver.
  - `approved: false` cancels the job as a disputed item total.
- **Path Parameters**:
  - `id` (`string`, required): Job UUID.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `approved` | `bool` | Yes | `true` to approve receipt total, `false` to dispute/cancel. |
- **Response (`200 OK`)**: Updated `Job` object.

#### 25. `POST /api/v1/jobs/{id}/rate`
- **Auth**: `Bearer <access_token>`
- **Function**: Submits a 1–5 star rating for the rider (and optionally the merchant on food jobs) once the job is `completed`. Removes `"rate"` from `allowed_actions` and updates average ratings (and invalidates the merchant's Redis cache).
- **Path Parameters**:
  - `id` (`string`, required): Job UUID.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `rider_rating` | `int` | Yes | Rating from `1` to `5`. |
  | `rider_tags` | `[string]` | No | Feedback tags, e.g. `["friendly", "safe_driver"]`. |
  | `comment` | `string` | No | Free-text review comment. |
  | `merchant_rating` | `int` | No | Merchant rating from `1` to `5` (for food orders). |
- **Response (`200 OK`)**: `{ "data": {}, "meta": {} }`

#### 26. `POST /api/v1/jobs/{id}/share`
- **Auth**: `Bearer <access_token>`
- **Function**: Generates a public live-tracking URL (`/t/{token}`) for the job that refreshes every 10 seconds in any browser.
- **Path Parameters**:
  - `id` (`string`, required): Job UUID.
- **Response (`200 OK`)**: `{ "data": { "url": "http://.../t/abc123...", "expires_at": "2026-11-16T09:30:00Z" }, "meta": {} }`

#### 27. `POST /api/v1/jobs/{id}/sos`
- **Auth**: `Bearer <access_token>`
- **Function**: Records an emergency SOS alert with the caller's coordinates and logs an urgent alert for dispatchers.
- **Path Parameters**:
  - `id` (`string`, required): Job UUID.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `location` | `LatLng` | No | `{ "lat": float64, "lng": float64 }`. |
- **Response (`200 OK`)**: `{ "data": {}, "meta": {} }`

#### 28. `POST /api/v1/jobs/{id}/call`
- **Auth**: `Bearer <access_token>`
- **Function**: Returns the dialable/masked phone number for the other party on the job (customer <-> rider) so phone numbers do not have to be exposed in job views.
- **Path Parameters**:
  - `id` (`string`, required): Job UUID.
- **Response (`200 OK`)**: `{ "data": { "masked_number": "+639181112222" }, "meta": {} }`

---

### 6.7 Job Chat Endpoints

#### 29. `GET /api/v1/jobs/{id}/messages`
- **Auth**: `Bearer <access_token>`
- **Function**: Lists chat messages (`ChatMessage`) between customer, rider, and system for the specified job (oldest first).
- **Path Parameters**:
  - `id` (`string`, required): Job UUID.
- **Query Parameters**:
  - `cursor` (`int`, optional): Pagination offset.
  - `limit` (`int`, optional): Page size (`1..100`, default `50`).
- **Response (`200 OK`)**: Paginated list of `ChatMessage` objects.

#### 30. `POST /api/v1/jobs/{id}/messages`
- **Auth**: `Bearer <access_token>`
- **Function**: Sends a text and/or image chat message on a live job and pushes a `chat.message` WebSocket event to the other party.
- **Path Parameters**:
  - `id` (`string`, required): Job UUID.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `text` | `string` | Conditional | Message text (required if `image_key` is omitted). |
  | `image_key` | `string` | Conditional | Uploaded image key from `POST /api/v1/uploads` with purpose `"chat_image"`. |
- **Response (`200 OK`)**: Created `ChatMessage` object.

---

### 6.8 File Uploads & Static File Serving

#### 31. `POST /api/v1/uploads`
- **Auth**: `Bearer <access_token>`
- **Function**: Creates a pre-signed HMAC-SHA256 `PUT` URL valid for 15 minutes to upload a JPEG image.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `purpose` | `string` | Yes | One of: `"rider_license"`, `"rider_orcr"`, `"rider_selfie"`, `"rider_clearance"`, `"receipt"`, `"proof_of_delivery"`, `"parcel_photo"`, `"chat_image"`, `"menu_item_photo"`, `"merchant_logo"`, `"merchant_cover"`. |
  | `content_type` | `string` | Yes | Must be `"image/jpeg"`. |
- **Response (`200 OK`)**:
  ```json
  {
    "data": {
      "upload_url": "http://localhost:8080/upload/u/receipt/uuid.jpg?exp=1763265000&sig=...",
      "key": "u/receipt/uuid.jpg",
      "expires_at": "2026-11-16T03:30:00Z"
    },
    "meta": {}
  }
  ```

#### 32. `PUT /upload/{key...}`
- **Auth**: Pre-signed query parameters (`exp` and `sig`) — **no `Authorization` header required**.
- **Function**: Receives raw JPEG bytes (max 10 MB, must begin with JPEG SOI marker `\xff\xd8`) and writes them to `<DATA_DIR>/uploads/<key>`.
- **Query Parameters**:
  - `exp` (`int64`, required): Unix expiration timestamp.
  - `sig` (`string`, required): Hex HMAC-SHA256 signature of `<key>|<exp>`.
- **Responses**: `200 OK`, `403 Forbidden` (expired/invalid sig), `413 Request Entity Too Large` (>10 MB), `415 Unsupported Media Type` (not a valid JPEG).
- **How to use**:
  ```bash
  curl -X PUT "$UPLOAD_URL" -H "Content-Type: image/jpeg" --data-binary @photo.jpg
  ```

#### 33. `GET /files/{key...}`
- **Auth**: Public
- **Function**: Serves an uploaded JPEG file with `Content-Type: image/jpeg`, `X-Content-Type-Options: nosniff`, `Content-Security-Policy: default-src 'none'`, and 24-hour cache headers.
- **Path Parameters**:
  - `key` (`string`, required): File key matching `^u/[a-z_]+/[0-9a-f-]{36}\.jpg$`.

---

### 6.9 Rider Endpoints

#### 34. `GET /api/v1/rider/me`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Returns the rider's `RiderProfile` (KYC status, online state, vehicle details, rating, and wallet balance).
- **Parameters**: None.
- **Response (`200 OK`)**: `RiderProfile` object.

#### 35. `PUT /api/v1/rider/me`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Submits rider vehicle details and uploaded KYC document keys for review, transitioning profile status to `"pending_review"`.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `vehicle` | `object` | Yes | `{ "plate": string, "make_model": string, "color": string }`. |
  | `documents` | `object` | Yes | `{ "license_key": string, "orcr_key": string, "selfie_key": string, "clearance_key": string }` (all keys must have been created via `POST /uploads`). |
- **Response (`200 OK`)**: Updated `RiderProfile`.

#### 36. `POST /api/v1/rider/status`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Toggles the rider online or offline. Going online requires `status == "approved"` (`403 rider_not_approved` otherwise) and `balance_centavos >= min_balance_centavos` (`402 insufficient_balance` otherwise). Updates or removes the rider's position in the Redis geospatial index (`goapp:riders:geo`).
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `online` | `bool` | Yes | `true` to go online and receive offers, `false` to go offline. |
  | `location` | `LatLng` | No | `{ "lat": float64, "lng": float64 }`. |
- **Response (`200 OK`)**: Updated `RiderProfile`.

#### 37. `POST /api/v1/rider/location`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: HTTP fallback for updating the rider's live GPS location and heading (updates Redis `goapp:riders:geo` and `goapp:rider:loc:<uid>`, and emits `rider.location` over WebSocket to the active job's customer).
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `location` | `LatLng` | Yes | `{ "lat": float64, "lng": float64 }` (`lat` in `-90..90`, `lng` in `-180..180`). |
  | `heading` | `float64` | No | Compass heading in degrees (`0..360`). |
  | `speed_kph` | `float64` | No | Optional GPS speed in km/h. |
  | `recorded_at` | `string` | No | Optional ISO-8601 client timestamp. |
- **Response (`200 OK`)**: `{ "data": {}, "meta": {} }`

#### 38. `GET /api/v1/rider/offers/current`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Returns the unexpired `JobOffer` currently offered to the rider (from memory or Redis `goapp:rider:offer:<uid>`), or `null` if none.
- **Parameters**: None.
- **Response (`200 OK`)**: `JobOffer` object or `null`.

#### 39. `POST /api/v1/rider/offers/{id}/accept`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Accepts an active dispatch offer before its 15-second countdown expires, assigns the rider to the job (`status = "rider_assigned"`), deletes the offer from Redis/memory, and notifies the customer and merchant.
- **Path Parameters**:
  - `id` (`string`, required): Offer UUID.
- **Response (`200 OK`)**: `Job` object formatted for `"rider"` (`409 offer_expired` if expired or already taken).

#### 40. `POST /api/v1/rider/offers/{id}/decline`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Declines an active offer, removes it from Redis/memory, records the rider in `declined_by`, and immediately dispatches the job to the next nearest available rider.
- **Path Parameters**:
  - `id` (`string`, required): Offer UUID.
- **Body Parameters** (`application/json`):
  - `reason` (`string`, optional): E.g. `"busy"` or `"timeout"`.
- **Response (`200 OK`)**: `{ "data": {}, "meta": {} }`

#### 41. `GET /api/v1/rider/jobs/active`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Returns the rider's currently active (in-progress) `Job`, or `null` if idle.
- **Parameters**: None.

#### 42. `GET /api/v1/rider/jobs`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Lists jobs assigned to the rider (newest first), optionally filtered by Asia/Manila calendar dates.
- **Query Parameters**:
  | Parameter | Type | Required | Description |
  | --- | --- | --- | --- |
  | `from` | `string` | No | Start date `YYYY-MM-DD` (Asia/Manila). |
  | `to` | `string` | No | End date `YYYY-MM-DD` (Asia/Manila). |
  | `cursor` | `int` | No | Pagination offset. |
  | `limit` | `int` | No | Page size (`1..100`, default `20`). |
- **Response (`200 OK`)**: Paginated list of `Job` objects.

#### 43. `POST /api/v1/rider/jobs/{id}/status`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Advances an assigned job to the next valid step in the state machine (`arrived_pickup` → `items_purchased` / `picked_up` → `arrived_dropoff` → `completed`). On `completed`, settles rider earnings/commissions in the rider's wallet.
- **Path Parameters**:
  - `id` (`string`, required): Job UUID.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `status` | `string` | Yes | Next status: `"arrived_pickup"`, `"items_purchased"`, `"picked_up"`, `"arrived_dropoff"`, or `"completed"`. |
  | `location` | `LatLng` | No | Rider's current coordinates. |
  | `receipt_key` | `string` | Required for `"items_purchased"` | Uploaded receipt photo key (Pabili). |
  | `item_total_centavos` | `int` | Required for `"items_purchased"` | Actual store receipt amount in centavos (`> 0`). |
  | `proof_key` | `string` | Required for `"completed"` (except `ride`) | Uploaded proof-of-delivery photo key. |
- **Response (`200 OK`)**: Updated `Job` object.

#### 44. `GET /api/v1/rider/earnings`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Aggregates completed job count and total rider earnings (in centavos) per day over an Asia/Manila date range.
- **Query Parameters**:
  | Parameter | Type | Required | Description |
  | --- | --- | --- | --- |
  | `from` | `string` | Yes | Start date `YYYY-MM-DD` (`from <= to`). |
  | `to` | `string` | Yes | End date `YYYY-MM-DD`. |
- **Response (`200 OK`)**: `{ "data": { "total_centavos": 18000, "jobs_count": 3, "days": [ { "date": "2026-11-16", "total_centavos": 18000, "jobs_count": 3 } ] }, "meta": {} }`

#### 45. `GET /api/v1/rider/wallet`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Returns the rider's current wallet balance and minimum required balance to go online.
- **Parameters**: None.
- **Response (`200 OK`)**: `{ "data": { "balance_centavos": 20000, "min_balance_centavos": 10000 }, "meta": {} }`

#### 46. `GET /api/v1/rider/wallet/transactions`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Lists wallet ledger entries (`topup`, `commission`, `earning`, `adjustment`, `payout`) for the rider, newest first.
- **Query Parameters**: `cursor` (`int`, optional), `limit` (`int`, optional, default `20`).
- **Response (`200 OK`)**: Paginated list of `WalletTransaction` objects.

#### 47. `POST /api/v1/rider/wallet/topups`
- **Auth**: `Bearer <access_token>` (`app="rider"`)
- **Function**: Initiates a rider wallet top-up between ₱100 (`10000` centavos) and ₱20,000 (`2000000` centavos) via GCash or Maya, returning a checkout URL. Supports `Idempotency-Key` in Redis and PostgreSQL.
- **Headers**: `Idempotency-Key` (`string`, optional).
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `amount_centavos` | `int` | Yes | Amount in centavos (`10000` to `2000000`). |
  | `method` | `string` | Yes | `"gcash"` or `"maya"`. |
- **Response (`200 OK`)**: `{ "data": { "topup_id": "uuid", "checkout_url": "http://.../pay/topup/uuid" }, "meta": {} }`

---

### 6.10 Merchant Portal Endpoints

All `/api/v1/merchant/*` endpoints require a `Bearer <access_token>` belonging to a user whose phone number is registered in `merchant_staff` (`403 forbidden` otherwise).

#### 48. `GET /api/v1/merchant/me`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Returns the merchant account (`merchant` profile, staff `role`, and `staff_name`).
- **Parameters**: None.

#### 49. `PATCH /api/v1/merchant/store`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Updates store settings (open/closed state, temporary pause timestamp, prep time, minimum order, weekly operating hours, logo/cover photos, or name). Invalidates the Redis merchant cache and broadcasts `merchant.updated`.
- **Body Parameters** (`application/json`, all optional):
  | Field | Type | Description |
  | --- | --- | --- |
  | `is_open` | `bool` | Whether the store is accepting orders. |
  | `paused_until` | `string` or `null` | ISO-8601 UTC timestamp to pause orders until, or explicit `null` to resume immediately. |
  | `prep_time_minutes` | `int` | Default preparation time (`5` to `60` minutes). |
  | `min_order_centavos` | `int` | Minimum basket subtotal in centavos (`>= 0`). |
  | `hours` | `[OpeningHours]` | Replaces weekly schedule: `[ { "weekday": 0..6, "opens": "HH:mm", "closes": "HH:mm" } ]`. |
  | `logo_key` | `string` | Uploaded logo key. |
  | `cover_key` | `string` | Uploaded cover image key. |
  | `name` | `string` | Store name. |
- **Response (`200 OK`)**: Updated `Merchant` object.

#### 50. `GET /api/v1/merchant/orders`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Lists food orders for the merchant's store (newest first), filtered by board column status and/or Asia/Manila date range.
- **Query Parameters**:
  | Parameter | Type | Required | Description |
  | --- | --- | --- | --- |
  | `status` | `string` | No | `"new"`, `"preparing"`, `"ready"`, or `"done"` (includes `picked_up`, `completed`, `rejected`, `cancelled`). Empty returns all. |
  | `from` | `string` | No | Filter `created_at` from `YYYY-MM-DD` (Asia/Manila). |
  | `to` | `string` | No | Filter `created_at` to `YYYY-MM-DD` (Asia/Manila). |
  | `cursor` | `int` | No | Pagination offset. |
  | `limit` | `int` | No | Page size (`1..100`, default `50`). |
- **Response (`200 OK`)**: Paginated list of `MerchantOrder` objects.

#### 51. `GET /api/v1/merchant/orders/{id}`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Fetches a single `MerchantOrder` by its order ID.
- **Path Parameters**: `id` (`string`, required): MerchantOrder UUID.

#### 52. `POST /api/v1/merchant/orders/{id}/accept`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Accepts a `"new"` food order (`job.status == "merchant_pending"`), sets the preparation time (`5..60` min), transitions the job to `"searching"`, and immediately starts rider dispatch.
- **Path Parameters**: `id` (`string`, required): MerchantOrder UUID.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `prep_time_minutes` | `int` | Yes | Preparation time between `5` and `60` minutes. |
- **Response (`200 OK`)**: Updated `MerchantOrder` (`409 order_already_handled` if already accepted/rejected).

#### 53. `POST /api/v1/merchant/orders/{id}/reject`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Rejects a `"new"` food order, cancels the customer's job (refunding online payment if applicable), and notifies the customer.
- **Path Parameters**: `id` (`string`, required): MerchantOrder UUID.
- **Body Parameters** (`application/json`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `reason` | `string` | Yes | `"out_of_stock"`, `"too_busy"`, `"closing_soon"`, or `"other"`. |
  | `note` | `string` | No | Additional explanation appended to the customer cancellation message. |
- **Response (`200 OK`)**: Updated `MerchantOrder`.

#### 54. `POST /api/v1/merchant/orders/{id}/ready`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Marks a `"preparing"` order as `"ready"` for pickup (`food.is_ready = true`, `food.ready_at = now`), unlocking the `"picked_up"` action for the assigned rider at the store.
- **Path Parameters**: `id` (`string`, required): MerchantOrder UUID.
- **Response (`200 OK`)**: Updated `MerchantOrder`.

#### 55. `GET /api/v1/merchant/menu`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Returns the store's full menu (`[MenuCategory]` sorted by `sort_order`, including unavailable items and add-on options).

#### 56. `POST /api/v1/merchant/menu/categories`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Creates a new menu category at the end of the menu and invalidates the Redis merchant cache.
- **Body Parameters**: `{ "name": string (required) }`.
- **Response (`200 OK`)**: Created `MenuCategory`.

#### 57. `PATCH /api/v1/merchant/menu/categories/{id}`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Renames an existing menu category.
- **Path Parameters**: `id` (`string`, required): Category UUID.
- **Body Parameters**: `{ "name": string }`.
- **Response (`200 OK`)**: Updated `MenuCategory`.

#### 58. `DELETE /api/v1/merchant/menu/categories/{id}`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Deletes an empty menu category (`422 validation_failed` if the category still contains items).
- **Path Parameters**: `id` (`string`, required): Category UUID.

#### 59. `PUT /api/v1/merchant/menu/categories/order`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Reorders the store's menu categories according to the provided list of category IDs.
- **Body Parameters**: `{ "category_ids": [string] }`.

#### 60. `POST /api/v1/merchant/menu/items`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Creates a new menu item (including nested `addon_groups` and `options`) inside a category and invalidates the Redis merchant cache.
- **Body Parameters** (`application/json` — `MenuItemInput`):
  | Field | Type | Required | Description |
  | --- | --- | --- | --- |
  | `category_id` | `string` | Yes | Target `MenuCategory` UUID. |
  | `name` | `string` | Yes | Item name. |
  | `description` | `string` | No | Item description. |
  | `photo_key` | `string` | No | Uploaded photo key (`menu_item_photo`). |
  | `price_centavos` | `int` | Yes | Base price in centavos (`>= 0`). |
  | `is_available` | `bool` | Yes | Initial availability state. |
  | `addon_groups` | `[object]` | No | `[ { "id"?: string, "name": string, "min_select": int, "max_select": int, "options": [ { "id"?: string, "name": string, "price_centavos": int, "is_available": bool } ] } ]`. |
- **Response (`200 OK`)**: Created `MenuItem`.

#### 61. `PUT /api/v1/merchant/menu/items/{id}`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Updates an existing menu item (and moves it if `category_id` changed) and invalidates the Redis merchant cache.
- **Path Parameters**: `id` (`string`, required): MenuItem UUID.
- **Body Parameters**: Same `MenuItemInput` structure as `POST /api/v1/merchant/menu/items`.
- **Response (`200 OK`)**: Updated `MenuItem`.

#### 62. `DELETE /api/v1/merchant/menu/items/{id}`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Deletes a menu item and invalidates the Redis merchant cache.
- **Path Parameters**: `id` (`string`, required): MenuItem UUID.

#### 63. `PATCH /api/v1/merchant/menu/items/{id}/availability`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Quickly toggles a menu item's `is_available` status (in-stock / sold-out) and invalidates the Redis merchant cache.
- **Path Parameters**: `id` (`string`, required): MenuItem UUID.
- **Body Parameters**: `{ "is_available": bool }`.
- **Response (`200 OK`)**: Updated `MenuItem`.

#### 64. `PATCH /api/v1/merchant/menu/addon-options/{id}/availability`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Toggles an individual add-on option's `is_available` status and invalidates the Redis merchant cache.
- **Path Parameters**: `id` (`string`, required): AddonOption UUID.
- **Body Parameters**: `{ "is_available": bool }`.
- **Response (`200 OK`)**: `{ "data": {}, "meta": {} }`

#### 65. `GET /api/v1/merchant/reports/sales`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Returns daily and total sales metrics (`orders_count`, `gross_centavos`, `commission_centavos`, `net_centavos`) for completed/picked-up orders over an Asia/Manila date range.
- **Query Parameters**:
  - `from` (`string`, required): Start date `YYYY-MM-DD`.
  - `to` (`string`, required): End date `YYYY-MM-DD`.
- **Response (`200 OK`)**: `SalesReport` object.

#### 66. `GET /api/v1/merchant/payouts`
- **Auth**: `Bearer <access_token>` (`merchant`)
- **Function**: Lists the current week's pending online-order payout followed by historical merchant payouts.
- **Query Parameters**: `cursor` (`int`, optional), `limit` (`int`, optional, default `20`).
- **Response (`200 OK`)**: Paginated list of `Payout` objects.

---

### 6.11 Real-Time WebSocket API

#### 67. `GET /ws?token=<access_token>`
- **Auth**: Query parameter `token` (`<access_token>`). Rejects unauthenticated or revoked tokens with `401 Unauthorized`; closes with WebSocket code `4001` (`token_expired`) when the JWT expires.
- **Function**: Persistent bidirectional real-time channel for live job updates, rider location streaming, dispatch offers, merchant order alarms, and chat messages. Backed by Redis Pub/Sub (`goapp:ws:events`) across instances.
- **Frame Format**:
  ```json
  { "type": "<event_name>", "id": "<uuid>", "data": { ... } }
  ```
- **Client → Server Messages**:
  | `type` | `data` Payload | Sender App | Function |
  | --- | --- | --- | --- |
  | `ping` | `{}` | All | Heartbeat every ~25s; server responds with `pong`. |
  | `rider.location` | `{ "location": { "lat": float64, "lng": float64 }, "heading"?: float64, "speed_kph"?: float64, "recorded_at"?: string }` | Rider | Updates rider GPS position in Redis/state and forwards to active job's customer. |
  | `job.subscribe` / `job.unsubscribe` | `{ "job_id": string }` | Customer | No-op acknowledgement (personal jobs are subscribed automatically). |
- **Server → Client Events**:
  | `type` | `data` Payload | Target App |
  | --- | --- | --- |
  | `pong` | `{}` | All |
  | `job.updated` | `{ "job": Job }` | Customer, Rider |
  | `rider.location` | `{ "job_id": string, "location": LatLng, "heading"?: float64 }` | Customer |
  | `offer.new` | `{ "offer": JobOffer }` | Rider |
  | `offer.expired` | `{ "offer_id": string }` | Rider |
  | `rider.profile_updated` | `{ "profile": RiderProfile }` | Rider |
  | `chat.message` | `{ "message": ChatMessage }` | Customer, Rider |
  | `order.new` | `{ "order": MerchantOrder }` | Merchant |
  | `order.updated` | `{ "order": MerchantOrder }` | Merchant |
  | `merchant.updated` | `{ "merchant": Merchant }` | Merchant |

---

### 6.12 Checkout, Live Share & Admin Pages

#### 68. `GET /pay/{kind}/{id}` & `POST /pay/{kind}/{id}`
- **Auth**: Public (Unguessable UUID)
- **Function**: Development checkout page for online payments (`GCash` / `Maya`).
  - `GET /pay/{kind}/{id}` renders the checkout UI showing the amount in PHP.
  - `POST /pay/{kind}/{id}` with form field `result=paid` or `result=failed` confirms or fails the payment and emits real-time WebSocket updates (`job.updated`, `order.new`, or `rider.profile_updated`).
- **Path Parameters**:
  - `kind` (`string`, required): `"job"` or `"topup"`.
  - `id` (`string`, required): Job UUID or Topup UUID.

#### 69. `GET /t/{token}`
- **Auth**: Public (Share token from `POST /api/v1/jobs/{id}/share`)
- **Function**: Renders a live HTML trip-tracking page showing booking code, status, pickup/dropoff, rider vehicle info, and a Google Maps pin link. Auto-refreshes every 10 seconds.
- **Path Parameters**:
  - `token` (`string`, required): Share token.

#### 70. `GET /admin` & `POST /admin/riders/{id}/{action}`
- **Auth**: Admin token via `?token=<ADMIN_TOKEN>`, `X-Admin-Token: <ADMIN_TOKEN>`, or `Authorization: Bearer <ADMIN_TOKEN>` (verified in constant time and rate-limited).
- **Function**:
  - `GET /admin` renders the rider KYC review dashboard listing all riders, their status, vehicle plate, and links to uploaded KYC documents.
  - `POST /admin/riders/{id}/{action}` where `action` is `"approve"` or `"reject"` updates the rider's KYC status, emits `rider.profile_updated` over WebSocket, and redirects back to `/admin`.
- **Path Parameters** (`POST`):
  - `id` (`string`, required): Rider's `user_id`.
  - `action` (`string`, required): `"approve"` or `"reject"`.
