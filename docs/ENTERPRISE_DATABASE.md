# HospitalFlow enterprise database foundation

The installed database is `hospitalflow` on `localhost:5432`, on the existing PostgreSQL server. Existing business records were preserved and compared against a protected pre-migration snapshot. No other database was migrated. Ten ordered migrations are recorded with SHA-256 checksums; applied migrations must never be edited.

The installed catalogue contains **68 tables, 23 procedures, 37 functions, 92 row triggers, 2 event triggers, 14 views, 1 materialized view, 4 row-security policies, 130 indexes, 5 sequences and 2 enum types**. See [every object, column, constraint and routine signature](DATABASE_OBJECTS.md).

## Find inventory in pgAdmin

Refresh **Databases → hospitalflow → Schemas**. Expand `hospitalflow → Tables → medicine_batches` for inventory and `stock_movements` for the stock ledger. Use **View/Edit Data → All Rows** to inspect records. Other schemas are visible alongside `hospitalflow`; procedures and functions appear in their own folders.

```sql
SELECT * FROM hospitalflow.stock_alerts;
SELECT * FROM hf_ops.object_inventory ORDER BY object_type, object_name;
SELECT * FROM hf_ops.validate_database();
```

Use the catalogue for precise column names before writing custom queries. Do not manually change clinical, stock or financial records to bypass the command procedures.

## Schemas and PostgreSQL equivalents

| Schema | Purpose |
| --- | --- |
| `hospitalflow` | Clinical operations, identity, pharmacy, finance, sessions and audit |
| `hf_api` | Grouped business commands and procedures; the package equivalent |
| `hf_security` | Actor/role validation and patient-access helpers |
| `hf_reporting` | Read-only aliases and aggregate reporting; view-based synonym equivalents |
| `hf_ops` | Fixed maintenance schedules, integrity checks, backup/recovery evidence and schema-change history |

PostgreSQL schemas group routines rather than Oracle-style packages. Read-only views provide named access paths rather than native Oracle synonyms. The implementation uses actual PostgreSQL objects, without claiming unsupported object types.

## Module coverage

| Area | Database support |
| --- | --- |
| Patient identity | Patients, contacts, consent history, scoped access grants, duplicate checks |
| Workforce and scheduling | Doctors, staff, departments, ward mappings, provider sessions/absences, appointment overlap and state checks |
| Admission and discharge | Beds, assignments, encounters, transfers, admission events, discharge tasks, follow-ups |
| Clinical operations | Notes, prescriptions, orders, prescription authors and dispensing links |
| Pharmacy and procurement | Batches, suppliers, purchase orders, partial goods receipts, holds, reservations, stock movements and reconciliation |
| Finance | Bills, immutable lines/payments, effective service prices, charge context, credit adjustments and bounded payment reversals |
| Integration | ID-only transactional outbox, leases, retry state and token-checked completion |
| Governance | Users, roles, sessions, consent, activity events, row history and DDL event audit |
| Operations | Due jobs, run history, worker heartbeats, integrity findings, snapshots and recovery evidence |

Extended commands are implemented and tested at the database layer and are exposed through Admin/Developer Operations controls forms, with bounded record lists. A payment reversal records a local accounting correction; it does not issue a refund through an external payment provider. No external email/SMS or integration dispatcher is configured.

## Transaction and security contract

The web backend validates its persistent authenticated session, sets transaction-local `hospitalflow.actor_id`, and calls:

```sql
-- Parameters supplied by the trusted backend, within one transaction:
SELECT hf_api.execute(@action, @payload::jsonb, @key::uuid, @hash);
```

The gateway validates the active actor and allowed role, locks the workflow transaction, checks the per-actor retry key and keyed request fingerprint, then invokes the appropriate routine. Business changes, audit and idempotency evidence commit together. Conflicting retry payloads are rejected. Password hashing occurs in .NET before the command payload reaches SQL. The actor setting is a trusted-backend context, not cryptographic proof for arbitrary database clients; end users must never receive runtime database credentials.

Constraints and triggers enforce stock/ledger equality, reservation capacity, posted financial history, reversal limits, exclusive bed occupancy, admission history, appointment overlap, valid provider availability, price history and discharge prerequisites. Writes currently share an advisory lock; benchmark throughput before increasing deployment scale.

