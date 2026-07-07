# Sprint 0 — Foundation Spec

Everything that must exist before Phase 1 (attendance) work can start.
**Estimated effort:** 10–14 working days for one developer.

---

## 0. Decisions locked

| Concern | Choice |
|---|---|
| Backend | Django + DRF + Postgres |
| Realtime (dashboard) | Django Channels (websockets) over Redis |
| Mobile push | Firebase Cloud Messaging (mobile only — no Firestore, no Firebase Auth) |
| Mobile app | Flutter (`inspired/` repo) |
| Dashboards | Next.js 16 + Tailwind 4 + shadcn (`iams-dash/` repo) |
| Auth | Google OAuth → backend JWT (carries `employee_id` + role) |
| Sites | Multi-site / multi-zone, HR-configurable |
| APK delivery | Self-hosted download page + in-app version check |
| CI/CD | GitHub Actions → VPS deploy + signed APK build |
| GitHub | Personal account for now (migrate to free org later) |
| VPS provider | **DigitalOcean** — Basic Droplet, 2 GB RAM / 50 GB SSD, Frankfurt region (~$12/mo) |
| Domain | **DuckDNS** free subdomains for the pilot (3 subdomains, see §4); swap to company domain once recovered |
| Keystore backup | Google Drive (`.jks` file) + password manager entry (password — Drive alone is insufficient) |
| MVP users | Construction + Production departments at Coffee Park (Ntungamo) |

---

## 1. Architecture

```
┌─────────────────────┐         ┌──────────────────────┐
│  Flutter app        │ ──HTTPS─┤  iag-api.duckdns.org │
│  ("inspired")       │  + WSS  │  Django + DRF        │
│  Construction +     │         │  + Channels (Daphne) │
│  Production crews   │         │  ├─ Postgres         │
└─────────────────────┘         │  └─ Redis (Channels  │
         │                      │       + Celery later)│
         │ FCM push             └──────────────────────┘
         ▼                                  ▲
   Google FCM                               │ HTTPS + WSS
                                            │
┌─────────────────────┐                     │
│  Next.js dashboards │ ────────────────────┘
│  ("iams-dash")      │
│  Admin/HR/HoD/CEO   │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ iag-dl.duckdns.org  │  static APK + sha256 + version.json
└─────────────────────┘
```

All three apps deploy to **one DigitalOcean Droplet** behind nginx.
Postgres + Redis on the same box for v1. Nightly DB backup → DigitalOcean Spaces
(S3-compatible) or Backblaze B2.

---

## 2. Repos

Three repos under your personal GitHub account:

| Repo | Status | Stack |
|---|---|---|
| `inspired` | exists at `~/inspired/`, **not yet a git repo** — needs `git init` | Flutter |
| `iams-dash` | exists at `~/iams-dash/`, already a git repo | Next.js 16 |
| `inspired-api` | **new** — create during Sprint 0 | Django |

Three repos = three independent CI pipelines + cleaner access control.

---

## 3. Directory layouts

### `inspired-api/` (new repo)
```
.
├── pyproject.toml          # uv-managed
├── docker-compose.yml      # local dev: postgres + redis + django + daphne
├── Dockerfile              # production image
├── manage.py
├── config/
│   ├── settings/
│   │   ├── base.py
│   │   ├── dev.py
│   │   ├── staging.py
│   │   └── production.py
│   ├── urls.py
│   ├── asgi.py             # Channels
│   └── wsgi.py
├── apps/
│   ├── accounts/           # Employee, Role, Google OAuth, JWT
│   ├── orgs/               # Department, Site (geofence + BSSID)
│   ├── attendance/         # Phase 1 — model stubs only in Sprint 0
│   ├── notifications/      # FCM device registration + send helpers
│   └── core/               # base models, mixins, pagination, perms
├── ops/
│   └── bootstrap.sh        # one-time VPS setup script
├── tests/
└── .github/workflows/
    ├── ci.yml              # lint + test on every PR
    └── deploy.yml          # build image + ssh-deploy on push to main
```

### `iams-dash/` (existing)
```
.
├── src/
│   ├── app/
│   │   ├── (auth)/login/       # Google sign-in landing
│   │   ├── admin/              # System Admin
│   │   ├── hr/                 # HR
│   │   ├── hod/                # Heads of Department
│   │   ├── exec/               # CEO/GM
│   │   └── api/auth/[...]/     # NextAuth Google provider, forwards to backend
│   ├── components/             # existing components stay here
│   └── lib/
│       ├── api.ts              # fetch wrapper that attaches JWT
│       └── ws.ts               # Channels websocket client
└── .github/workflows/deploy.yml
```

