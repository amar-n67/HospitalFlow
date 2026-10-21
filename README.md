# HospitalFlow

**Intelligent Hospital Operations Management System**

HospitalFlow is an ASP.NET Core 10 application backed exclusively by PostgreSQL. Patients, appointments, wards, beds, admissions, prescriptions, stock movements, invoices, payments, users, sessions, alerts and activity history are stored in relational database tables. There is no JSON-file or whole-document runtime storage fallback.

## Quick start

From the repository root:

```sh
./hospitalflow run
```

Or use the standard .NET command:

```sh
dotnet run --launch-profile http
```

Open **http://localhost:5136**. Stop with **Ctrl+C**. The shared PostgreSQL server stays running.

The project now follows the reference AmarShowsBook layout: root-level **Controllers, Models, Data, Services, Helpers, Database and wwwroot**. Open `HospitalFlow.sln` in your IDE. See [Quick start and commands](docs/QUICK_START.md) and [Project structure](docs/PROJECT_STRUCTURE.md).

## Current local installation

The application uses a dedicated database on your existing PostgreSQL 17 server:

| Setting | Value |
| --- | --- |
| Host | `localhost` |
| Port | `5432` |
| Database | `hospitalflow` |
| Application role | `hospitalflow_app` |
| Database administrator / migration account | `postgres` |
| Browser URL | http://localhost:5136 |

Local database credentials are in owner-readable files excluded from Git: `appsettings.Local.json` contains the runtime connection, and `.local/database.json` contains local provisioning credentials. Do not commit or share these files. The supplied `postgres` account provisions and migrates the database; the web application uses the separate restricted `hospitalflow_app` account. In pgAdmin refresh **Databases → hospitalflow → Schemas → hospitalflow → Tables**. Inventory is in `medicine_batches`; transaction history is in `stock_movements`.

Existing local records were imported, preserving user IDs and password hashes. The original JSON file is no longer read or written by the application. A pre-import backup was saved under `.local/legacy-backup-*.json`. The imported dataset includes demonstration records, which the interface identifies. No records were deleted from another database.

```sh
./hospitalflow run
```

Sign in with an existing HospitalFlow account. Database credentials are separate from application sign-in credentials. Use the initials button in the top right to change your application password. Changing it revokes all your current sessions. Administrators can create users, disable accounts, add providers and add beds through Administration.

## Accounts and administration

Roles now include **Admin, Doctor, Nurse, Patient (User), Volunteer and Developer**. Admin/Developer have full access; Doctor can register doctors, nurses, patients and volunteers; Nurse has nursing responsibilities; patient/volunteer access is limited. See [people and roles](docs/PEOPLE_AND_ROLES.md). Signup requires email verification and administrator approval. Forgot-password links expire and work once. Email syntax is validated, and new passwords require at least 6 characters with uppercase, lowercase and a symbol; common passwords and account identities are rejected. As requested, development emails are saved privately under `.local/mail/`; SMTP will be configured later.

Use **Administration** for account approval, role/permission management, user creation and system health; use **Operations controls** for the expanded business workflows. Existing accounts and staff permissions were preserved. See [accounts and access](docs/ACCOUNTS_AND_ACCESS.md) for instructions and production mail settings.

## People and registrations

Use **People & registrations → Add person** to choose the registration type. IDs are generated as **A / D / N / P / V / DEV**. Patient and staff directories include IDs, name, email, mobile, DOB and relevant department/job details; existing unknown fields remain unfilled. The new codes are stored in PostgreSQL, while existing internal keys and history are preserved.

## Patient portal and appearance

Registration by Admin/Developer or Doctor/Reception creates a linked patient account, automatic patient ID and protected email/SMS invitations. First login with the temporary password requires DOB verification and a new password before patient-only pages are accessible. Login then accepts email or patient ID. Local delivery files are in `.local/mail/` and `.local/sms/`, as requested. Existing patients can be enabled by adding their email through Edit.

The application consistently uses port **5136**. Required inputs show `*`. Use the theme button or double-click anywhere to switch Default/Dark; signed-in preferences are stored in PostgreSQL. See the [patient portal guide](docs/PATIENT_PORTAL.md).

## Database structure

Twenty-five checksum-protected migrations define the relational database. See the installed object catalogue for current object counts. `schema_versions` records checksums of applied migrations. `idempotency_hash_keys` holds the random key used to protect retry fingerprints.

See the [enterprise database guide](docs/ENTERPRISE_DATABASE.md) and [installed object catalogue](docs/DATABASE_OBJECTS.md) for the complete inventory and transaction behavior. See the [project structure and data storage guide](docs/PROJECT_STRUCTURE.md) for the feature layout and persistence rules. Main source locations:

- `Database/Migrations/`: ordered, embedded SQL migrations.
- `Data/RowMap.cs`: typed relational row mapping and parameterized SQL.
- `Data/DbSecurity.cs`: database-backed authentication sessions and data-protection key repository.
- `Data/Store.cs`: transactional persistence, imports, idempotency, authentication state and alerts.
- `Program.cs`: HTTP security, request auditing and authorized endpoints.
- `hf_api.execute` in the SQL migrations: transaction gateway and linked business procedures.
- `Database/grant_runtime.sql`: privileges for the restricted runtime account.

## Activity logging

Every API request records a durable start event before processing and a completion event containing the result and HTTP status. This includes reads, successful mutations, rejected requests, validation failures and authorization failures. Successful business changes also record an event in the same transaction as the changed records.

Sign-in, sign-out, password changes, page visits, individual patient/invoice views and report exports have explicit events. Database row-history triggers record the table, record ID, operation, changed column names, actor ID and correlation ID. They do **not** copy clinical text, patient contact values, passwords, password hashes, request bodies or query strings into the history.

