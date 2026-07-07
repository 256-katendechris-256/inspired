# Runbook — Stable local backend access via Tailscale (no cloud, no card)

**Status:** ✅ Live · **Owner:** Dev · **Source of truth for:** reaching the locally-run backend from the test phone reliably, with no paid hosting
**Last updated:** 2026-06-19 · **Context:** stopgap until a card works for [DigitalOcean](./deploy-digitalocean.md)

---

## 0. Why this exists

DigitalOcean rejected the prepaid card, so the droplet is on hold. Meanwhile the
backend still runs on the laptop, and the old pain — *"can't connect to the
server"* — had two causes:

1. **The process:** `manage.py runserver` (Django's dev server) is single-threaded
   and restarts/dies easily.
2. **The address:** `192.168.1.176` is a DHCP lease that changes, only reachable
   on the same WiFi, and Android blocks cleartext HTTP to it.

This runbook fixes both, free and without a card: **gunicorn** for a stable
process, **Tailscale** for a stable HTTPS name that works across WiFi and mobile
data. When the card is sorted, switch to the [DigitalOcean
runbook](./deploy-digitalocean.md) — the gunicorn stack is identical.

## 1. Shape

```
  Phone (Tailscale app)                 Laptop (Tailscale + gunicorn)
  Flutter app                           tailscale serve  ── HTTPS ──┐
        │  https://<laptop>.ts.net  ─────────────────────────────►  │
        └──────────────── encrypted Tailscale mesh ────────────────►┘
                                                       gunicorn :8000
                                                       (Django + docker db/redis)
```

Tailscale gives the laptop a permanent **MagicDNS** name
(`<laptop>.<tailnet>.ts.net`) that does not change with networks or DHCP.
`tailscale serve` fronts gunicorn with a valid HTTPS cert on that name, so the
Flutter app talks HTTPS — no Android cleartext exception needed.

## 2. Laptop setup

### 2.1 Install Tailscale and log in
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up          # opens a browser login — sign in (Google works)
tailscale status           # note this machine's name, e.g. katende-laptop
tailscale cert --help >/dev/null 2>&1 || true   # ensure HTTPS feature available
```
Enable **MagicDNS** and **HTTPS Certificates** once in the Tailscale admin console
(DNS page) if not already on.

### 2.2 Run the backend under gunicorn
Keep Postgres + Redis in docker, run Django with gunicorn bound to localhost:
```bash
cd /home/katende/inspired-api
docker compose up -d db redis           # data services only
# point .env at the host-published ports for a host-run gunicorn:
#   DATABASE_URL=postgres://iag:iag@localhost:5433/iag_dev
#   REDIS_URL=redis://localhost:6379/0
.venv/bin/python manage.py migrate
.venv/bin/gunicorn config.wsgi:application --bind 127.0.0.1:8000 --workers 3
```
(Or run the whole stack in docker — the point is gunicorn, not `runserver`.)

### 2.3 Expose it over HTTPS on the stable name
```bash
sudo tailscale serve --bg 8000
tailscale serve status      # prints the public-to-your-tailnet https://<laptop>.<tailnet>.ts.net
```
That URL is stable across reboots and network changes.

## 3. Phone setup
1. Install the **Tailscale** app (Play Store).
2. Log in with the **same account** as the laptop.
3. Confirm both devices show in `tailscale status` / the app.

The phone can now reach `https://<laptop>.<tailnet>.ts.net` on WiFi *or* mobile
data, as long as the laptop is on and gunicorn + `tailscale serve` are running.

## 4. Point the Flutter app at it
```bash
flutter run --dart-define=BACKEND_URL=https://<laptop>.<tailnet>.ts.net
```
Also add the host to Django so it accepts the requests — in `inspired-api/.env`:
```
ALLOWED_HOSTS=localhost,127.0.0.1,<laptop>.<tailnet>.ts.net
```

## 5. Limits (so expectations are right)
- The laptop must be **on and running** gunicorn + `tailscale serve`; this is a
  dev/test convenience, not 24/7 hosting.
- Only devices logged into **your tailnet** can reach it (that's the point — it's
  private). To demo to an outside device, use the DigitalOcean droplet instead, or
  a Cloudflare quick tunnel (`cloudflared tunnel --url http://localhost:8000`) —
  but that URL changes on every restart, so it is not a stable option.
- The Next.js dashboard already uses `localhost:8000` on the same laptop, so it
  needs no tunnel for local work.

## 6. Switching to the droplet later
When the card works, follow [Deploy to DigitalOcean](./deploy-digitalocean.md).
Stop `tailscale serve`, repoint `BACKEND_URL` to `https://iag-api.duckdns.org`,
and the same gunicorn stack runs there instead. Nothing else changes.
