# PostgreSQL database objects

The application requires PostgreSQL; no runtime data is saved to JSON files. Migrations are embedded in the compiled assembly, applied in order under a transaction lock and checked by checksum on subsequent runs. Editing an already applied migration is rejected; add a new numbered migration instead.

The expanded database now contains 80 tables across business and operations schemas. The [enterprise guide](ENTERPRISE_DATABASE.md) describes the additional modules, procedures, security and schedules; the [installed catalogue](DATABASE_OBJECTS.md) lists every object and column. The table below summarises the original core.

## Relational tables

| Area | Tables |
| --- | --- |
| Identity and reference data | `roles`, `users`, `departments`, `wards`, `system_settings` |
| Patient flow | `patients`, `doctors`, `appointments`, `beds`, `admissions`, `bed_assignments` |
| Pharmacy | `medicine_batches`, `prescriptions`, `stock_movements` |
| Finance | `bills`, `bill_lines`, `payments` |
| Documentation | `notes` |
| Audit and reliability | `activity_log`, `row_history`, `idempotency_keys`, `idempotency_hash_keys`, `schema_versions` |
| Security | `sessions`, `auth_attempts`, `data_protection_keys` |
| Notifications | `notifications` |

`medicine_batches` represents a medicine/strength and its batch, expiry, reorder level and price. Bills and receipts retain their original decimal amounts. Doctor schedules use daily local shift times; appointment instants are normalized to UTC. The hospital timezone setting defines validation and calendar boundaries. The frontend renders instants in the browser timezone.

## Views

- `invoice_balances`: independent line and payment aggregates, avoiding multiplication when both have several rows.
- `bed_occupancy`: staffed, occupied and available beds and occupancy percentage by ward.
- `stock_alerts`: low-stock, expired and near-expiry batch conditions.

## Integrity

Foreign keys link visits, occupancy, prescriptions, stock and financial records. Partial unique indexes permit only one active admission per patient and bed, and only one open bed-assignment interval per admission and bed. Check constraints protect supported statuses, date ranges, shift ordering and positive monetary/quantity values.

Trigger functions preserve assignment history and row-history metadata. Deferred consistency triggers validate the final committed state, permitting multi-step transactions such as discharge/release and dispensing/charging without allowing inconsistent committed results. Appointment checks and all application mutations use the same advisory transaction lock. This favors correctness at the present scale; it does not claim high concurrent-write throughput.

Stock quantity must equal the sum of movements for each batch. During legacy import, an explicit opening-balance movement reconciles the imported quantity against any prior movement ledger. A historical opening balance is identified as an import baseline; it does not reconstruct missing historical receipts.

## Write behavior

The web service calls `hf_api.execute` with an authenticated actor, action, JSON payload, UUID retry key and keyed request fingerprint. Native database procedures validate and apply linked relational changes in one transaction. The operational read snapshot is separate from this command path. The application does not delete domain records. Financial corrections append new negative lines rather than overwriting posted charges. Database-generated history records contain changed field names, not their values.

Successful workflow audit events commit with the data. Request starts and completions commit separately so failed workflow transactions still have durable failure evidence. Client page and export telemetry uses a fixed allowlist. Idempotency requests are scoped to an authenticated user and protect mutation retries. Password-containing input uses a keyed HMAC for its idempotency fingerprint; the random HMAC key is stored in the database, not written to logs.

## Privilege model

On the currently configured local server, `postgres` applies migrations. The original dedicated cluster used `hospitalflow_owner`. `hospitalflow_app` has schema usage, necessary table reads, domain inserts/updates, session/throttle cleanup and sequence access. It has no schema creation/ownership privileges and no ledger updates/deletes. Row-history and bed-history triggers execute tightly scoped owner functions with a fixed search path. Production must supply only the runtime credential to the web process.

The SQL grant script targets the local role name `hospitalflow_app`. For managed environments use the corresponding separately provisioned runtime role and adjust that script before deployment. Do not grant application users database credentials.

## Legacy import

The installed database imported the existing JSON state once, preserving IDs, relationships, password hashes, financial lines, payments and old audit timestamps. The original file and a separate owner-readable backup are retained for recovery; they are no longer application storage. Imports refuse destinations that already contain users. If an import violates an integrity constraint, the transaction rolls back without partially importing records.

## Technical references

The mapping and transaction implementation follows [Npgsql basic usage](https://www.npgsql.org/doc/basic-usage.html). Timestamp values are normalized to UTC before binding, in accordance with [Npgsql date/time handling](https://www.npgsql.org/doc/types/datetime.html). Database invariants use [PostgreSQL constraints](https://www.postgresql.org/docs/17/ddl-constraints.html) and transactional triggers.

## Person profiles and role-prefixed IDs

Migration 012 adds persisted `registration_id` columns to patients/providers/accounts, patient email/address/emergency-contact fields and `person_profiles` for staff DOB/mobile/department/job information. Public IDs use P/D/N/V/A/DEV prefixes; internal keys and existing history are preserved. Doctor/Nurse become explicit roles and Volunteer remains non-clinical. See [people and registration](PEOPLE_AND_ROLES.md).