Activity, row history, stock movements, posted bill lines and payments are append-only. The runtime role cannot update or delete them. Database-owner credentials remain capable of administering the database, so production backups and independent log retention still matter.

Administrators can inspect recent history under **Administration → Activity log**. `GET /api/activity?offset=0&limit=100` provides paginated history; non-administrators receive only their own events. If the database cannot save a request-start event, the application fails the request before disclosing API data. If completion logging fails after a response has started, the start event remains and a critical server log records the failure.

## Integrity and retries

Mutations run in database transactions under a PostgreSQL advisory transaction lock. The application invokes database-native commands through `hf_api.execute`; linked changes, audit and retry records commit together. Foreign keys, checks and unique indexes protect relationships, non-negative stock and exclusive active admissions. Triggers check appointment overlap, occupancy consistency, invoice balance, stock/ledger reconciliation, medicine expiry and discharge prerequisites. Bed assignments preserve historical occupancy intervals.

Every mutation requires an `Idempotency-Key` UUID header. The browser generates one per form submission workflow and reuses it on retry. Repeating the same key, user, action and payload returns the original result; reusing a key for a different operation is rejected. This works across application instances and protects payments and stock receipts from retry duplication. These keys do not expire automatically; define a retention period with operational policy before pruning them.

## Verification

Requires .NET SDK 10, Python 3 and local PostgreSQL `initdb`, `pg_ctl`, `psql`, `pg_dump` and `pg_restore` tools.

```sh
dotnet restore HospitalFlow.csproj
dotnet build HospitalFlow.csproj --no-restore
node --check wwwroot/js/core/app.js
node tests/frontend_workspaces.cjs
node tests/frontend_persistence.cjs
python3 tests/postgres.py
python3 scripts/database_report.py
```

The test suite uses a disposable cluster and limited runtime role. It verifies core workflows, constraints, immutable ledgers, repeated migrations, concurrent resource allocation, stock reconciliation, cross-instance payment idempotency, sessions after restart, notifications, request/failed-login logging, account disabling, password changes, patient updates and bed creation. It does not touch your installed HospitalFlow database. `tests/smoke.py` invokes the same suite.

The approved `hospitalflow_jobs` login runs fixed maintenance routines with no clinical-table reads or schema-change privileges. User launchd agents run maintenance every 60 seconds and backups at 02:15 local system time while the Mac user is logged in. A real backup passed an isolated restore drill; all installed database validation checks currently report zero violations.

## Backups and local maintenance

```sh
python3 scripts/backup_database.py
python3 scripts/local_database.py status
python3 scripts/local_database.py stop
```

Backups are PostgreSQL custom-format dumps under `.local/backups/`, with owner-only file permissions. See [deployment](docs/DEPLOYMENT.md) for restore verification and production configuration. Your PostgreSQL server on port 5432 is externally managed; the helper checks readiness and will not start or stop that shared service. The former dedicated cluster on port 55432 is retained as a rollback copy, with its connection details in `.local/database-55432.json`.

## Production deployment

Production startup requires a PostgreSQL runtime connection and an encryption certificate for database-held authentication keys. It enforces secure cookies, HTTPS redirection and HSTS, and does not seed demonstration accounts. Migrations are applied separately with the owner account; the web process runs with the restricted runtime account. A non-root Dockerfile and production configuration are included.

See [deployment](docs/DEPLOYMENT.md) for exact settings. The local review instance runs in **Development** on loopback HTTP. A public production host, trusted HTTPS certificate, encrypted backups, monitoring, recovery targets and hospital-specific access policies must be configured and validated before real patient use. The code change and local tests alone do not certify a live hospital deployment.

Operational screens currently share a broad, role-filtered state snapshot, and write transactions are serialized across the application. These choices provide consistent behavior at the current scale, but require server-side record pagination, department/patient scoping and measured load tests for larger deployments. Provider sessions/absences, procurement, reservations, price catalogues and local payment reversals have Admin/Developer forms in Operations controls. Signup, verification, password reset and role-based access management are implemented; see [accounts and access](docs/ACCOUNTS_AND_ACCESS.md). SMTP configuration, MFA, controlled patient merges, external payment processing, SMS delivery and FHIR interfaces remain deployment or future work.

Personal workspaces: [patient, nurse and volunteer pages, contact editing, verified email changes and assignments](docs/ROLE_WORKSPACES.md).

[Mobile validation, record printing/downloads and overview navigation](docs/PRINTING_AND_VALIDATION.md).

[Multi-hospital access, directory, referrals and retained history](docs/HOSPITAL_NETWORK.md): the original hospital plus 20 labelled demonstration hospitals and 40 fictional provider profiles. Use the hospital selector to change authorised workspaces.

Appointment booking and staff attendance: see [the workflow guide](docs/APPOINTMENTS_AND_ATTENDANCE.md) for 10-minute slots, the two-hour cutoff, ₹200–₹750 fees, local test payments, cash refunds and doctor leave warnings.

Admin and Doctor are separate roles: see [the role guide](docs/ADMIN_AND_DOCTOR_ROLES.md) for management, clinical authoring and Developer access.

The [Patient care pathway](docs/COMPLETE_CARE_FLOW.md) covers Doctor admission orders, Nurse acceptance/bed assignment, scheduled medication outcomes, daily monitoring, pharmacy requests, versioned ward charges, patient timelines and staged discharge approval.

## Billing, annual holidays and releases

See [Billing, calendar and versioning](docs/BILLING_CALENDAR_VERSIONING.md) for Admin tariffs, medicine prices, patient TEST payments, discounts, yearly hospital holiday policies and automatic Git version increments. The initial version is `1.0.0`; the running version and release history are visible under **Application versions** for Admin/Developer.
