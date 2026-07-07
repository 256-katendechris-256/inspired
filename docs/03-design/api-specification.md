# API Specification — `inspired-api`

**Status:** ✅ Live · **Owner:** Backend · **Source of truth for:** HTTP contract between `inspired-api` and its clients (`inspired` Flutter app, `iams-dash` dashboards)
**Base URL (pilot):** `https://iag-api.duckdns.org` · **Last updated:** 2026-06-18
**Scope:** Sprint 0 endpoints (committed) + Phase 1 attendance (preview)

---

## 0. What an API specification is and why it comes after the ERD

An **API specification** is the contract for talking to the backend over HTTP:
every endpoint, what it accepts, what it returns, and how it fails. It is the
seam between the three apps — the Flutter app and the Next.js dashboards know
*nothing* about Django internals, only this contract.

**Why it comes right after the ERD:** an API is, in large part, the data model
*exposed over the network*. Entities become **resources** (URLs), relationships
become **nested routes or filters**, and the on-delete/permission rules from the
ERD and [RBAC matrix](./rbac-matrix.md) become **authorization checks** per
endpoint. You can't design `GET /sites/{id}/employees` until you've decided a
site *has* employees — which the ERD just settled.

**Why write it before the code:** with three repos building in parallel
(SPRINT_0 §2), the frontend teams need to code against *something* before the
backend exists. A written contract lets the dashboard mock `POST /auth/google`
and the Flutter app build its Dio client while the Django view is still being
written. The spec is what makes parallel work possible without daily "what does
this endpoint return?" interruptions.

**How an API spec is built (the method):**

1. **Identify resources** from the ERD nouns (employees, sites, devices…).
2. **Map operations to HTTP verbs** — GET (read), POST (create), PATCH (partial
   update), PUT (replace), DELETE (remove). Let the verb carry the intent so URLs
   stay nouns, not verbs (`POST /attendance` not `/createAttendance`).
3. **Define cross-cutting conventions once** — auth, errors, pagination, status
   codes — so every endpoint behaves predictably.
4. **Specify each endpoint**: path, auth required, request body, success
   response, error responses.
5. **Machine-encode it** as OpenAPI 3.1 (`openapi.yaml`) so it generates client
   stubs, mock servers, and interactive docs. This Markdown is the human-readable
   companion; the YAML is the executable truth (see §7).

---

## 1. Conventions (apply to every endpoint)

### 1.1 Versioning
All routes are prefixed `/api/v1`. The major version changes only on a
breaking change; additive changes (new fields, new endpoints) do not bump it.
The in-app update mechanism (SPRINT_0 §9) lets us retire old app versions, so
`v1` can evolve for a long time.

### 1.2 Authentication
- Scheme: **Bearer JWT** in the `Authorization` header:
  `Authorization: Bearer <access_token>`.
- Tokens are issued by `POST /api/v1/auth/google` (see §2). Access token lives
  **15 min**, refresh token **30 days** (SPRINT_0 §6).
- JWT claims: `{ employee_id, role, dept_code }`. Clients **must not** trust
  these for authorization — the server re-checks on every request — but may read
  them to shape the UI.
- Endpoints marked 🔓 are public (no token). All others require a valid access
  token; expired → `401` (refresh and retry); insufficient role → `403`.

### 1.3 Content type
`application/json` for all request and response bodies, UTF-8. Timestamps are
**ISO 8601 UTC** (`2026-06-18T09:30:00Z`).

### 1.4 Standard error envelope
Every 4xx/5xx returns the same shape, so clients write one error handler:

```json
{
  "error": {
    "code": "not_registered",
    "message": "Not registered. Contact HR.",
    "details": {}
  }
}
```

`code` is a stable machine string (switch on this); `message` is human-readable
(may change); `details` is optional per-field validation info.

### 1.5 Status codes used
| Code | Meaning in this API |
|---|---|
| 200 | OK — read or update succeeded |
| 201 | Created — new resource made |
| 204 | No Content — delete succeeded |
| 400 | Validation error (`details` lists fields) |
| 401 | Missing/expired access token — refresh and retry |
| 403 | Authenticated but not authorized (wrong role, or not registered) |
| 404 | Resource not found *(or hidden from this role — see RBAC matrix)* |
| 409 | Conflict (e.g. duplicate check-in) |
| 422 | Semantically invalid (e.g. check-in outside geofence, if rejected) |
| 429 | Rate limited |
| 500 | Server error |

### 1.6 Pagination (list endpoints)
Cursor/limit style:
`GET /api/v1/employees?limit=50&offset=0` →

```json
{ "count": 213, "next": "?limit=50&offset=50", "previous": null, "results": [ ... ] }
```

