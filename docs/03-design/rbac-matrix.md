# RBAC / Authorization Matrix

**Status:** ✅ Live · **Owner:** Backend / Security · **Source of truth for:** who can do what — role definitions, the permission matrix, onboarding/identity rules, and the employee profile.
**Last updated:** 2026-06-24

---

## 0. What this document is

Role-Based Access Control (RBAC) answers one question for every action in the
system: *"is this person allowed to do this?"* It does that by giving each person
a **role**, and defining — once, here — what each role may do to each **resource**.
Code then enforces it; it does not re-decide it.

This is the contract the backend permission checks, the dashboard route guards,
and the mobile app all build against. A capability that is not granted here does
not exist.

## 1. Roles

Five roles (the `Role` enum on `Employee`). Each has a **scope** — the slice of
data it can see and act on.

| Role | `code` | Scope | In one line |
|---|---|---|---|
| Employee | `employee` | **Self only** | Checks in/out, completes own profile. Mobile app. |
| Head of Department | `hod` | **Own department** | Sees their team's attendance, approves dept requests. |
| HR | `hr` | **Org-wide (people)** | Onboards & manages people, leave, records, reports. |
| System Admin | `admin` | **Org-wide (system)** | Configures sites/geofences, users & roles, audit. The super-user. |
| Executive / CEO | `exec` | **Org-wide (read)** | Cross-department analytics, read-only. |

**System Admin vs HR** is the key split: HR manages *people*; Admin configures
the *system* (geofences, roles, security). They overlap on user management but
the Admin owns access control and infrastructure.

## 2. Resources & actions

Actions: **C**reate · **R**ead · **U**pdate · **D**elete · **A**pprove · **X** (export).

| Resource | Employee | HOD | HR | Admin | Exec |
|---|---|---|---|---|---|
| **Own profile** | R, U | R, U | R, U | R, U | R, U |
| **Own attendance** (check-in/out) | C, R | C, R | C, R | C, R | C, R |
| **Attendance — all** | — | R *(own dept)* | R (org) | R (org) | R (org) |
| **Attendance — correct / resolve flag** | — | — | U | U | — |
| **Employees** (roster) | — | R *(own dept)* | C, R, U | C, R, U, D | R |
| **Employee — assign role** | — | — | — | C/U | — |
| **Employee — reset password** | — | — | U | U | — |
| **Departments** | — | R | R | C, R, U, D | R |
| **Sites & Blocks** (geofences) | R *(assigned)* | R | R | **C, R, U, D** | R |
| **Audit log** (security events) | — | — | R | R, X | R |
| **App versions** | — | — | — | C, R, U | — |
| **Reports / exports** | — | X *(dept)* | X | X | X |

Notes:
- **Only the Admin** creates/edits **geofences** and **assigns roles** — these
  are access-control and infrastructure decisions.
- **HR and Admin** both onboard employees and reset passwords; only Admin sets a
  user's *role*.
- **Audit log records security events only** (logins, role changes, exports,
  geofence edits) — never normal employee movement.
- Devices/FCM tokens are **not** an admin-facing resource (no surveillance UI).

## 3. Identity & onboarding

The admin/HR has **names + emails** — the system manufactures the rest.

**Auto-generated employee ID.** On account creation the system assigns
`{DEPT_CODE}-{NNN}` (zero-padded, sequential within the department), e.g.
`PROD-001`, `IT-001`, `IT-002`. The ID is stable and unique; the human never
types it.

**Bulk onboarding.** Admin/HR creates a department, then **bulk-uploads** its
people (CSV or pasted `full_name, email[, role]`). For each row the system:
1. generates the employee ID,
2. sets the department (and role, default `employee`),
3. sets a **preset password** (random or shared) and `must_change_password = true`,
4. emails/【hands over】the credentials.

**First login.** The employee signs in with the preset password, is forced to
change it, then is prompted to **complete their profile** (§4).

## 4. Employee profile (what HR needs to know)

Captured once, owned partly by the employee (self-service) and partly by HR/Admin.

| Field group | Fields | Edited by |
|---|---|---|
| **Identity** | full name, preferred name, photo, date of birth, gender, national ID (NIN) | Employee (HR verifies) |
| **Contact** | phone, alternate phone, email (login), home address | Employee |
| **Next of kin** | name, relationship, phone | Employee |
| **Employment** | employee ID, department, role, job title, employment type, start date, home site | **HR / Admin only** |
| **Status** | active, must_change_password, password_changed_at | System / Admin |

The employee can edit Identity/Contact/Next-of-kin; **Employment fields are
read-only to them** (only HR/Admin change department, role, job title). This goes
on a new `EmployeeProfile` (1:1 with `Employee`) so the core auth model stays lean.

## 5. Geofence administration (no field visit required)

The Admin manages Sites & Blocks **from the dashboard** — not by walking the site
with a phone:
- An interactive **map**: click to drop the centre point (sets lat/lng), drag a
  handle (or type metres) to set the radius, optionally add allowed WiFi BSSIDs.
- This replaces the manual coordinate-setting we've been doing in the database.
- A field-captured GPS point (from the mobile app) remains an *option* for
  precision, but is no longer required.

## 6. Enforcement

- Authoritative checks live **server-side** (DRF permission classes keyed on the
  JWT `role` + department), never only in the UI.
- The dashboard route-guards and the mobile app mirror these for UX, but the API
  is the gate.
- Scope is applied in the queryset: HOD endpoints filter to `request.user.department`;
  org-wide roles see all; employees see only themselves.

---

*Related: [ERD](./ERD.md) (the `Employee` / `EmployeeProfile` / `Site` / `Block`
shapes), [API Specification](./api-specification.md) (the endpoints that enforce
this).*