### `inspired/` (existing — currently just the Flutter scaffold)
```
lib/
├── main.dart
├── core/
│   ├── api/                 # dio client + interceptors (JWT, retry)
│   ├── auth/                # google_sign_in + jwt storage
│   ├── storage/             # sqflite offline queue
│   ├── location/            # geolocator wrapper
│   ├── wifi/                # wifi_info_flutter (or wifi_scan)
│   └── update/              # version check + APK download prompt
├── features/
│   ├── auth/
│   ├── home/
│   └── attendance/          # Phase 1 — empty in Sprint 0
└── shared/widgets/
.github/workflows/
└── apk-release.yml          # build + sign + upload + bump version row
```

**Android package name:** `com.inspireafrica.inspired`

---

## 4. Domains & DigitalOcean setup

**Domain strategy:** Free DuckDNS subdomains for the pilot. DuckDNS gives one
account up to 5 free subdomains pointing to any IP, supports Let's Encrypt
(via DNS-01 with their token, or HTTP-01 if port 80 is open). When the
company domain is recovered, change three DNS records and the apps keep working —
the only code change is one base-URL constant in Flutter and one in the dashboards.

| DuckDNS subdomain (suggested) | Serves |
|---|---|
| `iag-dash.duckdns.org` | Next.js dashboards |
| `iag-api.duckdns.org` | Django (REST + websockets) |
| `iag-dl.duckdns.org` | APK file + `version.json` + `sha256.txt` |

Exact names are picked when you create the DuckDNS account (must be globally
unique). Replace the placeholders above with your actual choices throughout
this doc.

### DigitalOcean Droplet specs
- **Plan:** Basic, Regular Intel — 2 GB RAM / 1 vCPU / 50 GB SSD ($12/mo)
- **Region:** Frankfurt (lowest latency to Uganda among DO regions)
- **OS:** Ubuntu 24.04 LTS
- **Add-ons:** Enable backups ($2.40/mo — weekly automated snapshots)
- **Floating IP:** assign one so DNS doesn't need to change if the droplet is rebuilt

### VPS bootstrap (one-time, run as root)
```bash
# core packages
apt update && apt install -y nginx postgresql-16 redis-server \
    certbot python3-certbot-nginx docker.io docker-compose-plugin \
    ufw fail2ban rclone

# create deploy user
adduser iag && usermod -aG sudo,docker iag

# firewall
ufw allow OpenSSH && ufw allow 'Nginx Full' && ufw enable

# postgres
sudo -u postgres createuser iag --pwprompt
sudo -u postgres createdb iag_prod -O iag

# TLS for all three subdomains (DuckDNS resolves to the droplet IP first)
certbot --nginx -d iag-dash.duckdns.org -d iag-api.duckdns.org -d iag-dl.duckdns.org

# nightly backup cron (rclone → DigitalOcean Spaces)
echo "0 2 * * * iag pg_dump iag_prod | gzip | rclone rcat spaces:iag-backups/db-$(date +\%F).sql.gz" \
  >> /etc/crontab
```
Full script lives at `inspired-api/ops/bootstrap.sh`.

---

## 5. Django foundation

### Dependencies (`pyproject.toml`)
```
django ^5.1
djangorestframework
djangorestframework-simplejwt
django-cors-headers
channels[daphne]
channels-redis
psycopg[binary]
redis
google-auth          # verify Google ID tokens
firebase-admin       # FCM
django-environ
gunicorn
```

### Core models (Sprint 0 scope only)