### 1.7 Filtering & ordering
Query params, documented per endpoint. Common ones: `?department=CONST`,
`?site=3`, `?is_active=true`, `?ordering=-created_at`.

---

## 2. Authentication & identity

### 🔓 POST /api/v1/auth/google
Exchange a Google ID token for our JWT pair. This is **the authorization gate**
(SPRINT_0 §6): Google proves identity; the `Employee` row proves authorization.

**Request**
```json
{ "id_token": "<google_id_token>", "platform": "android" }
```

**200 OK**
```json
{
  "access": "<jwt_15min>",
  "refresh": "<jwt_30day>",
  "employee": {
    "employee_id": "EMP001",
    "full_name": "Chris Katende",
    "email": "katendechris5@gmail.com",
    "role": "admin",
    "dept_code": "CONST",
    "home_site_id": 1
  }
}
```

**Errors**
- `403 not_registered` — Google identity valid but no active `Employee` row.
- `401 invalid_google_token` — token failed `verify_oauth2_token`.

### 🔓 POST /api/v1/auth/refresh
Trade a refresh token for a new access token (simplejwt).
**Request** `{ "refresh": "<jwt>" }` → **200** `{ "access": "<jwt_15min>" }`
Errors: `401 token_invalid` (expired/blacklisted refresh → force re-login).

### POST /api/v1/auth/logout
Blacklist the current refresh token. **204 No Content.**

### GET /api/v1/me
Return the authenticated employee's profile (shaped from the JWT subject).
**200** → same `employee` object as above. Used by clients on launch to confirm
the session is still valid and to render role-appropriate UI.

---

## 3. Devices (FCM registration)

### POST /api/v1/devices
Register/refresh this device's FCM token (SPRINT_0 §7). Idempotent on
`fcm_token` — re-registering updates `last_seen` and re-links to the caller.

**Request**
```json
{ "fcm_token": "<fcm>", "platform": "android" }
```
**201 Created** → `{ "id": 12, "platform": "android", "last_seen": "2026-06-18T09:30:00Z" }`

> **Privacy (SPRINT_0 §12a.2):** there is intentionally **no** `GET /devices`
> list endpoint and **no** admin device view. Tokens are write-only from the
> client's side and read only by the server's push-send code.

### DELETE /api/v1/devices/{id}
Unregister a device (e.g. on logout). **204 No Content.**

---

## 4. Organization — Sites & Departments

> Authorization per the [RBAC matrix](./rbac-matrix.md). Sites CRUD is
> **System Admin** only; reads are broader. In Sprint 0 these are managed in
> Django admin — the API routes below are the Phase 1 contract the dashboard
> Sites page will consume.

### GET /api/v1/departments
List departments. Any authenticated user. **200** → paginated `Department[]`.

### GET /api/v1/sites
List sites. Supports `?is_active=true&department=CONST`.
**200**
```json
{ "count": 2, "results": [
  { "id": 1, "name": "Coffee Park", "lat": -0.987654, "lng": 30.262345,
    "radius_m": 150, "allowed_wifi_bssids": ["a4:b1:c2:d3:e4:f5"],
    "departments": ["CONST","PROD"], "is_active": true }
]}
```

### POST /api/v1/sites  🔒 admin
Create a site (geofence + BSSID allow-list).
**Request** = site object without `id`. **201** → created site. `400` on bad
lat/lng or malformed BSSID.

### PATCH /api/v1/sites/{id}  🔒 admin
Partial update (e.g. toggle `is_active`, edit BSSID list). **200** → updated site.

### DELETE /api/v1/sites/{id}  🔒 admin
**204.** `409 site_in_use` if attendance records reference it (PROTECT).

---

## 5. Employees (roster)

### GET /api/v1/employees  🔒 hr, admin, hod*
List employees. `?department=CONST&is_active=true&ordering=full_name`.
\*HoD is scoped to their own department (enforced server-side — see RBAC matrix).
**200** → paginated `Employee[]`.

### POST /api/v1/employees  🔒 hr, admin
Pre-register an employee — this row is what authorizes their future Google login
(SPRINT_0 §6). **201** → created employee. `409 email_exists` on duplicate email.

### GET /api/v1/employees/{id}  🔒 self, hr, admin, hod(own dept)
**200** → `Employee`. `404` if outside the caller's allowed scope (we return 404,
not 403, to avoid leaking existence — see RBAC matrix §note).

### PATCH /api/v1/employees/{id}  🔒 hr, admin
Update role, department, active status. **200**.

---

## 6. Attendance  🟡 *Phase 1 preview — contract draft, not yet built*

Detailed in Phase 1 design; sketched here so clients can plan. Backed by
`AttendanceRecord` in the [ERD](./ERD.md). The full check-in/out interaction is
specified in [Sequence Diagrams](./sequence-diagrams.md).

