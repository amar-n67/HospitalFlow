# Deployment and recovery

## Local database already provisioned

HospitalFlow now uses your existing PostgreSQL 17 server at `localhost:5432`, database `hospitalflow`. The supplied `postgres` administrator account was used to create and restore it; the application uses a separate restricted `hospitalflow_app` account. Your other databases were not changed. Refresh the Databases node in pgAdmin to see it.

Credentials are in ignored owner-readable local files. The helper checks this externally managed server's readiness but will not start or stop it. The former port-55432 cluster and its rollback configuration are retained; it is no longer the application's database.
```sh
python3 scripts/local_database.py start
dotnet run --project HospitalFlow --launch-profile http
```

To apply future migrations to this database:

```sh
dotnet build HospitalFlow
python3 scripts/local_database.py migrate
```

The original file import used `--import-legacy HospitalFlow/App_Data/hospitalflow.json`. Do not repeat the import into a populated database. The later move to port 5432 used a full schema backup/restore and verified every table row-for-row before switching the connection.

## Provision a separate production database

Use a supported PostgreSQL deployment with restricted network access and encrypted storage. Create an owner/migration role and a separate application login; the application login must not own the schema. Provide secrets through the deployment environment or secret manager, not committed configuration.

Run migrations as a one-off deployment job using the owner connection. On an empty database, supply a unique first administrator through these environment variables:

- `ConnectionStrings__HospitalFlow`: owner connection for this one job.
- `Bootstrap__Email`, `Bootstrap__Name`, `Bootstrap__Password`: initial account; password length at least 6 characters with uppercase, lowercase and a symbol.
- `ASPNETCORE_ENVIRONMENT=Production`.

```sh
dotnet HospitalFlow.dll --migrate
```

Then apply `HospitalFlow/Database/grant_operations.sql` and `HospitalFlow/Database/grant_runtime.sql` as the database owner, adapting its `hospitalflow_app` role name if needed. Remove owner and bootstrap secrets from the web process. Demo seeding is refused outside Development. No default password is generated for a fresh production database.

## Runtime settings

| Variable | Required setting |
| --- | --- |
| `ASPNETCORE_ENVIRONMENT` | `Production` |
| `ConnectionStrings__HospitalFlow` | Restricted runtime connection; for a remote database use certificate-validated TLS and the correct root CA |
| `AllowedHosts` | Actual application hostname, without wildcard |
| `Security__KeyEncryptionCertificate` | Mounted PFX path with a private key, readable only by the app identity |
| `Security__KeyEncryptionCertificatePassword` | PFX password from the secret manager |
| `Kestrel__Certificates__Default__Path` | HTTPS PFX path when Kestrel terminates HTTPS |
| `Kestrel__Certificates__Default__Password` | HTTPS certificate password |
| `ASPNETCORE_URLS` | HTTPS binding, for example `https://+:5136` |

The supplied Dockerfile publishes .NET 10 and runs as the image's non-root application user. Mount certificates read-only and expose the HTTPS listener through your deployment network. It contains no database or local credentials. It has not been deployed to an external host during this task.

If terminating HTTPS at a reverse proxy, configure forwarded headers for **explicit trusted proxies/networks** before HTTPS middleware; do not trust arbitrary forwarded headers. The supplied configuration assumes direct Kestrel HTTPS termination. Public DNS, certificate issuance, reverse proxy configuration and a deployment platform were not provided.

Production mode refuses startup without the key-encryption certificate, uses secure HttpOnly SameSite cookies and HSTS, and redirects HTTP to HTTPS. Data-protection keys are stored in PostgreSQL; new keys in Production are encrypted with the configured certificate. Store older decryption certificates during rotation so existing keys remain readable. Do not move Development's unencrypted key repository into Production: create the production database separately, or plan a controlled key rotation/session revocation. PostgreSQL contains encrypted session tickets, and account status is checked on authentication.

## Logging

Watch for request-start events with missing completions and critical server logs if completion auditing fails. Activity records contain actor identity, action, reference, UTC time, outcome, request correlation, method, source IP and status. Data-change triggers append table/record/changed-column metadata. Application passwords, hashes and clinical text are omitted from audit records.

Readiness depends on a successful database-backed health request, not merely an open TCP port. Route operational logs to independent retention and alerting; the database owner can still administer or replace database objects. Define patient-data and audit retention with the institution before implementing pruning jobs. The scheduled worker cleans expired sessions and performs integrity, alert, reporting and backup-health checks; it does not automatically prune historical clinical or financial records.

## Backup and restore

```sh
python3 scripts/backup_database.py
```

This creates a custom-format `pg_dump` in `.local/backups/` with owner-readable permissions. For production, schedule database backups and WAL/PITR as required, encrypt backup storage and use a separate recovery destination. Backups contain sensitive application data and must not be shared as ordinary project files.

To test a restore, create a new empty database owned by a recovery/migration role. Restore a dump into that database, never over the only live copy:

```sh
pg_restore --no-owner --no-acl --exit-on-error --dbname="$RECOVERY_DATABASE_CONNECTION" /path/to/hospitalflow.dump
```

Apply both `grant_operations.sql` and `grant_runtime.sql` for the recovery environment (the dump intentionally excludes ACLs), verify table counts, invoice balances, stock reconciliation, active bed occupancy and audit chronology, then start an isolated application instance against it. Confirm its encryption certificate can decrypt the restored authentication keys. The automated integration test performs a disposable backup/restore check; production recovery time and recovery-point targets still require an operational drill.

## Validation boundary

The local application is database-connected and its relational workflows/security controls are tested. Before real hospital deployment, validate workload capacity, department/patient access boundaries, independent log retention, backup recovery, MFA/account recovery, monitoring and clinical governance. The interface currently requests a role-filtered operational snapshot and writes are serialized; these require pagination and workload-driven changes at larger scale. No clinical efficacy, regulatory certification or production availability result is claimed.

## Installed local schedules and recovery evidence

See [enterprise database operations](ENTERPRISE_DATABASE.md). The approved restricted maintenance login is configured in a Git-ignored owner-readable file. Two user launchd agents are installed: maintenance every 60 seconds and backup at 02:15 local system time. They require the Mac user to be logged in; use an always-on service scheduler for production.

Run `python3 scripts/configure_jobs.py status` to inspect schedules, `python3 scripts/verify_database.py` for schema/integrity checks, and `python3 scripts/restore_drill.py` to restore the latest recorded backup into a disposable password-protected cluster. The installed database has passed an actual backup/restore drill; this is local recovery evidence, not a measured production SLA.

## Account email delivery

Production now also requires `Accounts__PublicOrigin` (public HTTPS origin), `Mail__From` and `Mail__Smtp__Host`; optional port/username/password settings are described in [accounts and access](ACCOUNTS_AND_ACCESS.md). The local installation deliberately uses private development email files, as requested. Production will not fall back to those files.

## Patient invitations and fixed port

Standard web bindings use port **5136**, including the production container. Both local launch profiles explicitly bind that port; HTTPS requires its certificate and cannot run beside HTTP on the same port. Set `Accounts__PublicOrigin` to the actual public HTTPS origin so emailed links target the deployed service. Automated tests alone use explicit temporary bindings.

Patient email/SMS invitations are protected in PostgreSQL. Development uses owner-only `.local/mail/` and `.local/sms/` transport files. SMS has no external-provider adapter yet and remains pending in Production; it is never reported as delivered. See [patient access](PATIENT_PORTAL.md).
