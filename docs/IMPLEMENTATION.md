# Implementation and research traceability

The selected title is **HospitalFlow: Intelligent Hospital Operations Management System**. Framework and database names are implementation details, not part of the title. The source report describes a proposed design; its claims are not evidence of deployment or completed research.

## Requirement mapping

| Report requirement | Implementation evidence | Remaining scope |
| --- | --- | --- |
| FR-01 patient identity | Patient registration, identifier, audited edits, duplicate check and linked journey | reviewed merges, emergency identity reconciliation |
| FR-02 scheduling | Provider hours, overlapping slot rejection and explicit status transitions | Database sessions and absences implemented; extended scheduling UI, reminders and override approval remain |
| FR-03 admission and beds | Atomic occupancy, transfer and discharge; cleaning and maintenance, bed creation and durable occupancy history | Accommodation constraints and richer ward configuration |
| FR-04 pharmacy | Clinician entry, batch expiry, stock receipts and dispense ledger | Database procurement, holds and reservations implemented; extended UI, recall and returns remain |
| FR-05 finance | Itemised decimal charges, partial payments and credit adjustments | Database price catalogues and local payment reversals implemented; extended UI, taxes, insurance and provider integrations remain |
| FR-06 dashboards and alerts | Stored-record metrics, defined occupancy and no-show denominators; live exception list | Database acknowledgements and daily snapshots implemented; delivery channels remain |
| FR-07 audit | Read/write/request/rejection events, record references and correlation; append-only database ledgers | Independent retention and external audit monitoring |
| FR-08 export | Appointments, bed and billing CSVs, subject to accessible state, with export audit | Governed general-purpose imports |
| FR-09 interoperability | No integration endpoints claimed | Approved FHIR mappings and conformance tests |
| FR-10 prediction | No predictive model enabled | Governance, representative data and evaluation |

## HTTP contract

All endpoints are same-origin. POST requests must include `Content-Type: application/json` and `X-HospitalFlow: 1`. Mutation actions also require an `Idempotency-Key` UUID header. Cookie authentication is required except for login and health. Cross-origin access is not enabled.

- `POST /api/login` takes `email` and `password` and creates an HttpOnly session cookie.
- `POST /api/logout` ends the session.
- `GET /api/me` returns the signed-in name, role and storage mode.
- `GET /api/state` returns a role-filtered snapshot of operational records.
- `GET /api/health` returns process health and storage mode, with no patient records.
- `GET /api/activity` provides paginated activity history scoped to the caller.
- `POST /api/activity` records allowlisted page visits and exports.
- `GET /api/notifications` reads durable operational notifications.
- `POST /api/account/password` changes a password and revokes all sessions.
- `POST /api/actions/{action}` validates and commits one complete workflow transaction.

| Action | Payload fields |
| --- | --- |
| patient | name, dob (ISO date), sex, phone |
| patient-update | id, name, dob, sex, phone |
| bed | id, ward, category |
| user-status | id, active |
| doctor | name, department, start and end (HH:mm) |
| appointment | patientId, doctorId, at (ISO timestamp with offset), type |
| appointment-status | id, status |
| admit | patientId, bedId, reason |
| transfer | id (admission), bedId, reason |
| discharge | id (admission), summary |
| bed-status | id, status |
| medicine | name, batch, expiry, quantity, reorder, price |
| stock | id (medicine), quantity, reason |
| prescription | patientId, medicineId, quantity, instructions |
| dispense | id (prescription) |
| bill | patientId, description, amount |
| payment | id (bill), amount, method |
| adjustment | id (bill), amount, reason |
| note | patientId, text |
| user | name, email, role, password |

Business-rule failures return 409 with a safe `error` and request `correlationId`. Authentication and authorization return 401 and 403. Invalid JSON returns 400. Workflows generate internal identifiers. Input values are validated server-side and rendered using escaped text in the browser.

## Transaction behavior

Every successful workflow commits relational row changes, business audit and the retry key in one transaction. PostgreSQL foreign keys, checks, partial unique indexes and triggers independently validate the final state. No JSON-file or whole-document runtime storage remains. Rejected operations roll back; separate request-start/completion events preserve rejection evidence.

Dispensing changes stock and prescription status, adds a movement and creates an invoice together. Transfers close a historical bed assignment and open the destination interval. Discharge requires settled bills and completed prescriptions before releasing the bed to cleaning. Posted charge and payment records are immutable; credit adjustments add lines.

The browser and API use idempotency keys, backed by a PostgreSQL ledger and keyed request fingerprints, so retries work across instances. Database sessions, throttling, alerts and encryption keys are persistent as well. Write transactions currently use an application-wide advisory lock, and operational views use a role-filtered snapshot. These favor consistency at this scale; high-volume deployment needs measured load testing and narrower queries.

## Research evaluation

Use synthetic records for development. Functional API tests provide software correctness evidence only. Interview findings, user task completion measures, response-time benchmarks, clinical safety review and before/after operational comparisons still require authorized collection and supervisor-approved methods. No implementation screen presents efficiency improvement percentages or clinical efficacy claims.

## Database-first extension

Ten migrations install the expanded command API, procurement, service prices, payment reversals, consent/contact records, patient access grants, provider sessions/absences, discharge tasks, follow-ups and an integration outbox. Existing web mutation routes now call `hf_api.execute`; they no longer persist differences from in-memory workflow mutations. The extended database commands are tested and exposed through Admin/Developer Operations controls. See the [enterprise guide](ENTERPRISE_DATABASE.md) and [full catalogue](DATABASE_OBJECTS.md).
