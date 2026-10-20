# Hospital network and retained patient history

## Directory and switching

Migration 015 preserves existing users and records in **H-0001**, the original hospital. It adds **20 clearly labelled fictional hospitals**, example addresses in different Indian cities, and two fictional doctor profiles per hospital (40 profiles). These are demonstration directory data, not verified real institutions, credentials, appointments or bed availability. The original hospital's address remains “not configured” until its owner enters it.

The selected hospital appears in the header. People can select only active hospital memberships. The first existing active Admin/Developer is retained as the **network operator**, and a fresh installation's bootstrap administrator becomes its operator. Developers have network access. Network operators can select hospitals, edit/add directory entries, and grant or revoke memberships from **Hospital access**. Ordinary hospital Admins manage people and operations only in their assigned hospital; they cannot create platform Developers or manage network-operator accounts.

Roles and account identity are shared across memberships. The same Doctor, Nurse or Volunteer role applies in each assigned hospital; this version does not support a different primary role per hospital. Changes to a shared multi-hospital account’s role, permissions or global enabled status require a network operator, so a local Admin cannot alter access in another hospital. Public signup remains a limited, approval-required account in the original hospital. Registration in a selected hospital automatically assigns the newly created person there. Revocation sets membership inactive and does not delete people, patients or clinical history.

## Database boundary

Operational tables now have immutable `hospital_id` ownership, indexed hospital filters and PostgreSQL row-security policies. Server-side request context resolves the authenticated identity and validates the selected hospital on every request; changing a header cannot create access. Pooled connections reset hospital, actor and patient settings when opened. Cross-hospital clinical foreign-key references are rejected by a database trigger. Shared patient identity is visible to staff only after registration/enrolment in that hospital; clinical rows remain owned by their original hospital.

Staff lists, account changes, task assignment, documents, notifications, retry records and reporting views respect the selected hospital. Shared authentication, encrypted delivery queues, taxonomy (department/ward names), network metadata and platform maintenance evidence remain network services. Platform jobs and backup/restore operate across the database. The runtime database credential is a trusted server identity, never an end-user SQL account; tenant settings are supplied by the authenticated backend.

Currency and timezone remain network-wide INR/Asia-Kolkata. Hospital membership does not imply a ward-specific or treating-doctor-only access model: existing module permissions still apply within the selected hospital.

## Referrals

A Doctor or authorised full-access hospital administrator can select a registered patient, an available destination hospital and optionally a doctor listed there. The reason/handover text and minimum patient identity are shared with the addressed hospital. Requests require idempotency keys; duplicate pending source/patient/destination combinations are rejected.

Referrals transition from Pending to Accepted or Declined by the destination team, or to Cancelled by the source team. Resolutions require a recorded note. Acceptance adds a destination patient enrolment and, when a patient portal account exists, that hospital membership. It never moves source appointments, invoices, prescriptions or admissions, and does not create an appointment, bed reservation, discharge or external email/SMS. The receiving team must record those actions separately. A new referral can be recorded after an earlier one is resolved.

Incoming referrals expose only the shared patient name, patient ID and referral summary until accepted. Volunteers cannot read referral patient information. Patients can read only their own referrals, not other referrals addressed to their selected hospital.

## History tree

**Hospital history** is a nested, collapsible patient → hospital → registration/appointment/admission/prescription/invoice/referral tree. Staff see clinical events for their selected hospital and referral summaries sent to/from it. Patient portal users see their own retained tree across hospitals. Ordinary patient pages show records for the selected hospital; the tree retains access to earlier own records. Document permissions continue to apply to each node.

Legacy prescription timestamps are populated from recorded authorship when available; unknown original timestamps remain unknown. No historical dates are invented. Global patient identity/contact corrections remain shared and audited; previous clinical rows retain their hospital ownership.

## Verification

`tests/hospital_network.py` exercises hospital/header isolation, scoped account lists and documents, cross-hospital stock rejection, referral retries and recipient-only resolution, preserved source visits, accepted destination enrolment, patient-only history, volunteer isolation, immediate membership revocation and first-time patient onboarding at a second hospital. Existing workflow, authentication, validation and backup/restore integration tests remain part of the suite.