```python
# apps/orgs/models.py
class Department(models.Model):
    name = CharField(max_length=80, unique=True)
    code = CharField(max_length=16, unique=True)   # e.g. "CONST", "PROD"

class Site(models.Model):
    name = CharField(max_length=120)
    lat = DecimalField(max_digits=9, decimal_places=6)
    lng = DecimalField(max_digits=9, decimal_places=6)
    radius_m = PositiveIntegerField(default=150)
    allowed_wifi_bssids = ArrayField(CharField(max_length=17), default=list)
    departments = ManyToManyField(Department, related_name="sites")
    is_active = BooleanField(default=True)

# apps/accounts/models.py
class Role(models.TextChoices):
    EMPLOYEE = "employee"
    HOD      = "hod"
    HR       = "hr"
    ADMIN    = "admin"
    EXEC     = "exec"

class Employee(models.Model):
    employee_id = CharField(max_length=16, unique=True)   # canonical handle
    full_name   = CharField(max_length=120)
    email       = EmailField(unique=True)                  # gmail for now
    phone       = CharField(max_length=20, blank=True)
    department  = ForeignKey(Department, on_delete=PROTECT, related_name="employees")
    role        = CharField(max_length=16, choices=Role.choices, default=Role.EMPLOYEE)
    home_site   = ForeignKey(Site, on_delete=SET_NULL, null=True, blank=True)
    is_active   = BooleanField(default=True)
    created_at  = DateTimeField(auto_now_add=True)

class DeviceToken(models.Model):
    employee  = ForeignKey(Employee, on_delete=CASCADE, related_name="devices")
    fcm_token = CharField(max_length=255, unique=True)
    platform  = CharField(max_length=10)  # 'android' | 'ios' | 'web'
    last_seen = DateTimeField(auto_now=True)
```

**Seed fixture:**
- Sites: Coffee Park (Ntungamo), Ntinda HQ
- Departments: Construction (`CONST`), Production (`PROD`)
- One admin Employee (you) — role `ADMIN`

---

## 6. Google OAuth + JWT flow

### Dashboard (NextAuth)
1. User clicks "Sign in with Google" → NextAuth Google provider
2. NextAuth receives Google ID token
3. NextAuth's `signIn` callback POSTs id_token to `POST /api/auth/google` on Django
4. Django verifies via `google.oauth2.id_token.verify_oauth2_token`
5. Django looks up `Employee` by email; if not found → **403 "Not registered, contact HR"**
6. Django issues access JWT (15 min) + refresh JWT (30 days), claims `{employee_id, role, dept_code}`
7. Dashboard stores access token in memory + refresh in httpOnly cookie

### Flutter (`google_sign_in` package)
1. `GoogleSignIn().signIn()` → id token
2. App POSTs id_token to the same `POST /api/auth/google`
3. Same lookup + JWT issuance
4. App stores both tokens in `flutter_secure_storage`
5. Dio interceptor attaches `Authorization: Bearer <access>`, refreshes on 401

### Authorization gate (the critical security check)
```python
def get_or_403(id_token: str) -> Employee:
    info = id_token_lib.verify_oauth2_token(
        id_token, requests.Request(), settings.GOOGLE_OAUTH_CLIENT_ID
    )
    email = info["email"]
    try:
        return Employee.objects.get(email=email, is_active=True)
    except Employee.DoesNotExist:
        raise PermissionDenied("Not registered. Contact HR.")
```
Google login proves **identity**; the HR-pre-registration row is what proves **authorization**.

---

## 7. FCM provisioning

1. Create Firebase project (free tier) — Firebase console → Add project
2. Add Android app `com.inspireafrica.inspired` → download `google-services.json` → drop into `inspired/android/app/`
3. Project Settings → Service accounts → Generate private key → store as GitHub secret `FCM_SERVICE_ACCOUNT_JSON`
4. Backend reads it on boot via `firebase_admin.initialize_app(credentials.Certificate(json))`
5. Sprint 0 ships only the device registration endpoint (`POST /devices` → store fcm_token on Employee). Actual sending lives with each module.

---

## 8. CI/CD — GitHub Actions

### Backend `ci.yml` (every PR)
```yaml
on: pull_request
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres: { image: postgres:16, env: {POSTGRES_PASSWORD: pg}, ports: ['5432:5432'] }
      redis:    { image: redis:7, ports: ['6379:6379'] }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install uv && uv sync
      - run: uv run ruff check .
      - run: uv run mypy .
      - run: uv run pytest -q
```

### Backend `deploy.yml` (push to main)
```yaml
on: { push: { branches: [main] } }
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/build-push-action@v6
        with: { tags: ghcr.io/${{ github.repository }}:${{ github.sha }}, push: true }
      - uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.VPS_HOST }}
          username: iag
          key: ${{ secrets.VPS_SSH_KEY }}
          script: |
            cd ~/iag && docker compose pull && docker compose up -d && \
            docker compose exec -T web python manage.py migrate --noinput
```

### Dashboard `deploy.yml`
Next.js `build` → docker image → ssh deploy → restart compose service.
Keep it inside the same docker-compose stack on the VPS so ops is uniform.

