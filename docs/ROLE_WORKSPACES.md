# Personal workspaces

Every signed-in role can open **My profile** from the navigation or top-right avatar. Mobile (exactly ten digits), address and (for patients) emergency contact are editable. Names, birth dates, sex, roles, registration IDs and employment information require authorised hospital staff corrections. Requests always act on the signed-in user; submitted IDs and role fields cannot select another person or increase access. Contact changes are validated, saved in PostgreSQL and audited.

Changing email requires the current password and confirmation at the new email address. The existing email remains usable until the single-use, 30-minute link is confirmed. Confirmation updates the linked patient record in the same transaction and revokes existing sessions and recovery tokens. Changing a password invalidates pending email change links. Three email change requests per 15 minutes are allowed. In local development, read the private email pickup files; no external email/SMS provider is currently configured.

Age is calculated from date of birth on the current calendar date. It increases on the birthday without changing the birth date or needing a scheduled database job. A 29 February birthday advances on 1 March in a non-leap year. Missing birth dates display “Not recorded”. Displayed profile ages recalculate while open without clearing or interrupting form edits.

Patients can see only their own profile, appointments, prescriptions, admission history, invoices and receipts. Prescription medicine names are selected only from their own prescriptions; inventory quantities and staff notes remain private. Patients cannot book visits, record payments or alter clinical information through these pages.

Nurses have a nursing overview with active inpatients, age, bed readiness, and links to clinical notes, admissions, transfers and the bed board, plus their own work assignments. Existing nursing permissions remain hospital-wide within those modules; these pages do not introduce a ward-assignment access model.

Volunteers have their own profile and non-clinical work assignments. They can start an assigned task and then mark it complete. They cannot read patients, clinical notes, billing or other people's tasks. Occupations (Guard, Washerman, Housekeeping, Other) remain visible on the profile. No clinical details should be entered in work task titles or locations.

Administrators and developers assign tasks to active nurses and volunteers from **Work assignments**, view progress and can advance task status. Other staff cannot create assignments. Tasks cannot skip straight from Assigned to Completed or be reopened through this interface. Concurrent/repeated transitions are rejected rather than overwritten. All task reads and changes are logged; row history preserves assignment changes.

Database migration 013 adds `email_changes` (hashed tokens, password fingerprints) and `work_tasks` (assignee, location, deadline and status), with indexes and task history triggers. Plaintext passwords and verification tokens are never stored in these tables. Runtime grants are defined in `grant_runtime.sql`.