`hospitalflow_app` does not own the schema and cannot perform schema DDL or rewrite immutable ledgers. `hospitalflow_jobs` inherits only the fixed maintenance role, can execute allowlisted maintenance and read aggregate health, and cannot read clinical tables. Credentials are excluded from Git and stored in owner-readable local files. Production should use a secret manager and a separate backup operator identity.

Four row-security policies cover contacts, consents, follow-ups and clinical orders through patient/department access. Existing core operational snapshots remain broader and role-filtered. This is not complete hospital-wide row isolation; extend the query/access model before a deployment requiring stricter boundaries.

## Activity and audit

API starts/completions, rejected requests, authentication, page visits, exports and patient/invoice views are recorded. Business events commit with successful writes. Row triggers append record IDs, changed column names, actor/correlation, database session identity and transaction ID for new events. They avoid copying clinical text, passwords or contact values. Event triggers record schema changes. Historic imported events are retained without inventing missing metadata.

The runtime cannot update/delete activity, row history or posted ledgers. Database administrators retain administrative power; independent log retention is required for stronger tamper evidence. Direct SQL SELECT statements are not covered by row-change triggers. Retention policies are recorded but clinical/audit purges are disabled by default.

## Installed schedules

The approved macOS user launchd maintenance agent invokes `scripts/job_worker.py` every 60 seconds. It uses the restricted job credential in `.local/jobs/database.json` (owner-only, Git-ignored). The backup agent runs at **02:15 local system time**. These agents run while the Mac user is logged in. Production needs an always-on scheduler/service; invoke the same worker under a dedicated service identity with protected configuration.

| Job | Due interval |
| --- | --- |
| Operational alerts | 60 seconds |
| Expired-session cleanup | 1 hour |
| Integrity monitor | 15 minutes |
| Ward daily snapshot | 1 hour |
| Report cache | 15 minutes |
| Expired outbox lease recovery | 60 seconds |
| Backup freshness monitor | 24 hours |
| Planner statistics | 24 hours |

The scheduler uses locked due rows, fixed task names, bounded execution, run evidence and retry backoff. It does not accept arbitrary scheduled SQL. Neither pg_cron nor pgAgent is installed on this server; no shared-server restart or extension change was made.

```sh
python3 scripts/configure_jobs.py status
python3 scripts/job_worker.py
python3 scripts/verify_database.py
python3 scripts/database_report.py --objects
```

## Backup, restore and verification

A real custom-format backup was created and restored into a disposable password-protected cluster. SHA-256, restored constraints and integrity checks passed, and evidence is recorded in `hf_ops.backup_runs` and `hf_ops.restore_drills`. An earlier failed drill is also retained rather than erased. Local successful restore duration is evidence of this drill, not a production recovery-time guarantee.

```sh
python3 scripts/backup_database.py
python3 scripts/restore_drill.py
```

Dumps exclude owner/ACLs intentionally. After restoring into an empty recovery database, apply **both** `HospitalFlow/Database/grant_operations.sql` and `HospitalFlow/Database/grant_runtime.sql`, with correctly provisioned environment roles. Validate encryption-key certificates and isolated application access before a recovery cutover. Production still needs encrypted off-host backups, retention, WAL/PITR where required and measured recovery objectives.

The [schema-only installer](../HospitalFlow/Database/hospitalflow_schema.sql) is for a **new empty database**, not a script to rerun over this installation. Normal upgrades use the embedded migrations and `scripts/local_database.py migrate`. A fresh schema installation also requires application bootstrap, protected runtime/HMAC configuration and role grants as described in [deployment](DEPLOYMENT.md).

Verification completed: .NET build; disposable database/API/concurrency/security tests; native command acceptance tests; production certificate/startup checks; generated SQL installer tests; live migration checksum/integrity verification; preservation comparison; and a real backup restore. The live verification reports zero violations for all 13 error checks and all three operational evidence warnings.

This is an implemented database foundation, not certification of a hospital production deployment. Remaining deployment work includes hospital-specific access policies, MFA/recovery, load testing and pagination, independent audit retention, external integrations, monitored always-on infrastructure and institutional clinical/security review.