### Flutter `apk-release.yml` (on tag `v*`)
```yaml
on: { push: { tags: ['v*'] } }
jobs:
  apk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.x', channel: stable }
      - run: flutter pub get
      - name: Decode keystore
        run: echo "${{ secrets.ANDROID_KEYSTORE_B64 }}" | base64 -d > android/app/release.jks
      - run: flutter build apk --release
      - name: sha256
        run: sha256sum build/app/outputs/flutter-apk/app-release.apk > sha256.txt
      - uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.VPS_HOST }}
          username: iag
          key: ${{ secrets.VPS_SSH_KEY }}
          source: "build/app/outputs/flutter-apk/app-release.apk,sha256.txt,version.json"
          target: "/var/www/download/"
      - name: Bump version row in backend
        run: |
          curl -X POST https://iag-api.duckdns.org/internal/app/versions \
            -H "Authorization: Bearer ${{ secrets.RELEASE_TOKEN }}" \
            -d '{"platform":"android","version":"${{ github.ref_name }}","url":"https://iag-dl.duckdns.org/app-release.apk","sha256":"'"$(cut -d' ' -f1 sha256.txt)"'"}'
```

---

## 9. In-app update mechanism

- Endpoint: `GET /app/versions/latest?platform=android` → `{version, url, sha256, mandatory: bool}`
- Flutter calls it on launch; if `latest.version > pubspec.version` shows banner → opens `url`
- `mandatory: true` blocks all screens behind the update prompt (used for security fixes)

---

## 10. Environment variables

| Name | Where | Purpose |
|---|---|---|
| `DJANGO_SECRET_KEY` | VPS `.env` | Django secret |
| `DATABASE_URL` | VPS `.env` | `postgres://iag:…@localhost/iag_prod` |
| `REDIS_URL` | VPS `.env` | `redis://localhost:6379/0` |
| `GOOGLE_OAUTH_CLIENT_ID` | both | OAuth audience verification |
| `FCM_SERVICE_ACCOUNT_JSON` | VPS `.env` (file path) | Firebase admin |
| `ALLOWED_HOSTS` | VPS `.env` | `iag-api.duckdns.org` |
| `CORS_ALLOWED_ORIGINS` | VPS `.env` | `https://iag-dash.duckdns.org` |
| `VPS_HOST`, `VPS_SSH_KEY` | GitHub Secrets | Deploy |
| `ANDROID_KEYSTORE_B64`, `KEY_ALIAS`, `KEY_PASSWORD` | GitHub Secrets | APK signing |
| `RELEASE_TOKEN` | GitHub Secrets | Bumping version row |

---

## 11. Acceptance criteria — Sprint 0 is "done" when

1. `git push` to any of the three repos triggers green CI
2. Merge to `main` on backend → image lands on VPS, migrations run, `/healthz` returns 200
3. Merge to `main` on dashboards → live at `https://iag-dash.duckdns.org/login`
4. Tag `v0.0.1` on `inspired` → signed APK at `https://iag-dl.duckdns.org/app-release.apk` + version row in DB
5. "Sign in with Google" on dashboard → backend returns JWT → you're on `/hr` (you're seeded as HR/Admin)
6. Same Google sign-in on Flutter APK → token stored, app lands on home screen
7. Unregistered Gmail attempting login → 403 "Not registered" on both clients
8. Admin can create a new `Site` and `Employee` in Django admin (no UI yet)
9. Flutter app registers its FCM token to backend (visible in Django admin under `DeviceToken`)
10. App launched with old version → "Update available" banner appears

---

## 12. Day-by-day estimate (one developer)

| Day | Work |
|---|---|
| 1 | DigitalOcean Droplet, DNS, TLS, Postgres + Redis up |
| 2 | Django scaffold, base settings, Dockerfile + compose, `/healthz` |
| 3 | Core models (Employee, Department, Site, Role, DeviceToken) + admin + seed fixture |
| 4 | Google OAuth verify endpoint + JWT issuance + 403 gate + tests |
| 5 | Backend GitHub Actions (CI + deploy) green end-to-end |
| 6 | NextAuth Google sign-in + JWT exchange + protected route guards |
| 7 | Dashboards GitHub Actions + first deploy + login round-trip in prod |
| 8 | Flutter: google_sign_in + dio + secure storage + login screen + protected home |
| 9 | Flutter: in-app version check + update banner |
| 10 | Flutter: FCM token registration + Android keystore + signed build |
| 11 | Flutter GitHub Actions (apk-release) + download page served by nginx |
| 12 | End-to-end smoke test of all 10 acceptance criteria |
| 13–14 | Buffer / fixes / docs |

