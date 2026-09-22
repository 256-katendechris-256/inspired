# ERP Integration Plan — Requisitions ↔ financialtooliag

**Status:** 🟡 Partial · **Owner:** Backend (`inspired-api`) · **Source of truth for:** how requisitions raised in `inspired` get reflected in, and reconciled against, the external ERP at [financialtooliag.vercel.app](https://financialtooliag.vercel.app/)
**Last updated:** 2026-08-02

---

## 0. What this document is

`inspired` (Flutter) lets employees raise **finance requisitions** and **store
requests**, which move through an internal approval chain inside `inspired-api`.
Separately, Inspire Africa Group runs an ERP — the "financial tool" at
`financialtooliag.vercel.app` — which is **not our codebase**: no repo access,
no API docs, no credentials as of this writing.

The requirement: requisitions raised in the app need to be reflected in the ERP,
and the ERP's own status on those requisitions needs to flow back into the app.
This document is the plan for that integration — what's decided, what's open,
and what's needed from the ERP owners before it can be built.

This plan was reconstructed on 2026-08-02 from a conversation whose original
notes weren't saved anywhere durable — treat the "Decided" section below as
confirmed, and everything in "Open questions" as still needing sign-off from
whoever owns the ERP side.

## 1. Current state (what exists today, in `inspired`)

Two requisition flows already exist client-side, each with its own internal
approval chain, entirely within `inspired-api` — the ERP is not involved yet:

| Flow | Screen | Status chain (observed in code) |
|---|---|---|
| Finance requisition | `lib/features/requests/finance_requisition_screen.dart` | `pending_hod` → `pending_finance` → `approved` / `rejected` |
| Store request | `lib/features/requests/store_request_screen.dart` | `pending_verification` → `pending_hod` → `approved` / `rejected` |

Both post/read through `inspired-api` (`POST /api/requisitions/finance`,
`GET /api/requisitions/finance`, and the store equivalent) — the Flutter app
never talks to anything external directly. Neither flow is yet documented in
`docs/03-design/api-specification.md` or `docs/03-design/ERD.md` (the ERD only
lists `ItemRequest` / `StoreItem` as a Phase 3 placeholder) — that's a
pre-existing gap, not something this plan is scoping in, but it means the
request/response shapes above are read from the client code, not a contract.

## 2. Decided

- **`inspired-api` is the integration point**, not the Flutter app and not
  `iams-dash` directly. The app already only talks to `inspired-api`; that
  boundary doesn't change. `inspired-api` becomes responsible for both calling
  out to the ERP and receiving/pulling ERP status.
- **Sync is bidirectional**:
  1. **Push** — requisition data created/updated in `inspired-api` needs to
     reach the ERP.
  2. **Pull** — status changes made on the ERP side (approval, rejection,
     payment, whatever the ERP's own workflow does) need to come back into
     `inspired-api` and be visible in the app.
  3. **Scheduled reconciliation** — a batch job on a timer, independent of the
     real-time push/pull, to catch drift (missed webhook, failed push, ERP
     downtime) rather than relying on real-time calls alone.

## 3. Open questions (blocking implementation — need ERP-side input)

Nothing about the ERP's actual API contract is known yet. Before any code
gets written against it, someone needs to get the following from whoever owns
`financialtooliag`:

- **API shape** — REST? What base URL/environment (does staging exist,
  separate from the production `financialtooliag.vercel.app`)? Request/response
  schemas for creating and updating a requisition-equivalent record.
- **Auth** — how does `inspired-api` authenticate to the ERP (API key, OAuth
  client credentials, mutual cert)? Is there a service-account concept on
  their side?
- **Push trigger granularity** — does the ERP want a call on *every* internal
  status transition (submit, HOD approval, finance approval), or only once,
  at final internal approval, with the full record? Pushing on submit means
  the ERP sees not-yet-approved requisitions; that may or may not be wanted.
- **Pull mechanism** — can the ERP send us a **webhook** on status change, or
  does `inspired-api` need to **poll** it? If webhook: what's the payload,
  is it signed, is delivery retried on our end being down?
- **Field mapping** — our requisitions have `particulars` / `qty` / `unit_cost`
  / `amount_in_words` / department / requester. What does the ERP's schema
  expect, and is there a natural key to correlate "our requisition" with
  "their record" (we'll need to store their ID against ours either way)?
- **Idempotency & retries** — if a push fails or times out, can it be safely
  retried (does the ERP dedupe on our ID), or does retrying risk creating
  duplicates?
- **Reconciliation cadence** — how far can our state and their state drift
  before it matters? Determines whether the batch job runs hourly, nightly,
  etc.

Until these are answered, "Nothing yet" is the honest state of ERP-side
access — this section is the checklist to close that gap, not a spec to build
against.

## 4. Proposed shape (subject to the answers above)

```
 inspired (Flutter)
        │  POST /api/requisitions/finance
        │  GET  /api/requisitions/finance
        ▼
 inspired-api (Django) ── owns the internal approval chain ──┐
        │                                                     │
        │  on final internal approval: push requisition  ────┤
        │  ◄──────────────  webhook or poll: ERP status  ────┤
        │                                                     │
        │  scheduled job: reconcile drift, retry failed pushes│
        ▼                                                     ▼
   erp_sync_status / erp_reference_id                financialtooliag.vercel.app
   fields added to the requisition record             (external ERP — no code access)
```

- Add `erp_reference_id` and `erp_sync_status` (`not_synced` / `synced` /
  `sync_failed`) to the requisition models in `inspired-api`, so the app can
  surface sync state and a failed push can be retried without guessing.
- `iams-dash` is a read surface for this data (dashboards), not a party to the
  sync itself, unless a future requirement says otherwise.

## 5. Next steps

1. Get an API contract (or a contact who can produce one) from whoever owns
   `financialtooliag` — this unblocks everything else in §3.
2. Once the contract exists, write it up in
   `docs/03-design/api-specification.md` (or a dedicated ERD entry) as the
   actual source of truth, superseding the "Proposed shape" above.
3. Backfill the missing finance-requisition / store-request entities into
   `docs/03-design/ERD.md` and `docs/03-design/rbac-matrix.md` while touching
   this area — they predate this plan and were never documented.
