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
| **Attendance — correct / resolve flag** | — | U *(own dept)* | U | U | — |
| **Employees** (roster) | — | R *(own dept)* | C, R, U | C, R, U, D | R |
| **Employee — assign role** | — | — | — | C/U | — |
| **Employee — reset password** | — | — | U | U | — |
| **Departments** | — | R | R | C, R, U, D | R |
| **Sites & Blocks** (geofences) | R *(assigned)* | R | R | **C, R, U, D** | R |
| **Audit log** (security events) | — | — | R | R, X | R |
| **App versions** | — | — | — | C, R, U | — |
| **Reports / exports** | — | X *(dept)* | X | X | X |
| **Leave requests** | C, R *(own)* | R, A *(own dept, stage 1)* | R, A *(stage 2)* | R, A | — |
| **Leave types & public holidays** | R | R | C, R, U, D | C, R, U, D | R |
| **Store requests** | C, R *(own)* | R, A *(own dept, stage 2)* | — | R, A | — |
| **Finance requisitions** | C, R *(own)* | R, A *(own dept, stage 1)* | — | R, A | — |
| **Tasks** | R, U *(assigned to me)* | C, R, U, D *(own dept)* | — | C, R, U, D | — |
| **Notifications (inbox)** | R, U *(own)* | R, U *(own)* | R, U *(own)* | R, U *(own)* | R, U *(own)* |

Notes:
- **Only the Admin** creates/edits **geofences** and **assigns roles** — these
  are access-control and infrastructure decisions.
- **HR and Admin** both onboard employees and reset passwords; only Admin sets a
  user's *role*.
- **Revised**: HOD may now create/correct attendance records for their own
  department (was originally read-only) — they're best placed to know their
  own team actually showed up, and delete stays Admin/HR-only as a guardrail.
- **Audit log records security events only** (logins, role changes, exports,
  geofence edits) — never normal employee movement.
- Devices/FCM tokens are **not** an admin-facing resource (no surveillance UI).
- **Requests are private to the people on the form** (2026-09-18): a leave,
  store or finance request is visible only to the requester, the HOD of the
  requester's department, the department it is addressed to (HR for leave,
  Stores for store requests, Finance for requisitions) and System Admin. Exec
  does not see request lists; HR does not see store/finance requests. Each
  party is notified (inbox + push) when a request reaches their stage, and
  can download the filled-in form as a PDF.
- **Finance requisition documents** (2026-09-26): the requester may attach up
  to 5 supporting documents when submitting, and add or remove them until the
  HOD decides; anyone who can see the requisition can open them, and the PDF
  carries them appended behind the form. **No one approves their own
  requisition** at either stage — a HOD's own goes to System Admin, a Finance
  clerk's own to another Finance member.
- **Leave types are data, not code** (`leave.LeaveType`): HR/Admin set the
  yearly entitlement, description and gender restriction. Defaults: annual 21,
  sick 14, maternity 60 (women), paternity 4 (men), unpaid/other 0. A type
  with a gender restriction is hidden from, and rejected for, anyone of the
  other gender — and for anyone whose `Employee.gender` is still unset.
- **Sign-in reminders** (08:45 and 09:00) are local alarms scheduled on the
  phone from `/api/attendance/me/reminder-plan`, so they fire with no signal;
  the plan skips Sundays, public holidays and approved leave, and today's
  alarms are cancelled on check-in.

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
