# Runbook — Deploy `inspired-api` to a DigitalOcean droplet

**Status:** ✅ Live · **Owner:** Ops / Backend · **Source of truth for:** standing up the pilot backend on a stable, always-on server
**Last updated:** 2026-06-19 · **Context:** [ADR-0001 §4 alt. 1 — de-risk first](../02-architecture/adr/0001-migrate-backend-to-supabase.md)

---

## 0. Why this runbook exists

The development pain — *"the server keeps going on and off"* — is a **hosting**
problem, not a code problem. The backend runs locally and is reached over a flaky
LAN address (`127.0.0.1:40537` / `192.168.1.176:8000`). The fix is to run the
existing stack on an always-on server with a stable public HTTPS URL.

DigitalOcean's **new-account free credit (~$200 / 60 days)** covers this many times
over (a suitable droplet is ~$6–12/month), so **use the credit now — do not wait
for paid billing to start.** This unblocks development and testing immediately and
keeps the Supabase question separate, to be decided later on its own merits.

> ⚠️ **Credit expiry.** The credit lasts ~60 days. Before it runs out, add a
> payment method (the droplet keeps running) or migrate. Put a reminder on the
> calendar for ~day 50.

## 1. What gets deployed

The same three-container stack as dev, hardened for a public server via
[`docker-compose.prod.yml`](../../../inspired-api/docker-compose.prod.yml):

```
                 Internet (HTTPS :443)
                          │
                    ┌─────▼─────┐   automatic Let's Encrypt TLS
                    │   Caddy   │   (Caddyfile)
                    └─────┬─────┘
                          │  http :8000 (internal network only)
                    ┌─────▼─────┐
                    │ web       │   gunicorn → config.wsgi
                    │ (Django)  │   migrate + collectstatic on boot
                    └──┬─────┬──┘
              ┌────────▼─┐ ┌─▼────────┐
              │ db       │ │ redis    │   no published host ports —
              │ postgres │ │          │   reachable only inside the stack
              └──────────┘ └──────────┘
```

Key hardening vs. the dev `docker-compose.yml`:

- **gunicorn**, not `manage.py runserver` (the dev server is single-threaded and
  dies easily — a prime cause of the flakiness).
- **db and redis publish no host ports** — they were exposed on `5433`/`6379` in
  dev; on a public droplet that is a wide-open attack surface. They talk to `web`
  over the internal docker network only.
- **Caddy** terminates TLS with auto-renewing Let's Encrypt certs (modern Android
  blocks cleartext HTTP, so HTTPS is required for the Flutter app).
- **`restart: unless-stopped`** on every service — survives reboots and crashes.

## 2. Prerequisites

- [ ] A DigitalOcean account with the free credit applied.
- [ ] An SSH key added to your DO account (Settings → Security → SSH Keys).
- [ ] Control of the `iag-api.duckdns.org` DuckDNS record (already used in config).
- [ ] The `inspired-api` repo reachable from the droplet (git remote, or `scp`).

## 3. Procedure

### 3.1 Create the droplet
1. DO → **Create → Droplets**.
2. Image: **Ubuntu 24.04 LTS**. Plan: **Basic / Regular, 2 GB RAM** ($12/mo —
   comfortably inside the credit; 1 GB also works but builds are tight).
3. Region: closest to Uganda (e.g. **Frankfurt** or **Bangalore**) for latency.
4. Authentication: **SSH key**. Create, and note the **public IPv4**.

### 3.2 Point the domain at the droplet
1. In DuckDNS, set `iag-api` → the droplet's public IPv4.
2. Verify from your machine: `dig +short iag-api.duckdns.org` returns that IP.
   (TLS issuance in step 3.5 fails until DNS resolves correctly.)

### 3.3 Install Docker on the droplet
SSH in (`ssh root@<droplet-ip>`), then:
```bash
curl -fsSL https://get.docker.com | sh
# optional non-root user
adduser deploy && usermod -aG docker deploy
```
A basic firewall is good hygiene — open only SSH + web:
```bash
ufw allow OpenSSH && ufw allow 80 && ufw allow 443 && ufw --force enable
```

### 3.4 Get the code and configure secrets
```bash
git clone <your inspired-api remote> /opt/inspired-api
cd /opt/inspired-api
cp .env.prod.example .env
# generate a Django secret key:
python3 -c "import secrets; print(secrets.token_urlsafe(64))"
nano .env      # paste the secret key, set a STRONG POSTGRES_PASSWORD,
               # and make DATABASE_URL use that same password
```
Confirm `.env` has `DEBUG=False`, the correct `ALLOWED_HOSTS`,
`CSRF_TRUSTED_ORIGINS`, and matching DB password in `POSTGRES_PASSWORD` **and**
`DATABASE_URL`.

### 3.5 Launch
```bash
docker compose -f docker-compose.prod.yml up -d --build
```
On first boot `web` runs migrations and `collectstatic`, then gunicorn starts;
Caddy requests the TLS cert (needs DNS from 3.2 + ports 80/443 from 3.3).

### 3.6 Create the first admin user
```bash
docker compose -f docker-compose.prod.yml exec web python manage.py createsuperuser
```

### 3.7 Verify
```bash
curl https://iag-api.duckdns.org/healthz      # -> {"status":"ok","database":true}
```
Open `https://iag-api.duckdns.org/admin/` — the login page should be styled
(confirms static files are served) and login should succeed (confirms
`CSRF_TRUSTED_ORIGINS`).

## 4. Point the clients at the server

| App | Where | Change to |
|---|---|---|
| `inspired` (Flutter) | build define `BACKEND_URL` (`lib/core/config.dart` default) | `--dart-define=BACKEND_URL=https://iag-api.duckdns.org` |
| `iams-dash` (Next.js) | `.env.local` → `BACKEND_URL` | `https://iag-api.duckdns.org` |

The flaky LAN address is now gone for both clients.

## 5. Day-2 operations

```bash
# logs
docker compose -f docker-compose.prod.yml logs -f web
# deploy new code
git pull && docker compose -f docker-compose.prod.yml up -d --build
# run a migration manually
docker compose -f docker-compose.prod.yml exec web python manage.py migrate
# backup the database
docker compose -f docker-compose.prod.yml exec db \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > backup-$(date +%F).sql
```

A real backup schedule, monitoring, and restore drill belong in
[Backup & Restore](./backup-restore.md) and [SLO/Monitoring](./slo-monitoring.md)
(both 📄 templates today) — fill them before relying on this in production.

## 6. Relationship to the Supabase decision

This runbook is the **reversible, de-risking** path from
[ADR-0001](../02-architecture/adr/0001-migrate-backend-to-supabase.md): it fixes
the connectivity problem now with **zero rewrite** and **nothing deleted**. The
[Supabase migration plan](../05-delivery/supabase-migration-plan.md) remains an
*optional* later step, no longer coupled to this immediate fix.
