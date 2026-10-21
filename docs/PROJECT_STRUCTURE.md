# Project structure and data storage

HospitalFlow uses PostgreSQL as the source of truth for hospital and patient records. The browser calls authenticated `/api/…` endpoints; C# reads relational tables and invokes parameterized, transactional database commands. No operational record is saved in browser storage or a JSON data file.

## Source layout

```text
HospitalFlow/                       Repository / application root
  HospitalFlow.sln                 Open this solution in an IDE
  HospitalFlow.csproj              .NET project: run/build from this directory
  Program.cs                      Startup, security middleware and endpoint registration
  Controllers/                    HTTP API endpoint groups
    ApplicationEndpoints.cs       Login, session, state and core commands
    AccountEndpoints.cs           Signup, verification, recovery and access management
    BookingEndpoints.cs           Appointment booking and staff leave/attendance
    CareFlowEndpoints.cs          Clinical care pathway
    EnterpriseFinanceEndpoints.cs Billing, calendar and version endpoints
    ...                           People, patients, documents, hospital network
  Models/                         Domain records and API/data transfer models
  Data/
    Store.cs                      PostgreSQL connection, transactions and initialization
    RowMap.cs                     Parameterized relational mapping
    DbSecurity.cs                 Database session tickets and key repository
    Seeding/DemoData.cs            Explicit development-only bootstrap fixtures
  Services/
    Accounts/                     Account and onboarding Store sections
    Appointments/                 Booking queries and commands
    Background/                   Automatic daily charge worker
    Documents/                    Printable document data and rendering
    Hospitals/                    Hospital membership, network and referrals
    Messaging/                    Database-queued email and SMS workers
    Patients/                     Patient portal and first-login Store sections
    People/                       Registration and profile Store sections
    Releases/                     Running-build release registration
    Workforce/                    Profile, work assignments and staff queries
  Helpers/                        Shared access and account-validation helpers
  Database/
    Migrations/                   Immutable, ordered SQL migrations
    grant_runtime.sql             Restricted application database privileges
    grant_operations.sql          Restricted maintenance database privileges
    hospitalflow_schema.sql       Generated empty-database installer
  Properties/launchSettings.json  HTTP/HTTPS development launch profiles: port 5136
  wwwroot/
    index.html                    Application shell
    css/app.css                   Styles and themes
    js/core/                      Startup/API client, dialogs, validation and theme
    js/features/                  Patient, staff, clinical and billing UI modules
  scripts/                        Database administration, backup and Git tools
  tests/                          Isolated integration and frontend checks
  docs/                           Feature, deployment and architecture guides
  .vscode/                        Build/run tasks and debugger configuration
  hospitalflow                    Executable development-command launcher
  VERSION / release.json          Commit-managed application version and history
  appsettings*.json               Environment configuration (local settings private)
  .local/                         Private settings, pickups and backups; excluded from Git
```

This layout follows the reference AmarShowsBook project's root-level `Controllers`, `Models`, `Data`, `Services`, `Helpers`, `Database` and `wwwroot` convention. HospitalFlow uses Minimal API endpoint groups in `Controllers`; it does not require a conversion to MVC or Razor. The current UI remains in `wwwroot`, so no empty `Views` folder or unused view framework is added.

`Program.cs` registers endpoint groups and security middleware. Controllers handle HTTP requests; `Services` contain feature operations implemented as sections of the shared PostgreSQL `Store`. Files named `Store.*.cs` are partial sections of that class, not separate dependency-injected service types. `Data` contains its connection and persistence foundation. `Models` hold data contracts, and `Helpers` hold shared access/validation rules. SQL business commands and constraints remain in `Database/Migrations`.

Routes, frontend asset URLs and SQL checksums are unchanged. The executable project was moved from the former nested `HospitalFlow/` folder to this repository root; supported scripts, tests, Docker build paths and local configuration moved with it. Applied SQL resource names remain `HospitalFlow.Database.Migrations.*`. Local email/SMS pickup directories still resolve to this repository's `.local/` directory.

See [Quick start](QUICK_START.md) for the supported commands. From the repository root, `dotnet run` and `./hospitalflow run` both launch the application. The launcher can also be invoked by absolute path from another directory.

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

`Data/Seeding/DemoData.cs` is retained because disposable tests and explicit development database initialization need fixtures. It is only called during migration/bootstrap of an empty database when development seeding is enabled. Runtime pages read the imported relational rows, not this file. Existing demonstration people remain in PostgreSQL.

The obsolete `App_Data/hospitalflow.json` snapshot has been moved to the private, Git-ignored `.local/archive/legacy-json/` directory. The unused in-memory `Workflows` command engine was removed. OS metadata and Python bytecode caches were removed; future caches remain ignored.

`.local/` and `appsettings.Local.json` contain private configuration, backups and delivery artifacts. They must remain outside Git, Docker build context and published output. Do not delete them as general cleanup. The project excludes local settings and `App_Data` from publish. `bin/` and `obj/` are SDK-generated and ignored; they are needed by the current build/run workflow and can be regenerated.

## Verification

Run from the repository root:

```sh
dotnet build HospitalFlow.csproj --no-restore
node tests/frontend_workspaces.cjs
node tests/frontend_persistence.cjs
python3 tests/version_release.py
python3 tests/postgres.py
```

The PostgreSQL suite uses a disposable cluster, exercises persisted workflows and verifies sessions and payment idempotency across process restarts. It does not reset the installed database. Static assets are checked through the running test application after layout changes.

`VERSION`, `release.json` and `.githooks/pre-commit` maintain build/release identity. The version manifest is included in output; the running release history is stored in PostgreSQL. See [billing, calendar and versioning](BILLING_CALENDAR_VERSIONING.md).
