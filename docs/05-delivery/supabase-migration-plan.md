# Supabase Migration Plan

**Status:** 🟡 Live · **Owner:** Backend / Platform · **Source of truth for:** the sequence of work to move off Django onto Supabase
**Last updated:** 2026-06-19 · **Decision:** [ADR-0001](../02-architecture/adr/0001-migrate-backend-to-supabase.md)

---

## 0. What this document is

[ADR-0001](../02-architecture/adr/0001-migrate-backend-to-supabase.md) records
*what* we decided and *why*. This document is the *how and in what order* — the
phased execution plan and the living checklist the team works through. The ADR is
stable; this plan changes as phases complete. Tick the boxes as you go.

Three working assumptions (override in the ADR if any is wrong):

- **Cloud Supabase** (the always-on URL is the entire point).
- **Keep admin-preset-password onboarding** — matches today's flow: admin creates
  the user with a preset password, employee is forced to change it on first login.
- **Reseed dev data** rather than migrate the local dev DB (faster; the local DB
  is dev junk). Production data migration is a Phase 6 concern only if real data
  exists by cutover.

## 1. Target architecture

```
 inspired (Flutter)              iams-dash (Next.js 16)
 supabase_flutter                @supabase/ssr + supabase-js
        │                                │
        │   Supabase SDK: auth · queries · realtime
        └────────────────┬───────────────┘
                         ▼
        ┌────────────────────────────────────────────┐
        │                 SUPABASE                     │
        │  Auth (GoTrue)   email/password + Google     │
        │  Postgres + RLS  schema + role policies      │
        │  PostgREST       auto CRUD for reads         │
        │  Edge Functions  TRUSTED writes:             │
        │                  check-in · check-out ·      │
        │                  onboard · send-push         │
        │  Realtime        live dashboard updates      │
        └───────────────────────┬──────────────────────┘
                                │ called from Edge Functions
                                ▼
        ┌────────────────────────────────────────────┐
        │  Upstash Redis (serverless REST)            │
        │  cache · rate-limit · token blocklist        │
        │  Upstash QStash → schedule FCM / jobs        │
        └────────────────────────────────────────────┘
```

## 2. Component mapping (old → new)

| Today (`inspired-api` Django) | Becomes |
|---|---|
| `Employee` model + `EmployeeJWTAuthentication` | Supabase Auth (`auth.users`) + `public.employees` profile (FK to `auth.users.id`) |
| `role` / `employee_id` / `department` on Employee | columns on `public.employees`, **injected into the JWT** as `app_role` / `app_department_id` via an access-token hook for RLS |
| `accounts` views (check-email, login, set-password, google, refresh, me) | Supabase Auth flows + `must_change_password` flag; `onboard` Edge Function for admin-preset passwords |
| `orgs` models (Department / Site / Block; `allowed_wifi_bssids` ArrayField) | SQL tables; ArrayField → `text[]`, JSONField → `jsonb`, TextChoices → enums |
| `attendance` CheckIn/CheckOut **verification** (radius, BSSID, mock-GPS, accuracy) | `check-in` / `check-out` **Edge Functions** (service-role insert; RLS blocks client writes) |
| `me/today`, `me/sites`, `me/history` reads | PostgREST queries + RLS (self / dept / all by role) |
| `notifications.DeviceToken` + FCM | `device_tokens` table + `send-push` Edge Function, scheduled via QStash/`pg_cron` |
| `core.healthz` | Supabase status / trivial Edge Function |
| docker-compose Postgres + unused Redis | Supabase Postgres + Upstash Redis (now wired) |

## 3. Three hard problems (design these before coding the phase that needs them)

1. **Auth model shift.** `public.employees.id` = `auth.users.id` (uuid FK). Drop
   the local `password` column — Supabase Auth owns credentials. Keep
   `must_change_password` + `password_changed_at` as app flags. An **access-token
   hook** (Postgres function registered with Supabase Auth) injects `app_role` and
   `app_department_id` into the JWT so RLS reads them without recursing into
   `employees`. ⚠️ Do **not** name the claim `role` — that claim is reserved by
   PostgREST to choose the database role.

2. **Geofence trust stays server-side.** If clients could `INSERT` into
   `attendance_records` via PostgREST they could forge a `verified` status or fake
   coordinates. Therefore **RLS grants clients no INSERT/UPDATE on
   `attendance_records`** — the only write path is the `check-in`/`check-out` Edge
   Functions, which re-run the radius + BSSID + mock-location checks and insert
   with the service role. This preserves exactly what `CheckInView` does today.