### POST /api/v1/attendance/check-in  🔒 employee
Capture a check-in. Location + WiFi are read **only at this moment** (privacy
§12a.1). Works through the Flutter offline queue, so `captured_at` may precede
`received_at`.

**Request**
```json
{
  "site_id": 1,
  "lat": -0.987650, "lng": 30.262340,
  "wifi_bssid": "a4:b1:c2:d3:e4:f5",
  "captured_at": "2026-06-18T07:02:11Z",
  "client_event_id": "uuid-for-idempotency"
}
```
**201** → the stored record incl. `within_geofence`, `mock_location_suspected`,
`received_at`. **409 duplicate_event** if `client_event_id` already synced
(makes offline retry safe). **422 outside_geofence** *only if* policy rejects
out-of-fence check-ins (TBD Phase 1 — default is accept-and-flag).

### POST /api/v1/attendance/check-out  🔒 employee
Same shape; `kind = check_out`.

### GET /api/v1/attendance  🔒 role-scoped
Employee → own records only ("audit your own", §12a.3). HoD → own department.
HR/Exec → org-wide. Filters: `?date=2026-06-18&site=1&employee=EMP001`.

### WS /ws/v1/attendance/feed  🔒 hod, hr, exec
Django Channels websocket: live check-in/out events for the dashboard
("live attendance feed", SPRINT_0 §1, Phase 1 critical path). Auth via
`?token=<access>` on the upgrade request. Server pushes:
```json
{ "type": "check_in", "employee_id": "EMP001", "site_id": 1,
  "within_geofence": true, "received_at": "2026-06-18T07:02:13Z" }
```

---

## 7. App versions (in-app update)

### 🔓 GET /api/v1/app/versions/latest?platform=android
Powers the update banner (SPRINT_0 §9). Public so the app can check before login.
**200**
```json
{ "version": "0.0.1", "url": "https://iag-dl.duckdns.org/app-release.apk",
  "sha256": "…", "mandatory": false }
```

### POST /api/v1/internal/app/versions  🔒 release token
Called by the `apk-release.yml` CI job (SPRINT_0 §8) to register a new build.
Auth is a static `RELEASE_TOKEN` bearer (machine-to-machine, not a user JWT).
**201** → created `AppVersion`. `401` on bad token.

---

## 8. Health

### 🔓 GET /healthz
Liveness probe (no `/api/v1` prefix — it's infra, not product). **200**
`{ "status": "ok", "db": "ok", "redis": "ok" }`. Used by the deploy pipeline's
acceptance check (SPRINT_0 §11.2) and by nginx/uptime monitoring.

---

## 9. The machine-readable spec (OpenAPI)

This Markdown is for humans. The **executable** contract is
`inspired-api/openapi.yaml` (OpenAPI 3.1), generated from DRF via
`drf-spectacular`. It is the artifact that:

- generates the Flutter Dio client and TypeScript dashboard client,
- powers an interactive `/api/docs` (Swagger UI) in dev,
- backs a mock server so clients build before the backend is ready,
- is diffed in CI to catch **breaking changes** before merge.

**Rule:** when this doc and `openapi.yaml` disagree, the YAML wins and this doc
is fixed. Keep them in sync in the same PR.

---

## 10. Endpoint summary

| Method | Path | Auth | Phase |
|---|---|---|---|
| POST | `/api/v1/auth/google` | 🔓 | Sprint 0 |
| POST | `/api/v1/auth/refresh` | 🔓 | Sprint 0 |
| POST | `/api/v1/auth/logout` | user | Sprint 0 |
| GET | `/api/v1/me` | user | Sprint 0 |
| POST | `/api/v1/devices` | user | Sprint 0 |
| DELETE | `/api/v1/devices/{id}` | user | Sprint 0 |
| GET | `/api/v1/departments` | user | Sprint 0 |
| GET | `/api/v1/sites` | user | Sprint 0 / P1 |
| POST/PATCH/DELETE | `/api/v1/sites…` | admin | Phase 1 |
| GET/POST | `/api/v1/employees…` | hr, admin, hod | Phase 1 |
| POST | `/api/v1/attendance/check-in` | employee | Phase 1 |
| POST | `/api/v1/attendance/check-out` | employee | Phase 1 |
| GET | `/api/v1/attendance` | role-scoped | Phase 1 |
| WS | `/ws/v1/attendance/feed` | hod, hr, exec | Phase 1 |
| GET | `/api/v1/app/versions/latest` | 🔓 | Sprint 0 |
| POST | `/api/v1/internal/app/versions` | release token | Sprint 0 |
| GET | `/healthz` | 🔓 | Sprint 0 |

---

## 11. Change log
| Date | Change |
|---|---|
| 2026-06-18 | Initial spec — Sprint 0 endpoints + Phase 1 attendance preview |
