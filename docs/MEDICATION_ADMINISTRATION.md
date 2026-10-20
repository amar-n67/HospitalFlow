# Prescriptions and medication provided in hospital

Doctors create a patient prescription from **Clinical workspace → Record prescription**. Nurse accounts can view prescriptions for their authorised patients in **Nursing workspace** and **Clinical workspace**. Access follows the existing care relationship: an active admission in an assigned department or a time-limited patient access grant. Administrators can manage those grants in Operations controls.

After pharmacy dispensing, a Nurse chooses **Record provided**, enters the whole quantity actually provided and an administration note, and saves. The server records the nurse's name and staff ID, hospital, prescription, patient and current timestamp. This record documents what was provided; it does not recommend doses or schedules. Dispensing remains the separate pharmacy stock/billing transaction.

The cumulative quantity cannot exceed the prescribed quantity. Duplicate retries reuse the same record. Administration records are append-only, with row history and activity logging; they cannot be edited or deleted through the application. Developer retains combined role access. Admin and Doctor can view records but cannot record medication as a nurse.

Patients see their own prescriptions and administration history under **My care**. Doctors see the history in **Clinical workspace**. Patients cannot enter or change administration records. Hospital and care access are checked in PostgreSQL as well as the API.

Nurse accounts no longer have Hospital Network or Referrals pages. Their workspace selector receives only their authorised hospital memberships, without the network provider directory or referrals.

Migration: `022_medication_administration.sql`. Verification: `tests/medication_care.py` and `tests/frontend_workspaces.cjs`.

## Appointment consultation workflow

After check-in, the assigned Doctor chooses **Start visit** on the appointment row. The app opens a styled prescription dialog for that patient, showing earlier prescriptions from all recorded visits at the selected hospital. The patient cannot be changed in this dialog, and PostgreSQL checks the appointment/patient/assigned-doctor relationship. **Prescribe / history** reopens the dialog during or after the consultation. Add further medicines from the saved-record dialog. Each prescription retains its appointment link, recorded date and prescriber; standalone older prescriptions remain visible as earlier records.

The assigned Doctor can advance their own appointment queue and receives a 30-day care access grant when starting the consultation. Admin/Reception can continue managing the queue, while Admin remains unable to prescribe. Developer retains combined access.

Pharmacy staff use their existing **Pharmacist** permission to **Dispense & invoice**. Dispensing atomically reduces stock, records the handover and creates a medicine invoice. The confirmation opens print/download controls, and the prescription list shows the invoice and dispensing timestamp. Pharmacy can access copies of pharmacy-generated invoices; other invoice access still needs Billing permission. Dispensing is not payment collection.

Nurses see visit-linked prescriptions and record quantities actually provided after pharmacy dispensing. Patients see their own retained visit references, prescriptions, pharmacy invoices and timestamped nursing administration history under **My care**. Earlier hospitals remain accessible through the existing hospital/history navigation.

Migration `024_visit_prescriptions.sql` adds immutable visit links and assigned-doctor checks. `tests/visit_prescriptions.py` verifies the full workflow, rejected cross-patient/unassigned-doctor writes, duplicate protection, document boundaries and retained multiple-prescription visit history.

Admin queue actions also open the visit dialog after **Start visit**, showing read-only prescription history and identifying the assigned Doctor who can prescribe. Existing in-progress and completed appointments have **View prescriptions** for Admin and **Prescribe / history** for the assigned Doctor, so the dialog can be reopened without changing the appointment status.