3. **Redis queues need a worker Supabase won't host.** Cache, rate-limit, and
   token-blocklist run fine from Edge Functions over Upstash's REST API. A
   BullMQ-style queue needs a long-running process with nowhere to live here — use
   **Upstash QStash** (or `pg_cron`) to trigger the `send-push` Edge Function on a
   schedule/event instead.

## 4. Phased checklist

### Phase 0 — Provision & spike (manual; needs your accounts)
- [ ] Create the cloud Supabase project; capture project URL, `anon` key, `service_role` key.
- [ ] Create Upstash Redis + QStash; capture REST URL + token.
- [ ] Configure the Google provider in Supabase Auth (reuse client ID `983569230522-…`).
- [ ] Install Supabase CLI; `supabase init` + `supabase link` the project.
- [ ] Spike: a hello-world Edge Function that reads/writes Upstash Redis.
- [ ] Store secrets (`supabase secrets set …`); never commit keys.

### Phase 1 — Schema, RLS & auth hook
- [ ] SQL migration: enums (`role`, `verification_method`, `verification_status`, `platform`).
- [ ] Tables: `departments`, `sites`, `site_departments`, `blocks`, `employees`, `attendance_records`, `device_tokens` (faithful to the [ERD](../03-design/ERD.md); ArrayField→`text[]`, JSONField→`jsonb`).
- [ ] Indexes: `(employee_id, check_in_at desc)`, `(site_id, check_in_at desc)`; `updated_at` trigger.
- [ ] RLS policies per role ([RBAC Matrix](../03-design/rbac-matrix.md)); **deny client writes to `attendance_records`**.
- [ ] Access-token hook injecting `app_role` / `app_department_id`; register it in Auth.
- [ ] Seed orgs (departments/sites/blocks); document that employees seed via Admin API (need `auth.users`).

### Phase 2 — Trusted write path (Edge Functions)
- [ ] Port `CheckInView` logic → `check-in` Edge Function (radius, BSSID, accuracy, mock-location, single-active-record guard).
- [ ] Port `CheckOutView` → `check-out` Edge Function.
- [ ] `onboard` Edge Function (admin-only): create `auth.users` with preset password + `employees` row, `must_change_password=true`.
- [ ] Upstash rate-limit on check-in and auth attempts.

### Phase 3 — Dashboard (`iams-dash`)
- [ ] Add `@supabase/supabase-js` + `@supabase/ssr`; remove `lib/session.ts`, `lib/config.ts`, `/api/auth/*`, `BACKEND_URL`.
- [ ] Supabase Auth (Google) for login; role-gated pages from JWT claims.
- [ ] Wire pages to PostgREST queries; Realtime subscription for live check-ins.
- [ ] Redis-cached aggregates for reports/metrics pages.

### Phase 4 — Flutter app (`inspired`)
- [ ] Add `supabase_flutter`; replace `core/api/api_client.dart` + custom JWT storage.
- [ ] Supabase Auth login + forced password change on first login.
- [ ] Check-in/out call Edge Functions; history/sites via queries; keep the geofence map.
- [ ] Remove the `BACKEND_URL` dart-define (the LAN root cause).

### Phase 5 — Notifications & jobs
- [ ] `device_tokens` register/refresh from clients (RLS: self only).
- [ ] `send-push` Edge Function (FCM); schedule via QStash/`pg_cron`.
- [ ] JWT/session blocklist in Redis for logout-everywhere / force re-login.

### Phase 6 — Data migration & cutover
- [ ] If real data exists: `pg_dump` public tables → Supabase; migrate users into `auth.users` via Admin API. Otherwise reseed.
- [ ] Smoke-test both clients end-to-end against Supabase.
- [ ] Revise the affected ✅ Live docs: [API Specification](../03-design/api-specification.md), [ERD](../03-design/ERD.md), [RBAC Matrix](../03-design/rbac-matrix.md).
- [ ] Decommission `docker-compose` / Django; archive `inspired-api` as the spec reference.

## 5. Recommended first build step

After Phase 0 (which only you can do — it needs the accounts), the first code is
**Phase 1**: the SQL schema + RLS + access-token hook, because every other phase
depends on the schema and the role claims. Open question still to confirm: where
the Supabase project code (`supabase/migrations`, `supabase/functions`) lives —
a new `iams-supabase/` repo, or inside the existing `inspired-api` repo as it
transitions.
