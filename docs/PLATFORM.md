# Inspire Africa Group — Platform Documentation

One platform, three repositories: a Flutter field app, a Django API that owns
all the data and rules, and a Next.js dashboard for admin/HR/HOD/exec
oversight. This doc is the map — what each repo does, and exactly how to
stand it up.

| Repo | Role | Link |
|---|---|---|
| `inspired` | Flutter app crews use to check in/out, request leave, and raise requisitions | https://github.com/256-katendechris-256/inspired |
| `inspired-api` | Django + DRF service that owns the database and every business rule | https://github.com/256-katendechris-256/inspired-api |
| `iams-dash` | Next.js console where managers approve, configure, and report | https://github.com/256-katendechris-256/iams- |

---

## 1. `inspired` — Mobile app

**Repo:** https://github.com/256-katendechris-256/inspired

The field-facing Flutter app for construction/production crews. An employee
signs in with Google, checks in and out (verified by GPS against a site's
geofence, and by WiFi BSSID where a site has an approved network list), and
can raise **leave requests**, **finance requisitions**, and **store
requests** — all digitised versions of Inspire Africa Group's existing paper
forms (leave mirrors form `IAG/HRL/001`, store requests mirror the paper
"Request Note"). It works offline: check-ins queue locally (SQLite) and sync
once connectivity returns.

**Tech stack:** Flutter (Dart ^3.11), Riverpod, go_router, Dio,
flutter_secure_storage, google_sign_in, geolocator + network_info_plus,
sqflite (offline queue), Firebase Cloud Messaging, flutter_map / Mapbox.

**Feature modules — `lib/features/*`**

| Module | Purpose |
|---|---|
| `auth/` | Google sign-in, JWT session, forced password/first-login flows |
| `attendance/` | check-in/out, geofence + WiFi verification, warning banners |
| `home/` | dashboard, drawer, geofence map |
| `leave/` | leave request form + status tracking |
| `requests/` | finance requisitions + store requests hub |
| `profile/` | own profile, password change |

Cross-cutting logic lives in `lib/core/`: `api/` (Dio client + JWT/refresh
interceptor), `location/`, `wifi/`, `connectivity/`, `offline/` (sync queue),
`notifications/` (FCM), `storage/` (secure token storage).

### Set it up

1. **Install the Flutter SDK** — needs Dart ^3.11.4 (see `pubspec.yaml`).
   Confirm the toolchain:
   ```
   flutter doctor
   ```
2. **Clone and fetch packages**
   ```
   git clone git@github.com:256-katendechris-256/inspired.git
   cd inspired
   flutter pub get
   ```
3. **Add Firebase config (push notifications)** — drop your own
   `google-services.json` into `android/app/`. FCM won't initialise without
   it; it's not committed to the repo.
4. **Point the app at a backend** — all runtime config is injected with
   `--dart-define` (see `lib/core/config.dart`); every flag already has a
   working default, so this step is optional unless you're running
   `inspired-api` locally.
   ```
   flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8000    # Android emulator → host machine
   flutter run --dart-define=BACKEND_URL=http://192.168.1.176:8000  # physical device, same WiFi
   ```
5. **Run it**
   ```
   flutter run
   ```
   With no flags this talks straight to the live Railway backend — fine for
   UI work that doesn't need local backend changes.
6. **Build a release APK**
   ```
   flutter build apk --release \
     --dart-define=BACKEND_URL=https://web-production-2496d.up.railway.app
   ```

### Config flags — `lib/core/config.dart`

| `--dart-define` | Default | Purpose |
|---|---|---|
| `BACKEND_URL` | live Railway URL | Base URL of `inspired-api` |
| `GOOGLE_SERVER_CLIENT_ID` | baked in | Google OAuth web client ID — must match the backend's |
| `MAPBOX_TOKEN` | baked in (public `pk.`) | Geofence map tiles |
| `MAPBOX_STYLE` | `satellite-streets-v12` | Map style ID |

---

## 2. `inspired-api` — Backend API

**Repo:** https://github.com/256-katendechris-256/inspired-api

