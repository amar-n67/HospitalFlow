# Patient access, local messaging and appearance

## Fixed application port

The web application's standard port is **5136**. Default configuration and the HTTP launch profile use `http://localhost:5136`; the HTTPS profile and production container use HTTPS on port 5136 with configured certificates. Run one profile at a time. Invitation/recovery links use `Accounts:PublicOrigin`, defaulting locally to `http://localhost:5136`. Production must set the actual public HTTPS origin. Database connections continue to use the existing PostgreSQL service on port 5432.

```sh
dotnet run --project HospitalFlow --launch-profile http
```

Disposable automated tests explicitly override the web binding with isolated temporary ports; they do not occupy or modify the user's running installation.

## Required fields and themes

Required form controls display a red `*`, including dynamic dialogs, signup, sign-in, verification, patient email and mobile. Native browser requirements and server validation remain enforced.

Use the top-right **Dark / Default** button, or **double-click anywhere inside the application**, including a dialog, to switch themes. A visitor's selection is remembered in the browser. For a signed-in account it is also stored in `hospitalflow.user_preferences` and audited. Sign-in restores that account's saved theme.

## Register and invite a patient

An Admin, Developer or User with the Doctor/Reception responsibility can register a patient through **Patients → Register patient**. Enter the patient's full name, date of birth, sex, mobile and a unique email address. Mobile numbers with ten digits use the local +91 default; other international numbers must include `+` and the country code.

The system generates the patient ID and, in the same transaction:

1. Saves the patient record.
2. Creates a separate limited **User** account linked to that patient.
3. Hashes a cryptographically random temporary password, expiring after 24 hours.
4. Queues protected email and SMS invitations containing the patient's email, patient ID, application link and temporary password.
5. Commits the business/audit/retry evidence.

Retrying the same registration does not create another account or invitation. An email collision rolls back the whole registration rather than leaving a partially linked identity. Staff and patient identities cannot share an email; staff roles/permissions cannot be granted to a linked patient account.

Existing patient records and IDs are preserved. They are not automatically assigned guessed email addresses. To enable an existing patient's access, choose **Edit**, enter their email and save. Existing linked email addresses are read-only; changing a login email requires an identity-reviewed administrative process.

## Current delivery: private local files

As explicitly requested, both transports use private files in Development:

| Channel | Private directory | Contents |
| --- | --- | --- |
| Email | `.local/mail/` | Recipient, subject, invitation body |
| SMS | `.local/sms/` | Mobile recipient and invitation body |

Files/directories are owner-only, Git-ignored and outside the web root. The database stores a protected copy in the account email queue / `patient_sms`; normal APIs never return temporary passwords or mailbox contents. Read the relevant private file locally for testing. These files contain live temporary credentials and must not be shared or committed.

SMS records are marked **Local pickup**, not delivered to a real phone. No real email/SMS is sent with the current configuration. SMTP can be configured later using the account guide. An external SMS provider is not implemented; in Production its messages remain pending instead of pretending to deliver them. **Administration → System health** reports email and SMS queue totals.

## First login and mandatory change

1. Open the application link from the invitation.
2. Enter the email **or patient ID** and temporary password.
3. The application issues a short-lived, one-use onboarding challenge; it does **not** create an authenticated session or disclose patient records yet.
4. Enter the date of birth held on the registered patient record and a new password, confirmed twice in the form.
5. On success, the temporary credential and outstanding challenges/recovery tokens are invalidated. Sign in again using email/patient ID and the new password.

The new password must satisfy the existing six-character, uppercase, lowercase, symbol, common-password and account-identity rules, and differ from the temporary password. Each challenge expires after ten minutes and permits at most five DOB failures; IP/account throttles also apply. DOB is a supplementary check after possession of the temporary credential; it is not claimed to be MFA or proof of identity by itself.

A pending patient can request password recovery, but a reset does not remove the DOB/first-change gate. After invitation expiry, staff can use **Resend first access** from the patient directory to issue a new temporary credential. Reissue is restricted to pending patient access, requires an active account and is rate-limited. Activated patients use **Forgot password** instead.

## Patient pages and isolation

Activated patients see only **My profile**, **My appointments** and **My invoices**. Profile includes their ID, email, DOB, mobile and own admission history. Invoices include their own posted charges and receipts. Reads use server-side patient filters derived from the authenticated account; a browser-supplied patient ID cannot expand the scope.

The portal does not expose staff notes, other patients, inventory movements, account lists, operations controls or administrative health data. Patients cannot mutate hospital workflows or become staff through role/permission management. Staff operational permissions retain their existing hospital-wide module scope; this portal isolation does not claim complete row-level isolation for every staff screen.

## Verification

The build and isolated PostgreSQL/API suite pass, including the generated schema installer. Tests cover Doctor registration, automatic IDs, atomic invitation creation, retries, duplicate email rollback, encrypted queues/private pickup permissions, temporary expiry, DOB failures, mandatory password change, old credential rejection, email/ID sign-in, invitation reissue, recovery bypass prevention, staff/patient privilege separation, cross-patient read denial and persisted themes. Existing hospital workflow tests also pass.

Browser review verifies both themes, double-click switching and required markers on the patient form. No live sample patient or patient account was created solely for these tests. The original Admin account and existing business records are preserved.
