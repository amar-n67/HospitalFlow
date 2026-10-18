# Accounts, access and recovery

Open http://localhost:5136. Your existing administrator sign-in is preserved; its application role is now **Admin**. HospitalFlow has exactly three primary application roles:

| Role | Access |
| --- | --- |
| User | Own account and activity by default; assigned operational responsibilities only |
| Admin | All application modules, accounts, audit, system-health and operations controls |
| Developer | The same full application access as Admin |

Developer access does not expose PostgreSQL credentials, session tickets or password-reset secrets through the interface. Only trusted backend processes receive database credentials.

## Admin workflow

Go to **Administration → Users & roles → Manage access**. Approve/disable an account, select User/Admin/Developer and assign a User one or more responsibilities:

- Reception: registration, patient updates, appointment booking and visit status.
- Doctor: clinical notes/prescriptions, clinical views and medicine visibility.
- Nurse: admission, bed turnaround, transfer, discharge and operational notes.
- Pharmacist: inventory, stock receipts and dispensing.
- Billing: invoices, receipts and adjustments.

These responsibilities are permission grants, not additional primary roles. Existing staff roles were converted into the matching grants. Users receive the records required by their assigned modules; record access within each core module is currently hospital-wide, not complete patient-by-patient isolation. Configure stricter record scoping before a hospital requiring it goes live.

Admin and Developer can also use **Operations controls** for supplier/purchase-order management and receipts, stock quarantine/reservations/adjustments, service pricing and reversals, provider availability, staff/department assignments, patient contacts/consent/access, discharge tasks, follow-ups and clinical orders. Commands commit through the audited, idempotent database gateway. Operational record lists currently show up to 200 records per category.

Access changes revoke the affected account's sessions. Users cannot modify their own role/access through account management, and database protections prevent removing the last active full-access account. Admin-issued accounts are treated as identity-checked accounts; self-signups must verify their email before activation. Admin-created User accounts start with no permissions until explicitly assigned.

## Email and password validation

Email addresses must contain `@` and a complete domain (for example, `name@gmail.com`). Consecutive dots, incomplete domains and malformed domain labels are rejected. Valid addresses are trimmed and normalized to lowercase; email verification remains required for self-signups.

New passwords must contain 6–128 characters, at least one uppercase A–Z letter, one lowercase a–z letter, and a punctuation/symbol character such as `@`, `#` or `!`. A digit is optional. Common passwords and variations of `password`, `passwords` and `pass` are rejected. Passwords must not contain the account name, a name component of at least three characters, email username (before `@`) or full email address, compared without case or punctuation.

Browser validation gives immediate feedback and the server independently enforces the same policy for signup, admin-created accounts, resets, changes and fresh production bootstrap. Existing password hashes are preserved; sign-in does not retroactively reject an existing password for failing the new policy.

## Signup

1. Choose **Create an account**, enter name/email and a password of 6–128 characters.
2. Open the verification link delivered to the configured mailbox (24-hour expiry).
3. Ask an Admin or Developer to approve the account and assign responsibilities.
4. Sign in. A User without permissions sees their own account workspace and activity.

Signup cannot assign a privileged role, even if a caller edits the HTTP request. Repeated signup uses a generic response without disclosing whether an address exists. Resend verification is available from sign-in. Existing accounts and password hashes remain preserved during upgrade; passwords were not reset.

## Forgot password

Choose **Forgot password?**, enter the account email, and open the emailed link. Reset links expire after 30 minutes and can be used once. Requesting another link invalidates previous links of that type. A successful reset or authenticated password change revokes all existing sessions and outstanding reset tokens. Disabled/unverified accounts cannot use recovery to bypass approval or regain access.

Tokens are cryptographically random; only SHA-256 token hashes are stored in the token table. The account email queue is protected by ASP.NET Data Protection, including the link. Tokens are not returned by an API, stored in browser localStorage or placed in server request URLs. The browser removes the fragment link from the address bar after reading it. Signup, link requests, verification, reset and access changes have audit events. Request throttles cover IP and sign-in account fingerprints; recovery also limits per-account link issuance.

## Current delivery: private local files

As requested, SMTP is deferred. In Development the background queue writes owner-readable `.json` messages into **`.local/mail/`**, outside the web root and ignored by Git. Each message contains its recipient, subject and text body with the link. Open the matching private file locally to use the verification/reset link. Do not share or commit these files: a still-valid link grants its stated verification/reset action.

These files are a development mailbox, not messages delivered to real inboxes. The private directory is owner-only and each file is created with owner read/write permissions. The interface and API never expose the mailbox contents. Use **Administration → System health** to inspect pending/failed email counts. Delivery failures retry with a delay up to five attempts; request a fresh link after correcting configuration if a token has expired.

Optional development settings:

```json
{
  "Accounts": { "PublicOrigin": "http://localhost:5136" },
  "Mail": { "PickupDirectory": "/absolute/private/development/mail" }
}
```

## Later SMTP setup

Supply the following through environment variables or a secret manager. Do not commit passwords:

| Setting | Meaning |
| --- | --- |
| `Accounts__PublicOrigin` | Exact public HTTPS origin used in links |
| `Mail__From` | Verified sender address |
| `Mail__Smtp__Host` | SMTP hostname |
| `Mail__Smtp__Port` | STARTTLS submission port, normally 587 |
| `Mail__Smtp__Username` | SMTP identity if required |
| `Mail__Smtp__Password` | SMTP secret from protected configuration |

The sender requires TLS and validates the server certificate. This implementation uses STARTTLS SMTP submission, not implicit-TLS port 465. Production refuses startup without a public HTTPS origin, SMTP host/from and the existing key-encryption certificate. Production has no local-file delivery fallback. SMTP has not been configured or externally delivery-tested in this local installation.

ASP.NET's account-confirmation/recovery guidance is documented by [Microsoft](https://learn.microsoft.com/aspnet/core/security/authentication/accconfirm). This application retains its existing PostgreSQL authentication/session implementation and adds persisted, expiring, single-use lifecycle tokens rather than replacing existing account hashes.

## Verification and remaining production work

`dotnet build HospitalFlow --no-restore`, JavaScript syntax checks and `python3 tests/postgres.py --schema-installer` pass. Disposable tests cover unverified login denial, approval, signup role escalation attempts, permissions, Developer full access, admin-only operations, session revocation, generic recovery responses, token replay, encrypted queued messages and private-file delivery, alongside the existing clinical/financial/inventory tests. The installed database passes all integrity checks after the upgrade.

The local instance remains Development over loopback HTTP. Real deployment still requires SMTP delivery verification, HTTPS hosting, MFA/account recovery policy, measured load/pagination, narrower institutional record access where required, monitored always-on services and independent log/backup retention. Full application access does not mean that a local build is certified for hospital production use.

## Patient-linked User accounts

Patient registration creates a distinct, limited User identity with a first-login verification/password-change gate. These accounts see only their own patient pages and cannot receive staff grants. This is separate from public staff signup/approval. See the [patient portal guide](PATIENT_PORTAL.md) for temporary credentials, DOB verification, email/ID sign-in, private email/SMS delivery and theme preferences.