The single source of truth. A Django + DRF service that owns the Postgres
database and every business rule: who's allowed to do what (RBAC across five
roles), whether a check-in counts as verified, when a requisition needs a
second signature, and what the dashboards and mobile app are allowed to see.
Neither client touches the database directly — everything goes through this
API's JSON contract.

**Tech stack:** Django + DRF, PostgreSQL, Redis, JWT auth (Google OAuth
exchange), Gunicorn, Docker, pytest + pytest-django.

**Django apps — `apps/*`**

| App | Purpose |
|---|---|
| `accounts/` | Employee, Role (employee/hod/hr/admin/exec), onboarding |
| `attendance/` | check-in/out, geofence + WiFi verification, device-sharing detection |
| `dashboard/` | every admin/manager read + action endpoint the two frontends call |
| `leave/` | leave requests (mirrors `IAG/HRL/001`), HOD → HR approval chain |
| `requisitions/` | finance requisitions + store requests, multi-stage approval |
| `orgs/` | Department, Site, Block — the geofence hierarchy |
| `notifications/` | device (FCM) token registry + push dispatch |
| `core/` | `/healthz`, used by the deploy pipeline |

### Set it up (Docker — the intended path)

1. **Clone and configure**
   ```
   git clone git@github.com:256-katendechris-256/inspired-api.git
   cd inspired-api
   cp .env.example .env
   ```
   Fill in `DJANGO_SECRET_KEY` and `GOOGLE_OAUTH_CLIENT_ID` (same client ID
   the two frontends use). `docker-compose.yml` already wires
   `DATABASE_URL`/`REDIS_URL` for local dev — no need to touch those unless
   running outside Docker.
2. **Bring the stack up**
   ```
   docker compose up --build
   ```
   Starts three services: `db` (Postgres 16, host port **5434**), `redis`
   (6379), `web` (Gunicorn on **8000**).
3. **Migrate the schema**
   ```
   docker compose exec web python manage.py migrate
   ```
4. **Seed demo data (optional)**
   ```
   docker compose exec web python manage.py seed_demo
   ```
   Creates demo departments, a site, and employees you can log into — every
   seeded account's password is `demo1234`.
5. **Confirm it's alive**
   ```
   curl http://localhost:8000/healthz
   # → {"status": "ok", "db": "ok", "redis": "ok"}
   ```
6. **Run the test suite** — tests use `pytest-django`; if running outside
   the Docker network, point `DATABASE_URL` at the exposed host port first
   (the compose file's internal hostname `db` only resolves inside the
   network):
   ```
   DATABASE_URL=postgres://iag:iag@localhost:5434/iag_dev uv run pytest
   ```

### Environment variables — `.env`

| Variable | Purpose |
|---|---|
| `DJANGO_SECRET_KEY` | Django cryptographic signing key |
| `DEBUG` | `False` in anything resembling production |
| `ALLOWED_HOSTS` | Comma-separated host allowlist |
| `DATABASE_URL` | `postgres://user:pass@host:5432/db` |
| `REDIS_URL` | `redis://host:6379/0` |
| `CORS_ALLOWED_ORIGINS` | Origin(s) allowed to call the API — the dashboard's URL |
| `GOOGLE_OAUTH_CLIENT_ID` | Validates Google ID tokens from both clients |

### Deployment

Live today on **Railway** — `railway.toml` builds the repo's `Dockerfile`
directly and redeploys on every push to `main`. A second, fully documented
path exists for a self-managed box: a DigitalOcean droplet behind Caddy (see
`docs/06-operations/deploy-digitalocean.md` in this repo) — the original
Sprint 0 plan, kept as a fallback.

---

## 3. `iams-dash` — Web dashboard

**Repo:** https://github.com/256-katendechris-256/iams-

The management console — Admin, HR, HOD, and Exec sign in here to see what's
actually happening: who's on site right now, whose check-in got flagged and
why, approving leave and requisitions, configuring sites/geofences, and
running reports. It never talks to `inspired-api` directly from the browser
— every request goes through a Next.js route handler that attaches the
session's token server-side and forwards it on, so the API's bearer token
never reaches client JS.

