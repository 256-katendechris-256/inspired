# ADR-0001 — Migrate the backend to a Supabase-native architecture

**Status:** ✅ Accepted · **Date:** 2026-06-19 · **Owner:** Backend / Platform
**Supersedes:** the `inspired-api` Django + self-hosted Postgres/Redis stack (SPRINT_0 §2)
**Affects:** [ERD](../../03-design/ERD.md), [API Specification](../../03-design/api-specification.md), [RBAC Matrix](../../03-design/rbac-matrix.md), `inspired` (Flutter), `iams-dash` (Next.js)

---

## 0. What an ADR is and why this one exists

An **Architecture Decision Record** captures a single significant, hard-to-reverse
decision: the context that forced it, the options weighed, the choice made, and
the consequences we accept by making it. It exists so that six months from now
nobody has to reverse-engineer *why* the backend looks the way it does — the
reasoning is written down once, here, and everything else links to it.

This ADR records the decision to **replace the self-run Django backend with a
Supabase-native architecture.**

## 1. Context — the forcing function

The system is three apps against one backend (SPRINT_0 §2):

- `inspired` — Flutter employee app (geofenced GPS + WiFi check-in/out)
- `inspired-api` — Django 6 + DRF REST API
- `iams-dash` — Next.js HR/admin dashboard

During development the `inspired-api` server is run locally and reached over the
LAN (`http://192.168.1.176:8000`, and at times a forwarded `127.0.0.1:40537`).
That server **keeps going on and off**, so the Flutter app and the dashboard
cannot reliably reach the API. Development and testing stall whenever the box or
the tunnel drops. The root cause is not the database — it is that there is a
**server we have to keep alive ourselves**, on an address that is not stable.

Two facts shaped the decision:

1. The backend **already** uses Postgres, and Redis is declared in
   `docker-compose.yml` but **not used anywhere in code** (no cache, Celery, or
   channels). So the data layer is already Postgres-shaped — Supabase *is*
   managed Postgres.
2. The thing that actually has to be trusted on the server — **geofence /
   mock-location / WiFi-BSSID verification** at check-in — is a small, isolatable
   piece of logic. It does not require a full Django runtime; it requires a
   trusted execution context.

## 2. Decision

**Adopt a full Supabase-native architecture and retire the Django backend.**

| Concern | Was (Django) | Now (Supabase-native) |
|---|---|---|
| Database | self-hosted Postgres (docker) | **Supabase Postgres** (managed, always-on) |
| Auth | custom `Employee` JWT + Google OAuth | **Supabase Auth** (email/password + Google) + `public.employees` profile |
| Authorization | DRF permission classes | **Postgres RLS** + role claim injected via access-token hook |
| Reads (CRUD) | DRF views | **PostgREST** auto-API, constrained by RLS |
| Trusted writes (check-in/out) | DRF `CheckInView` | **Edge Functions** (service-role insert; clients cannot write directly) |
| Live dashboard | polling | **Supabase Realtime** |
| Push / async jobs | (planned Celery) | **Edge Functions** triggered by **Upstash QStash / `pg_cron`** |
| Cache / rate-limit / token blocklist | (unused Redis) | **Upstash Redis** (serverless REST), wired in Edge Functions |
| Hosting | a server we run on the LAN | **none we run** — clients hit Supabase's stable URL |

Clients move to first-party SDKs: `supabase_flutter` in `inspired`,
`@supabase/supabase-js` (+ `@supabase/ssr`) in `iams-dash`.

## 3. Consequences

**Positive**

- The "server keeps going on/off" failure mode is **designed out** — there is no
  self-run API process and no LAN address; the backend is a managed, always-on
  URL.
- Less code to own: CRUD, auth, refresh, and Realtime are handled by Supabase
  instead of hand-written DRF views.
- Security-sensitive logic shrinks to a few Edge Functions with a clear trust
  boundary (RLS forbids direct attendance writes).

**Negative / costs we accept**

- **It is a rewrite, not a config change.** Auth, every endpoint, and the
  dashboard/Flutter data layers change. Estimated multi-week effort (see the
  [migration plan](../../05-delivery/supabase-migration-plan.md)).
- **Auth semantics shift.** Our identity is `employee_id`; Supabase Auth is keyed
  on `auth.users` (email + uuid). We carry a `public.employees` profile linked by
  FK and inject `app_role` / `app_department_id` claims into the JWT for RLS.
- **Vendor coupling.** RLS policies, Edge Functions, and the access-token hook are
  Supabase-specific. Mitigated by the fact that the store is plain Postgres and
  migrations are SQL we own.
- **Background jobs need care.** Redis-backed worker queues (BullMQ) need a
  long-running process Supabase does not host. We use Upstash QStash or `pg_cron`
  to trigger Edge Functions instead of standing up a worker.

**Documents that must be revised as a result** (tracked in the migration plan):

- [API Specification](../../03-design/api-specification.md) — Django HTTP contract
  → Supabase (PostgREST resources + Edge Function endpoints + Auth flows).
- [ERD](../../03-design/ERD.md) — add the `auth.users` ↔ `employees` link; drop
  the local `password` column (Auth owns credentials).
- [RBAC Matrix](../../03-design/rbac-matrix.md) — express the role rules as RLS
  policies.

## 4. Alternatives considered

1. **Keep Django, lift only the infra to managed cloud** (point `DATABASE_URL` at
   Supabase Postgres, wire `REDIS_URL` to Upstash, deploy Django to Fly/Railway).
   *Lowest risk and fastest fix for the connectivity pain — but leaves a server we
   run and deploy, and does not deliver the "no backend to babysit" goal.*
   **Rejected** in favour of removing the self-run server entirely.
2. **Hybrid** — Supabase Postgres + Auth as the store, a thin server only for
   geofence verification. *Reasonable middle ground; rejected as unnecessary once
   Edge Functions cover the trusted-write path.*
3. **Full Supabase-native** — **chosen** (§2).

## 5. Status of the four Redis roles

Redis was named explicitly. Confirmed scope for Upstash Redis: **dashboard
caching, rate limiting (check-in/login), JWT/session blocklist, and background
jobs / FCM push.** Caching, rate-limiting, and blocklist run directly from Edge
Functions via the Upstash REST SDK; the jobs role is delivered via QStash/`pg_cron`
triggering an Edge Function, not a standing worker (see §3, Negative).
