# Patient care pathway

Open **Patient care pathway** in a staff workspace or **Care timeline & hospital stay** in the patient portal. Records stay within the selected hospital and the patient's existing identity. Staff and patient care views refresh every 30 seconds while visible; open forms are left undisturbed.

## Consultation and admission

Register a new patient through People & registrations before booking. Existing email/ID identities are retained rather than recreated. Check in the appointment and let the assigned Doctor select **Start visit** to review earlier prescriptions and create treatment records. **Prescribe medicines** on the care page creates a single atomic set of 1–30 medicine entries for an authorised consultation. Each medicine keeps its own prescription ID, dosage instructions, dispensing state and administration history. Pending prescriptions can be cancelled by their author with a reason and replaced by new records; issued prescriptions are never overwritten.

A treating Doctor uses **Request / link admission** to enter diagnosis, treatment instructions, planned duration, optional requested ward and optional Nurse. Nurses see the request in Nursing workspace and the shared care page. The assigned Nurse, or a Nurse accepting an unassigned order, accepts responsibility and then chooses an available ward/bed, confirms duration and enters nursing notes. Bed allocation remains atomic, preventing two admissions from taking one bed. The current ward/bed is visible to the Doctor, Nurse, patient, and pharmacy/billing staff where applicable. Doctors can extend duration or update the treatment plan with a reason.

For an admission created before this workflow, the treating Doctor can choose its **Existing stay** when requesting/linking the admission. Earlier records are preserved. This opts the stay into the managed discharge protocol without inventing clinical authorship or approval. The normal Admit/Discharge UI routes users into the care pathway; legacy native routines remain compatible with historical unmanaged records.

## Daily monitoring and medicines

Nurses record health status, optional numeric vital measurements with displayed units, treatment progress and daily notes. Doctors and patients can review these observations. The app stores measurements; it does not interpret them or suggest treatment.

Doctor, Nurse or the owning patient can request fulfillment of a pending prescription. Pharmacy uses its existing Pharmacist permission to dispense, recording stock movements and the medicine invoice. A fulfillment request cannot alter clinical instructions or dispense stock.

Doctor/Nurse staff can schedule each medicine separately, entering the clinician's dose text, counted quantity and scheduled time. Scheduled quantities plus previously provided quantities cannot exceed the prescription total. The Nurse checks **Given**, or leaves it unchecked for **Not given**, and enters remarks. Given records store actual administration time, the saving timestamp and Nurse identity; Not given records require a reason and do not consume medication quantity. Once an outcome is recorded it cannot be rewritten. A further dose needs its own schedule. Actual time and minutes relative to the scheduled time are displayed without inventing a clinical lateness threshold.

## Laboratory services

Doctors recommend tests against an accessible encounter. Doctor/Nurse staff can complete the test with comments. Managed-care and care-page outpatient tests require an Admin-configured service price before completion. Completion snapshots that price and posts the laboratory invoice line exactly once. Existing laboratory services/prices are configured in Operations controls. Earlier unmanaged orders retain their original behaviour and history.

## Charges

Admin must choose **Configure daily ward rates** and enter a dated version of bed, ward, ICU and nursing rates. No rates are assumed. An explicit zero means no charge for that component. ICU rates apply only to an ICU-labelled bed or ward. A changed tariff is a new immutable version; posted lines retain their original price snapshot.

The billing convention is **one calendar-day charge per category, using the first bed occupied on that date**, including admission and discharge dates. It does not prorate by hours or bill every transferred bed for the same day. The UI explains this convention before rates are saved. Configure the required historical effective dates for a linked existing stay before final billing.

Daily charges accrue at initial managed bed assignment, nursing updates, explicit calculation and discharge finalization. A background worker catches up every five minutes while the app runs, including missed days after a restart. Unique admission/date/category keys prevent duplicate lines across workers and retries. Missing tariffs remain visibly unpriced and block final billing instead of being guessed.

Pharmacy invoices use dispensed batch prices. Completed care laboratory tests use versioned service prices. Billing/Admin can enter categorised consultation, laboratory, nursing, consumable and other service charges with comments. Existing appointment booking payments are included as a separate consultation category rather than charged again. Date-wise/category-wise charge tables and accumulated totals are available to the patient; refunded booking fees contribute zero. Existing invoice/payment pages remain the source for balances and settlement.

## Discharge

1. Nurse prepares final condition and nursing remarks.
2. Treating Doctor reviews monitoring and enters diagnosis, treatment provided, discharge medicines, follow-up instructions and Doctor remarks.
3. Doctor approves the discharge review.
4. Nurse finalizes after all scheduled inpatient doses have an outcome, required discharge tasks are complete, pending prescriptions are fulfilled/cancelled, and invoices are settled.
5. The app catches up missing daily charges, checks settlement, marks the admission discharged, moves the bed to cleaning and records completion.

The existing application settlement policy is retained: if final charge calculation creates an outstanding balance, settle that invoice before retrying finalization. Calculation/retries do not duplicate charges.

New observations, prescriptions, medication outcomes, notes or plan changes reopen an approval that has not yet been finalized. The Doctor must review again. Managed stays cannot bypass approval through the old discharge command. The approved summary, medication schedule/outcomes, clinical remarks and all stage timestamps remain accessible; **Print/Download** uses the authorised, audited discharge-summary document endpoint. Downloads are standalone printable HTML; browser Print supports Save as PDF.

## Timeline and permissions

The timeline records author name, source timestamp, activity and comments for bookings, consultation updates, clinical notes, prescriptions, referrals, admission/bed events, dispensing, administration, monitoring, charges and staged discharge. New events are immutable. Earlier records are imported with known source authors/timestamps, using row history where available. Unknown historical authors or unavailable booking times are identified explicitly rather than invented.

Admin has operational and read-only clinical access; Doctor performs clinical planning/approval; Nurse performs assigned nursing workflows; patient sees only their own records and may request pharmacy fulfillment; Pharmacy/Billing get the limited ward, prescription/financial information needed for their work. They cannot read monitoring or discharge clinical summaries. Developer retains combined access. Volunteer has no care-page access. All access still requires the selected hospital's membership and care scope.

Migration: `025_complete_care_flow.sql`. Checks: `tests/care_flow.py`, `tests/postgres.py --schema-installer`, and `tests/frontend_workspaces.cjs`. The `--care-only` option on the PostgreSQL harness runs a focused disposable test, never the live database.