**Tech stack:** Next.js 16 (App Router, Turbopack), React 19, TypeScript,
Tailwind CSS 4, shadcn / radix-ui, Recharts.

**Structure — `src/components/*`**

| Path | Purpose |
|---|---|
| `admin-shell.tsx` | sidebar, dashboard cards, drill-down dialogs |
| `sites/` | geofence editor — sites, blocks, map picker |
| `departments/` | department roster, bulk onboarding, resets |
| `employees/` | staff directory + per-employee detail |
| `attendance/` | attendance table + corrections |
| `pages/` | reports, roles, settings, leave, store & finance requisitions, audit log, devices |
| `hr/` | HR-specific views (bulk upload, HR dashboard) |

API routes live under `src/app/api/`: `admin/[...path]`, `leave/[...path]`,
and `requisitions/[...path]` each proxy straight through to the matching
`inspired-api` path.

### Set it up

1. **Clone and install**
   ```
   git clone git@github.com:256-katendechris-256/iams-.git iams-dash
   cd iams-dash
   npm install
   ```
2. **Configure environment**
   ```
   cp .env.example .env.local
   ```
   Set `NEXT_PUBLIC_GOOGLE_CLIENT_ID` (same client ID as the other two apps)
   and `BACKEND_URL` — `http://localhost:8000` for a locally running
   `inspired-api`, or the Railway URL to develop against live data.
3. **Run the dev server**
   ```
   npm run dev
   ```
   Serves at `http://localhost:3000`.
4. **Production build**
   ```
   npm run build
   npm start
   ```

### Environment variables — `.env.local`

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_GOOGLE_CLIENT_ID` | Google Sign-In client ID (public, browser-side) |
| `BACKEND_URL` | Base URL the server-side route handlers forward to |

### Deployment

Live on **Vercel** at https://iams-dash.vercel.app (project `iams-dash`).
Deploy from the CLI, or connect the GitHub repo in Vercel for automatic
deploys on push:
```
vercel --prod
```

---

## 4. How it fits together

Both clients authenticate the same way and speak to the same backend —
neither ever touches Postgres or Redis directly, and neither trusts the
other's data without going through `inspired-api` first.

```
 inspired (Flutter)  ⇄  inspired-api (Django)  ⇄  iams-dash (Next.js)
 field crews             Postgres + Redis          Admin/HR/HOD/Exec
```

### Shared config that must match across all three

| Concern | Where it's set |
|---|---|
| Google OAuth client ID | `inspired-api`'s `GOOGLE_OAUTH_CLIENT_ID` validates the token; `inspired`'s `GOOGLE_SERVER_CLIENT_ID` and `iams-dash`'s `NEXT_PUBLIC_GOOGLE_CLIENT_ID` must be the same client |
| Sign-in → session | Both clients `POST /api/auth/google` with an ID token, get back a JWT carrying `employee_id` + `role` |
| Backend location | `inspired`'s `BACKEND_URL` dart-define and `iams-dash`'s `BACKEND_URL` env var both point at the same `inspired-api` instance |
| Push notifications | Firebase Cloud Messaging: `inspired` registers a device token via `notifications/`; `inspired-api` dispatches through it |

### The five roles

Full matrix: `inspired`'s `docs/03-design/rbac-matrix.md`.

| Role | Scope |
|---|---|
| `employee` | self only |
| `hod` | own department |
| `hr` | org-wide, people |
| `admin` | org-wide, system |
| `exec` | org-wide, read-only |

### Running all three locally, in order

1. **`inspired-api` first**
   ```
   docker compose up --build
   docker compose exec web python manage.py migrate
   docker compose exec web python manage.py seed_demo
   ```
2. **Then `iams-dash`, pointed at it**
   ```
   BACKEND_URL=http://localhost:8000 npm run dev
   ```
3. **Then `inspired`, pointed at it**
   ```
   flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8000  # emulator
   ```
   Log in with any seeded demo account — password `demo1234` — on either
   client.

---

*Compiled from each repo's own configuration, models, and setup scripts.
Treat repo `docs/` folders (especially `inspired/docs/`) as the living
source of truth where the two disagree.*