---

## 12a. Privacy posture (locked decisions)

These are non-negotiable design constraints — bake into every module.

1. **Location captured only at explicit user action.** Flutter app requests "while using app" location permission only (never background). GPS + WiFi BSSID are read at the moment the employee taps Check In or Check Out. No periodic/silent location queries.
2. **No admin UI exposes device data.** FCM tokens exist in DB to deliver push notifications. No `/admin/devices` page, no "last seen" displays, no "force re-auth from device" admin action. The original `devices-page.tsx` in the dashboard prototype is removed, not repurposed.
3. **Employee can audit their own attendance.** Mobile app has an "Attendance history" screen showing every record made about them — transparency principle.
4. **First-launch privacy notice in Flutter app**: explicit text that the app records location + WiFi only at check-in/out moments, not otherwise.
5. **Retention policy on attendance records.** Default 24 months active, then archive/delete. HR-configurable. Terminated employees: compliance period then purge.
6. **Audit log is for security events only** (logins, permission changes, data exports), never for surveillance of normal employee activity.

## 12b. Dashboard audit verdict (GPS+WiFi alignment)

The original `iams-dash` prototype was built around physical attendance devices. With the GPS+WiFi mobile model, the audit verdict is:

| Disposition | Components |
|---|---|
| **KEEP** | sidebar, header, theme provider/toggle, metric-card, attendance-chart, attendance-pie, activity-timeline, system-alerts, employees-table, department-table, audit-page, settings-page, hr/layout, hr/sidebar, hr/pages/hr-dashboard, hr/pages/hr-cards, hr/pages/hr-leave, ui/* shadcn primitives |
| **REFACTOR** | login-page → Google sign-in; attendance-page → GPS+WiFi data + per-site geofence map; recent-checkins → mobile check-ins; roles-page → our Role enum (employee/hod/hr/admin/exec); departments-page → wire to real `Department` model; reports-page → daily ops reports; hr/pages/hr-bulk → align with `Employee` schema; root `page.tsx` dashboard cards → drop lunch metrics, add active sites |
| **REMOVE** | devices-page (per privacy posture above), lunch-page, recent-lunches |
| **NEW** | Sites (System Admin — geofence + BSSID CRUD), Item Requests (HoD/Stores, Phase 3), Project Tracking (HoD+, Phase 4), App Versions (System Admin), Cross-dept Analytics (Exec, Phase 6) |

Web personas — employees do **not** use the web dashboard, only the Flutter app:

| Role | Web home |
|---|---|
| HoD | Their dept's live attendance + pending approvals |
| HR | Org-wide attendance, leave management, employee roster |
| System Admin | Sites + Users/Roles + Audit + App Versions |
| Exec/CEO | Cross-module analytics |

Phase 1 critical path:
1. Wire `/` to real auth, route by role, drop demo
2. Build Sites admin page (must exist before attendance check-ins can verify)
3. Backend: `AttendanceRecord` + check-in/check-out endpoints + Channels live feed
4. Refactor `attendance-page.tsx` to consume real data
5. Refactor `recent-checkins.tsx` to GPS+WiFi events
6. Remove lunch + devices pages

## 13. Risks to keep in mind

1. **Ntungamo connectivity** — Flutter offline queue is mandatory for Phase 1
2. **WiFi BSSID spoofing** is trivial on rooted phones — treat WiFi as positive signal, not proof; combine with GPS + device fingerprint
3. **Google OAuth without Workspace** — anyone with Gmail could attempt login; the HR-pre-registration gate is what enforces authorization
4. **Self-hosted APK** — must serve over HTTPS, signed with a consistent keystore, sha256 published
5. **Android keystore loss = no future updates** — back up `release.jks` + password to two offsite locations (1Password / encrypted USB / Google Drive vault)
6. **Single VPS is a SPOF** — acceptable for v1; nightly Postgres backup mitigates data loss
7. **Anti-spoofing is an arms race** — start with mock-location detection + HR review queue; don't chase 100% on day one

---

## 14. Status & next action

All Sprint 0 pre-decisions are settled:
- Domain — DuckDNS (free, 3 subdomains, swap to company domain later)
- VPS — DigitalOcean Droplet, Frankfurt, $12/mo
- GitHub — personal account
- Keystore backup — Google Drive (file) + password manager (password)
- Execution mode — step-by-step with the assistant

**Next action:** begin Day 1 (DuckDNS signup → DigitalOcean droplet → DNS → bootstrap).
