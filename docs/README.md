# IAMS / "Inspired" — Project Documentation Index

Inspire Africa Group — Integrated Attendance Management System.
Three apps, one platform: Flutter (`inspired`), Next.js dashboards (`iams-dash`),
Django backend (`inspired-api`).

This folder holds the **Software Development Life Cycle (SDLC) documents** — the
plans, diagrams, and technical analyses that exist *around* the code. The
governing decisions live in [`SPRINT_0.md`](./SPRINT_0.md); the documents below
factor those decisions into single-purpose artifacts.

## Status legend

- ✅ **Live** — written, current, code is built against it. Keep in sync.
- 🟡 **Partial** — real content exists but incomplete; fill as work proceeds.
- 📄 **Template** — structure only; belongs to a later stage. Fill at the right time.

## Document map

### 00 — Product / Inception
| Doc | Status |
|---|---|
| [Vision & Scope](./00-product/vision-and-scope.md) | 📄 |
| [Product Requirements (PRD)](./00-product/prd.md) | 📄 |
| [Personas & Roles](./00-product/personas.md) | 🟡 |

### 01 — Requirements
| Doc | Status |
|---|---|
| [Software Requirements Spec (SRS)](./01-requirements/srs.md) | 📄 |
| [Non-Functional Requirements](./01-requirements/nfr.md) | 📄 |
| [User-Story Backlog & Traceability](./01-requirements/backlog-traceability.md) | 📄 |

### 02 — Architecture
| Doc | Status |
|---|---|
| [System Architecture & C4](./02-architecture/system-architecture.md) | 📄 |
| [Architecture Decision Records](./02-architecture/adr/) | 🟡 |
| &nbsp;&nbsp;↳ [ADR-0001 — Migrate backend to Supabase](./02-architecture/adr/0001-migrate-backend-to-supabase.md) | ✅ |

### 03 — Design (the build contracts — written first)
| Doc | Status |
|---|---|
| [Entity-Relationship Diagram (ERD)](./03-design/ERD.md) | ✅ |
| [Data Dictionary](./03-design/data-dictionary.md) | 🟡 |
| [API Specification](./03-design/api-specification.md) | ✅ |
| [RBAC / Authorization Matrix](./03-design/rbac-matrix.md) | ✅ |
| [Sequence Diagrams](./03-design/sequence-diagrams.md) | ✅ |
| [UI/UX Spec](./03-design/ui-ux-spec.md) | 📄 |

### 04 — Security & Privacy
| Doc | Status |
|---|---|
| [Threat Model (STRIDE)](./04-security-privacy/threat-model.md) | 📄 |
| [Privacy Impact Assessment](./04-security-privacy/privacy-impact-assessment.md) | 🟡 |
| [Data Retention & Classification](./04-security-privacy/data-retention.md) | 📄 |

### 05 — Delivery
| Doc | Status |
|---|---|
| [Supabase Migration Plan](./05-delivery/supabase-migration-plan.md) | 🟡 |
| [Test Plan & Strategy](./05-delivery/test-plan.md) | 📄 |
| [CI/CD & Deployment Design](./05-delivery/cicd-deployment.md) | 📄 |
| [Release Management & Versioning](./05-delivery/release-management.md) | 📄 |

### 06 — Operations
| Doc | Status |
|---|---|
| [Ops Runbook](./06-operations/runbook.md) | 📄 |
| [Deploy to DigitalOcean](./06-operations/deploy-digitalocean.md) | ✅ |
| [Stable local access via Tailscale](./06-operations/local-access-tailscale.md) | ✅ |
| [Incident Response](./06-operations/incident-response.md) | 📄 |
| [Backup & Restore](./06-operations/backup-restore.md) | 📄 |
| [SLO/SLA & Monitoring](./06-operations/slo-monitoring.md) | 📄 |

## How these relate

```
SPRINT_0.md  (decisions, the "why now")
   │
   ├── factored into ──> 00 Product / 01 Requirements   (the "what & for whom")
   │
   ├── factored into ──> 02 Architecture                (the "shape")
   │
   └── factored into ──> 03 Design                      (the "contracts" code is built against)
                              │
                              └── constrained by ──> 04 Security/Privacy
                              └── delivered via  ──> 05 Delivery / 06 Operations
```

Rule of thumb: **a fact lives in exactly one document.** Everything else links to it.
