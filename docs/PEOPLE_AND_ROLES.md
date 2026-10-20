# People, roles and registration IDs

Use **People & registrations → Add person** to select who is being added. The form changes for Patient, Doctor, Nurse, Volunteer, Admin or Developer. The same entry point is available from Administration and the dashboard for authorized staff.

## Roles and permissions

| Person / role | ID prefix | Default access |
| --- | --- | --- |
| Admin | `A-` | Full application and account administration |
| Doctor | `D-` | Clinical workspace, patient registration and constrained people registration/directory |
| Nurse | `N-` | Patient/appointment visibility, operational notes, admissions, transfers, bed turnaround and discharge |
| Patient (User) | `P-` | Own patient portal after first-login verification |
| Volunteer | `V-` | Own account/profile/activity; no clinical or staff-directory access |
| Developer | `DEV-` | Full application access across every role/module |

Doctors can register Doctor, Nurse, Patient and Volunteer entries. Only Admin and Developer can register Admin/Developer accounts or change account roles/access. A Doctor cannot create a privileged account by editing a request. Nurses, patients and volunteers cannot call the people-registration API or read its directory.

Volunteer jobs include **Guard, Washerman, Housekeeping and Other**, with a job title for more detail. They do not receive clinical access. Doctor/Nurse roles supply their corresponding operational responsibility automatically. Existing Reception, Pharmacy and Billing permissions remain available for limited legacy operational accounts, preserving current workflows.

`User` remains the stored role for patient accounts. An unlinked public-signup/legacy limited User receives a `U-` account reference and no patient records by default; it is not treated as a patient until explicitly linked through the patient registration process. A linked patient cannot be promoted to a staff role or receive staff permission grants; use a separate identity for staff.

## Registration fields

- All new entries: name, email, mobile, DOB and sex.
- Doctor: department, job title and consultation shift.
- Nurse: department and job title.
- Volunteer: support job and job title.
- Patient: optional address and emergency contact, plus the existing automatic email/SMS invitation flow.
- Staff: initial password meeting the current password policy; contact/address details are stored in the staff profile.

Address/emergency contact are optional. Required fields display `*`. Emails, mobile syntax, DOB and doctor shifts are checked by the server. New email addresses must be unique. Patient email/mobile/DOB/name and their P ID appear in the relevant patient, appointment, admission, billing, profile and export views. Doctor IDs/contact details and staff IDs/email/mobile/DOB/job appear in their directories, subject to access.

Unknown legacy contact/DOB fields display **Not recorded** rather than invented values. Use **Edit details** in the people directory to complete a staff profile. Patient details are edited through **Patients**. Login email and role are not changed by a contact edit; role management remains a separate administrative operation. Patient email changes require an identity-reviewed administrative process.

## Stable keys and public IDs

The database generates unique display IDs such as `N-001025` and `P-001026`. Existing patients and providers also receive the new public IDs. The sequence is concurrency-safe and may have gaps after rejected transactions; codes are not counts.

Existing internal `id` values and foreign keys are preserved. The display ID is stored in **`registration_id`** on patients, doctors and users. This preserves clinical history, invoices, appointments, old audit references and login hashes. New linked Doctor provider/account IDs match; linked patient/account P IDs always match. Old standalone providers retain their relationships; missing employment links are not guessed.

Email or the current registration ID can be used for sign-in. Legacy patient `HF-…` login identifiers remain accepted for compatibility. A staff role change may issue a new role-appropriate display ID; the email and internal account key remain stable. Patient/provider display IDs are immutable.

## Database locations

| Data | Stored in |
| --- | --- |
| Patient P ID, name, email, mobile, DOB, sex, address, emergency contact | `hospitalflow.patients` (`phone` is the mobile column) |
| Account display ID, email, name, role, active status and password hash | `hospitalflow.users` |
| Staff mobile, DOB, sex, address, department, title, volunteer job and provider link | `hospitalflow.person_profiles` |
| Provider D ID, name, department and shift | `hospitalflow.doctors` |
| Patient/account association and first-login state | `hospitalflow.patient_accounts` |

Read-only examples for pgAdmin:

```sql
SELECT registration_id AS patient_id, name, email, phone AS mobile,
       dob, sex, address, emergency_contact
FROM hospitalflow.patients ORDER BY registration_id;

SELECT u.registration_id, u.role, u.name, u.email,
       p.mobile, p.dob, p.sex, p.department, p.job_title, p.occupation
FROM hospitalflow.users u
LEFT JOIN hospitalflow.person_profiles p ON p.user_id=u.id
ORDER BY u.registration_id;
```

Keep account hashes/private queues out of reports and exports. Do not rewrite internal IDs or bypass the application workflows to change identities.

## Verification

The .NET build and generated schema installer pass. Disposable integration tests cover six roles, all six ID prefixes, profile persistence, provider/account ID consistency, patient/account email/ID consistency, doctor registration permissions, blocked nurse/volunteer registration, blocked privileged-account creation by a Doctor, Developer full access, retries, contact edits and existing clinical/financial/inventory workflows. Live integrity checks pass after migration 012. Browser review verifies the person selector, nurse form, volunteer job choices and updated patient columns. No sample staff or patient accounts were added to the live database during testing.

Hospital memberships and hospital-specific operational data are described in [Hospital network](HOSPITAL_NETWORK.md). Registering a person assigns their initial membership to the selected hospital; earlier records stay with their original hospital.

For the current Admin versus Doctor permission split, see [Separate Admin and Doctor roles](ADMIN_AND_DOCTOR_ROLES.md). Admin clinical access is read-only; Developer retains both role capabilities.

Nurses cannot open Hospital Network or Referrals. Their care workspace now includes prescribed medication and timestamped administration records; see [Prescription administration](MEDICATION_ADMINISTRATION.md).

New staff registrations use initial password **1234**, set by the server rather than entered by the registering Admin/Doctor. No workspace session is issued until registered DOB verification and a required password change succeed. This applies to all newly registered staff roles, including Admin and Developer. Existing accounts are not reset. First-login credentials expire after 24 hours; an email recovery link can renew the login credential but still requires DOB verification before access. New passwords retain the normal strength and identity checks. Migration `023_staff_first_login.sql` preserves existing patient challenges while allowing staff activation; five incorrect DOB attempts exhaust a challenge, with existing endpoint rate limits also enforced.
