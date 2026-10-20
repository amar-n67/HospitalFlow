# Project structure and data storage

HospitalFlow uses PostgreSQL as the source of truth for hospital and patient records. The browser calls authenticated `/api/…` endpoints; C# reads relational tables and invokes parameterized, transactional database commands. No operational record is saved in browser storage or a JSON data file.

## Source layout

```text
HospitalFlow/
  Program.cs                      Application startup, middleware and core routes
  Core/                           Shared domain records and validation exceptions
  Features/
    Accounts/                     Authentication, roles, preferences and onboarding
    Appointments/                 Booking, payment and staff availability endpoints
    Clinical/                     Care pathway and medication endpoints
    Documents/                    Authorized printable/downloadable records
    Hospitals/                    Hospital membership, network and referrals
    Operations/                   Enterprise operations and staff workspaces
    Patients/                     Patient portal and patient account provisioning
    People/                       Staff and patient registration/profile management
  Infrastructure/
    Messaging/                    Database-queued email and SMS delivery workers
    Persistence/                  Relational Store, transactions and initialization
    Seeding/                      Explicit development-only database bootstrap fixtures
  Database/
    Migrations/                   Immutable, ordered SQL migrations
    DbSecurity.cs                 PostgreSQL session tickets and key repository
    RowMap.cs                     Parameterized relational mapping
    grant_runtime.sql             Restricted application database privileges
    grant_operations.sql          Restricted maintenance database privileges
    hospitalflow_schema.sql       Generated installer for an empty database
  Properties/                     Local launch profiles (application port 5136)
  wwwroot/
    index.html                    Application shell and ordered script references
    css/app.css                   Shared styles and themes
    js/core/                      Startup/API client, dialogs, validation and theme
    js/features/                  Feature pages and interaction handlers
scripts/                          Database setup, maintenance, reporting and recovery
tests/                            Isolated integration and frontend verification
docs/                             Feature, deployment and database documentation
```

The C# feature files are compiled automatically by the SDK; moving a file does not change its type or route. Frontend scripts retain their existing load order. `Program.cs` is the entry point. This organization does not change SQL migration resource names or applied checksums.

## What is persisted

| Information | Storage and behavior |
|---|---|
| Patients, employees, hospital membership and roles | PostgreSQL relational tables, with hospital-scoped authorization |
| Appointments, test-payment evidence, prescriptions, admissions, beds, observations and discharge reviews | PostgreSQL; successful workflow changes commit before the browser reports success |
| Pharmacy inventory, dispensing, invoices, charges and receipts | PostgreSQL with immutable ledgers and database integrity rules |
| Attendance, leave, assignments, referrals and timelines | PostgreSQL; pages reload their authorized records from API queries |
| Audit history, sessions, protection keys and retry fingerprints | PostgreSQL |
| Signed-in Default/Dark theme | `user_preferences`; loaded by `/api/me`, saved by `/api/account/theme`; a failed save restores the last confirmed theme |
| Email and SMS invitations | Protected database queues; private local delivery files remain enabled as previously requested |
| Age, totals, charts and display labels | Derived from authorized database values; age is calculated from date of birth and the current date |
| Search text, open dialogs, unsaved forms and anonymous theme | Temporary page memory; not saved as business records |

Frontend workspace reloads publish the new snapshot only after all required reads succeed. A failed reload does not replace a previously loaded workspace with partially fetched records. There is no offline data store or fabricated-data fallback. Saved themes do not use browser localStorage or sessionStorage.

## Seed data and local files

`Infrastructure/Seeding/DemoData.cs` is retained because disposable tests and explicit development database initialization need fixtures. It is only called during migration/bootstrap of an empty database when development seeding is enabled. Runtime pages read the imported relational rows, not this file. Existing demonstration people remain in PostgreSQL.

The obsolete `App_Data/hospitalflow.json` snapshot has been moved to the private, Git-ignored `.local/archive/legacy-json/` directory. The unused in-memory `Workflows` command engine was removed. OS metadata and Python bytecode caches were removed; future caches remain ignored.

`.local/` and `appsettings.Local.json` contain private configuration, backups and delivery artifacts. They must remain outside Git, Docker build context and published output. Do not delete them as general cleanup. The project excludes local settings and `App_Data` from publish. `bin/` and `obj/` are SDK-generated and ignored; they are needed by the current build/run workflow and can be regenerated.

## Verification

Run from the repository root:

```sh
dotnet build HospitalFlow --no-restore
node tests/frontend_workspaces.cjs
node tests/frontend_persistence.cjs
python3 tests/postgres.py
```

The PostgreSQL suite uses a disposable cluster, exercises persisted workflows and verifies sessions and payment idempotency across process restarts. It does not reset the installed database. Static assets are checked through the running test application after layout changes.
