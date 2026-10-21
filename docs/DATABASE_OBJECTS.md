# Installed HospitalFlow database catalogue

Generated from the installed PostgreSQL metadata on `localhost:5432/hospitalflow`. No patient records, password hashes or credentials are included. Regenerate with `python3 scripts/export_database_catalog.py`.

| Object type | Count |
| --- | --- |
| EVENT TRIGGER | 2 |
| FUNCTION | 101 |
| INDEX | 250 |
| MATERIALIZED VIEW | 1 |
| POLICY | 86 |
| PROCEDURE | 23 |
| SEQUENCE | 7 |
| TABLE | 108 |
| TRIGGER | 245 |
| TYPE | 2 |
| VIEW | 14 |

## Tables and columns

The `hospitalflow` schema contains business/security data. `hf_ops` contains schedules, operational evidence and recovery metadata. New financial and inventory ledgers use append-only records; see the enterprise database guide for privilege and retention boundaries.

### hf_ops.backup_runs

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| started_at | timestamp with time zone | NO | now() |
| completed_at | timestamp with time zone | YES |  |
| status | text | NO |  |
| file_reference | text | YES |  |
| bytes | bigint | YES |  |
| sha256 | text | YES |  |
| error_code | text | YES |  |


### hf_ops.daily_snapshots

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| day | date | NO |  |
| ward | text | NO |  |
| staffed_beds | bigint | NO |  |
| occupied_beds | bigint | NO |  |
| available_beds | bigint | NO |  |
| captured_at | timestamp with time zone | NO | now() |


### hf_ops.integrity_findings

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| run_id | uuid | NO |  |
| check_name | text | NO |  |
| violations | bigint | NO |  |
| checked_at | timestamp with time zone | NO | now() |


### hf_ops.job_definitions

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| name | text | NO |  |
| task | text | NO |  |
| interval_seconds | integer | NO |  |
| enabled | boolean | NO | true |
| next_run_at | timestamp with time zone | NO | now() |
| last_started_at | timestamp with time zone | YES |  |
| last_finished_at | timestamp with time zone | YES |  |
| last_status | text | YES |  |
| failures | integer | NO | 0 |


### hf_ops.job_runs

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| job_name | text | NO |  |
| started_at | timestamp with time zone | NO | now() |
| finished_at | timestamp with time zone | YES |  |
| status | text | NO |  |
| error_code | text | YES |  |


### hf_ops.restore_drills

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| backup_id | uuid | NO |  |
| performed_at | timestamp with time zone | NO | now() |
| outcome | text | NO |  |
| evidence_reference | text | NO |  |
| recovery_seconds | integer | YES |  |


### hf_ops.retention_policies

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| entity | text | NO |  |
| retain_days | integer | YES |  |
| purge_enabled | boolean | NO | false |
| approved_reference | text | YES |  |


### hf_ops.schema_change_events

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | bigint | NO |  |
| occurred_at | timestamp with time zone | NO | now() |
| database_user | text | NO |  |
| command_tag | text | NO |  |
| object_identity | text | NO |  |


### hf_ops.worker_heartbeats

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| worker | text | NO |  |
| last_seen_at | timestamp with time zone | NO |  |
| status | text | NO |  |


### hospitalflow.account_mail

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| user_id | text | NO |  |
| encrypted_message | text | NO |  |
| status | text | NO | 'Pending'::text |
| attempts | integer | NO | 0 |
| next_attempt_at | timestamp with time zone | NO | now() |
| created_at | timestamp with time zone | NO | now() |
| sent_at | timestamp with time zone | YES |  |
| error_code | text | YES |  |


### hospitalflow.account_tokens

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| token_hash | text | NO |  |
| user_id | text | NO |  |
| purpose | text | NO |  |
| expires_at | timestamp with time zone | NO |  |
| consumed_at | timestamp with time zone | YES |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.activity_log

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| actor | text | NO |  |
| action | text | NO |  |
| reference | text | NO |  |
| at | timestamp with time zone | NO | now() |
| outcome | text | NO | 'Success'::text |
| actor_id | text | YES |  |
| correlation_id | text | YES |  |
| source_ip | text | YES |  |
| method | text | YES |  |
| status_code | integer | YES |  |
| database_user | text | YES | SESSION_USER |
| transaction_id | bigint | YES | txid_current() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.admission_events

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| admission_id | text | NO |  |
| kind | text | NO |  |
| from_bed | text | YES |  |
| to_bed | text | YES |  |
| reason | text | NO |  |
| actor_id | text | NO |  |
| at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.admissions

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| patient_id | text | NO |  |
| bed_id | text | NO |  |
| reason | text | NO |  |
| at | timestamp with time zone | NO |  |
| status | text | NO |  |
| discharged | timestamp with time zone | YES |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.application_releases

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| version | text | NO |  |
| released_at | timestamp with time zone | NO |  |
| source_parent | text | NO |  |
| notes | text | NO |  |
| installed_at | timestamp with time zone | NO | now() |


### hospitalflow.appointment_bookings

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |
| patient_id | text | NO |  |
| doctor_id | text | NO |  |
| at | timestamp with time zone | NO |  |
| visit_type | text | NO |  |
| amount | numeric | NO |  |
| method | text | NO |  |
| state | text | NO | 'Pending'::text |
| payment_mode | text | NO |  |
| appointment_id | text | YES |  |
| created_by | text | NO |  |
| created_at | timestamp with time zone | NO | now() |
| expires_at | timestamp with time zone | NO | (now() + '00:10:00'::interval) |
| paid_at | timestamp with time zone | YES |  |
| refunded_at | timestamp with time zone | YES |  |


### hospitalflow.appointments

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| patient_id | text | NO |  |
| doctor_id | text | NO |  |
| at | timestamp with time zone | NO |  |
| type | text | NO |  |
| status | text | NO |  |
| checked_in | timestamp with time zone | YES |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.auth_attempts

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| key_hash | text | NO |  |
| failures | integer | NO |  |
| blocked_until | timestamp with time zone | NO |  |


### hospitalflow.bed_assignments

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | bigint | NO |  |
| admission_id | text | NO |  |
| bed_id | text | NO |  |
| from_time | timestamp with time zone | NO |  |
| to_time | timestamp with time zone | YES |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.beds

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| ward | text | NO |  |
| category | text | NO |  |
| status | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.bill_lines

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| bill_id | text | NO |  |
| description | text | NO |  |
| amount | numeric | NO |  |
| created_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.billing_tax_settings

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| bed_rate | numeric | NO | 18 |
| medicine_rate | numeric | NO | 7 |
| other_rate | numeric | NO | 0 |
| configured_by | text | YES |  |
| created_at | timestamp with time zone | NO | clock_timestamp() |


### hospitalflow.billing_tax_snapshots

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| line_id | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |
| setting_id | uuid | NO |  |
| category | text | NO |  |
| rate | numeric | NO |  |
| captured_at | timestamp with time zone | NO | now() |


### hospitalflow.bills

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| patient_id | text | NO |  |
| created_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.booking_events

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | bigint | NO |  |
| booking_id | uuid | NO |  |
| event | text | NO |  |
| actor_id | text | NO |  |
| at | timestamp with time zone | NO | now() |


### hospitalflow.booking_settings

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| hospital_id | text | NO |  |
| fee | numeric | NO |  |
| updated_at | timestamp with time zone | NO | now() |


### hospitalflow.care_charge_entries

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| admission_id | text | NO |  |
| patient_id | text | NO |  |
| charge_day | date | NO |  |
| category | text | NO |  |
| amount | numeric | NO |  |
| rate_id | uuid | NO |  |
| bed_id | text | NO |  |
| line_id | text | YES |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.care_command_keys

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| actor_id | text | NO |  |
| key | uuid | NO |  |
| action | text | NO |  |
| request_hash | text | NO |  |
| reference | text | NO |  |


### hospitalflow.care_discharge_reviews

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| admission_id | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |
| patient_id | text | NO |  |
| nurse_id | text | NO |  |
| final_condition | text | NO |  |
| nurse_remarks | text | NO |  |
| prepared_at | timestamp with time zone | NO | now() |
| doctor_id | text | YES |  |
| approved_at | timestamp with time zone | YES |  |
| diagnosis | text | YES |  |
| treatment | text | YES |  |
| discharge_medications | text | YES |  |
| follow_up | text | YES |  |
| doctor_remarks | text | YES |  |
| completed_by | text | YES |  |
| completed_at | timestamp with time zone | YES |  |


### hospitalflow.care_events

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| patient_id | text | NO |  |
| activity | text | NO |  |
| actor_id | text | YES |  |
| actor_name | text | NO |  |
| at | timestamp with time zone | NO | now() |
| comments | text | NO |  |
| reference | text | NO |  |
| details | jsonb | NO | '{}'::jsonb |


### hospitalflow.care_extra_categories

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| line_id | text | NO |  |
| category | text | NO |  |


### hospitalflow.care_invoices

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| admission_id | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |
| bill_id | text | NO |  |


### hospitalflow.care_lab_charges

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| order_id | uuid | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |
| patient_id | text | NO |  |
| line_id | text | NO |  |
| price_id | uuid | NO |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.care_managed_orders

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| order_id | uuid | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |
| patient_id | text | NO |  |


### hospitalflow.care_observations

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| admission_id | text | NO |  |
| patient_id | text | NO |  |
| recorded_by | text | NO |  |
| at | timestamp with time zone | NO | now() |
| health_status | text | NO |  |
| vitals | jsonb | NO | '{}'::jsonb |
| progress | text | NO |  |
| notes | text | NO |  |


### hospitalflow.care_plans

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| patient_id | text | NO |  |
| doctor_id | text | NO |  |
| nurse_id | text | YES |  |
| appointment_id | text | YES |  |
| admission_id | text | YES |  |
| requested_ward | text | YES |  |
| planned_days | integer | NO |  |
| nursing_days | integer | YES |  |
| nursing_notes | text | YES |  |
| diagnosis | text | NO |  |
| instructions | text | NO |  |
| status | text | NO | 'Requested'::text |
| created_at | timestamp with time zone | NO | now() |
| updated_at | timestamp with time zone | NO | now() |


### hospitalflow.care_rates

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| ward | text | NO |  |
| effective_from | date | NO |  |
| bed_daily | numeric | NO |  |
| ward_daily | numeric | NO |  |
| icu_daily | numeric | NO |  |
| nursing_daily | numeric | NO |  |
| configured_by | text | NO |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.clinical_orders

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| encounter_id | uuid | NO |  |
| service_id | uuid | NO |  |
| ordered_by | text | NO |  |
| status | text | NO |  |
| created_at | timestamp with time zone | NO | now() |
| completed_at | timestamp with time zone | YES |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.data_protection_keys

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | bigint | NO |  |
| friendly_name | text | NO |  |
| xml | text | NO |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.departments

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| name | text | NO |  |
| active | boolean | NO | true |


### hospitalflow.discharge_tasks

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| admission_id | text | NO |  |
| code | text | NO |  |
| required | boolean | NO | true |
| completed_by | text | YES |  |
| completed_at | timestamp with time zone | YES |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.doctors

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| name | text | NO |  |
| department | text | NO |  |
| start | time without time zone | NO |  |
| end | time without time zone | NO |  |
| active | boolean | NO | true |
| registration_id | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.email_changes

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| token_hash | text | NO |  |
| user_id | text | NO |  |
| email | text | NO |  |
| password_fingerprint | text | NO |  |
| expires_at | timestamp with time zone | NO |  |
| consumed_at | timestamp with time zone | YES |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.encounters

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| patient_id | text | NO |  |
| kind | USER-DEFINED | NO |  |
| appointment_id | text | YES |  |
| admission_id | text | YES |  |
| opened_at | timestamp with time zone | NO |  |
| closed_at | timestamp with time zone | YES |  |
| status | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.follow_ups

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| patient_id | text | NO |  |
| admission_id | text | YES |  |
| due_at | timestamp with time zone | NO |  |
| doctor_id | text | YES |  |
| instructions | text | NO |  |
| status | text | NO |  |
| appointment_id | text | YES |  |
| created_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.goods_receipt_lines

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| receipt_id | uuid | NO |  |
| purchase_order_line_id | uuid | NO |  |
| quantity | integer | NO |  |
| movement_id | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.goods_receipts

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| purchase_order_id | uuid | NO |  |
| reference | text | NO |  |
| received_by | text | NO |  |
| received_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.hospital_holidays

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| name | text | NO |  |
| on_date | date | YES |  |
| annual_month | integer | YES |  |
| annual_day | integer | YES |  |
| kind | text | NO |  |
| is_leave | boolean | NO | false |
| active | boolean | NO | true |
| notes | text | NO | ''::text |
| source | text | NO | ''::text |
| updated_by | text | YES |  |
| updated_at | timestamp with time zone | NO | now() |


### hospitalflow.hospital_memberships

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| user_id | text | NO |  |
| hospital_id | text | NO |  |
| active | boolean | NO | true |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.hospital_profile

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | smallint | NO |  |
| name | text | NO |  |
| currency | character | NO | 'INR'::bpchar |
| timezone | text | NO | 'Asia/Kolkata'::text |
| updated_at | timestamp with time zone | NO | now() |


### hospitalflow.hospitals

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| name | text | NO |  |
| address | text | NO |  |
| city | text | NO |  |
| state | text | NO |  |
| postal_code | text | NO |  |
| active | boolean | NO | true |
| accepting_referrals | boolean | NO | true |
| is_demo | boolean | NO | false |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.idempotency_hash_keys

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | smallint | NO |  |
| secret | bytea | NO |  |


### hospitalflow.idempotency_keys

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| user_id | text | NO |  |
| key | uuid | NO |  |
| action | text | NO |  |
| request_hash | text | NO |  |
| reference | text | NO |  |
| created_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.integration_outbox

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| event_type | text | NO |  |
| aggregate_type | text | NO |  |
| aggregate_id | text | NO |  |
| payload | jsonb | NO | '{}'::jsonb |
| created_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.invoice_discounts

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| line_id | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |
| bill_id | text | NO |  |
| amount | numeric | NO |  |
| reason | text | NO |  |
| created_by | text | NO |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.invoice_line_context

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| line_id | text | NO |  |
| service_price_id | uuid | YES |  |
| medicine_id | text | YES |  |
| quantity | numeric | NO |  |
| unit_price | numeric | NO |  |
| currency | character | NO | 'INR'::bpchar |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.medication_administrations

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| prescription_id | text | NO |  |
| patient_id | text | NO |  |
| quantity | integer | NO |  |
| provided_by | text | NO |  |
| provided_at | timestamp with time zone | NO | now() |
| note | text | NO |  |
| retry_key | uuid | NO |  |


### hospitalflow.medication_doses

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| prescription_id | text | NO |  |
| admission_id | text | YES |  |
| patient_id | text | NO |  |
| dose | text | NO |  |
| quantity | integer | NO |  |
| scheduled_at | timestamp with time zone | NO |  |
| created_by | text | NO |  |
| status | text | NO | 'Scheduled'::text |
| actual_at | timestamp with time zone | YES |  |
| recorded_by | text | YES |  |
| recorded_at | timestamp with time zone | YES |  |
| remarks | text | YES |  |
| administration_id | uuid | YES |  |


### hospitalflow.medicine_batch_holds

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| medicine_id | text | NO |  |
| reason | text | NO |  |
| held_by | text | NO |  |
| held_at | timestamp with time zone | NO | now() |
| released_by | text | YES |  |
| released_at | timestamp with time zone | YES |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.medicine_batches

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| name | text | NO |  |
| batch | text | NO |  |
| expiry | date | NO |  |
| quantity | integer | NO |  |
| reorder | integer | NO |  |
| price | numeric | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.medicine_price_history

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| medicine_id | text | NO |  |
| old_price | numeric | NO |  |
| new_price | numeric | NO |  |
| reason | text | NO |  |
| created_by | text | NO |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.network_operators

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| user_id | text | NO |  |


### hospitalflow.notes

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| patient_id | text | NO |  |
| text | text | NO |  |
| kind | text | NO |  |
| at | timestamp with time zone | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.notification_acknowledgements

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| notification_id | text | NO |  |
| user_id | text | NO |  |
| reason | text | NO |  |
| at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.notifications

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| rule | text | NO |  |
| reference | text | NO |  |
| title | text | NO |  |
| message | text | NO |  |
| target | text | NO |  |
| opened_at | timestamp with time zone | NO | now() |
| resolved_at | timestamp with time zone | YES |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.outbox_delivery

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| event_id | uuid | NO |  |
| status | text | NO | 'Pending'::text |
| attempts | integer | NO | 0 |
| next_attempt_at | timestamp with time zone | NO | now() |
| lease_token | uuid | YES |  |
| lease_until | timestamp with time zone | YES |  |
| last_error_code | text | YES |  |
| delivered_at | timestamp with time zone | YES |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.patient_access_grants

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| user_id | text | NO |  |
| patient_id | text | NO |  |
| purpose | text | NO |  |
| expires_at | timestamp with time zone | NO |  |
| granted_by | text | NO |  |
| created_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.patient_accounts

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| user_id | text | NO |  |
| patient_id | text | NO |  |
| must_change_password | boolean | NO | true |
| temporary_expires_at | timestamp with time zone | NO |  |
| invited_at | timestamp with time zone | NO | now() |
| activated_at | timestamp with time zone | YES |  |


### hospitalflow.patient_consents

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| patient_id | text | NO |  |
| purpose | text | NO |  |
| granted_at | timestamp with time zone | NO |  |
| expires_at | timestamp with time zone | YES |  |
| revoked_at | timestamp with time zone | YES |  |
| evidence_reference | text | NO |  |
| recorded_by | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.patient_contacts

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| patient_id | text | NO |  |
| name | text | NO |  |
| relationship | text | NO |  |
| phone | text | NO |  |
| is_emergency | boolean | NO | false |
| created_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.patient_hospitals

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| patient_id | text | NO |  |
| hospital_id | text | NO |  |
| registered_at | timestamp with time zone | NO | now() |


### hospitalflow.patient_login_challenges

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| token_hash | text | NO |  |
| user_id | text | NO |  |
| expires_at | timestamp with time zone | NO |  |
| attempts | integer | NO | 0 |
| consumed_at | timestamp with time zone | YES |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.patient_sms

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| user_id | text | NO |  |
| encrypted_message | text | NO |  |
| status | text | NO | 'Pending'::text |
| created_at | timestamp with time zone | NO | now() |
| completed_at | timestamp with time zone | YES |  |


### hospitalflow.patients

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| name | text | NO |  |
| dob | date | NO |  |
| sex | text | NO |  |
| phone | text | NO |  |
| created | timestamp with time zone | NO |  |
| registration_id | text | NO |  |
| email | text | YES |  |
| address | text | YES |  |
| emergency_contact | text | YES |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.payment_reversals

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| payment_id | text | NO |  |
| amount | numeric | NO |  |
| reason | text | NO |  |
| approved_by | text | NO |  |
| at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.payments

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| bill_id | text | NO |  |
| amount | numeric | NO |  |
| method | text | NO |  |
| at | timestamp with time zone | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.person_profiles

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| user_id | text | NO |  |
| doctor_id | text | YES |  |
| mobile | text | YES |  |
| dob | date | YES |  |
| sex | text | YES |  |
| address | text | YES |  |
| department | text | YES |  |
| job_title | text | YES |  |
| occupation | text | YES |  |
| created_at | timestamp with time zone | NO | now() |
| updated_at | timestamp with time zone | NO | now() |


### hospitalflow.pharmacy_requests

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| prescription_id | text | NO |  |
| patient_id | text | NO |  |
| requested_by | text | NO |  |
| at | timestamp with time zone | NO | now() |
| comments | text | NO |  |


### hospitalflow.portal_payments

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| bill_id | text | NO |  |
| payment_id | text | NO |  |
| patient_id | text | NO |  |
| amount | numeric | NO |  |
| method | text | NO |  |
| mode | text | NO |  |
| paid_by | text | NO |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.prescription_authors

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| prescription_id | text | NO |  |
| created_by | text | NO |  |
| created_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.prescription_dispensations

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| prescription_id | text | NO |  |
| movement_id | text | NO |  |
| bill_id | text | NO |  |
| dispensed_by | text | NO |  |
| at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.prescription_visits

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| prescription_id | text | NO |  |
| appointment_id | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.prescriptions

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| patient_id | text | NO |  |
| medicine_id | text | NO |  |
| quantity | integer | NO |  |
| instructions | text | NO |  |
| status | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |
| created_at | timestamp with time zone | YES | now() |


### hospitalflow.provider_absences

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| doctor_id | text | NO |  |
| starts_at | timestamp with time zone | NO |  |
| ends_at | timestamp with time zone | NO |  |
| reason_code | text | NO |  |
| approved_by | text | NO |  |
| cancelled_at | timestamp with time zone | YES |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.provider_sessions

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| doctor_id | text | NO |  |
| starts_at | timestamp with time zone | NO |  |
| ends_at | timestamp with time zone | NO |  |
| capacity | integer | NO | 1 |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.purchase_order_lines

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| purchase_order_id | uuid | NO |  |
| medicine_id | text | NO |  |
| quantity | integer | NO |  |
| unit_cost | numeric | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.purchase_orders

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| supplier_id | uuid | NO |  |
| number | text | NO |  |
| status | USER-DEFINED | NO | 'Draft'::hospitalflow.purchase_status |
| created_by | text | NO |  |
| approved_by | text | YES |  |
| created_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.referrals

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| patient_id | text | NO |  |
| source_hospital_id | text | NO |  |
| target_hospital_id | text | NO |  |
| target_doctor_id | text | YES |  |
| referred_by | text | NO |  |
| reason | text | NO |  |
| status | text | NO | 'Pending'::text |
| created_at | timestamp with time zone | NO | now() |
| resolved_at | timestamp with time zone | YES |  |
| resolved_by | text | YES |  |
| resolution_note | text | YES |  |


### hospitalflow.roles

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| name | text | NO |  |


### hospitalflow.row_history

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | bigint | NO |  |
| table_name | text | NO |  |
| record_id | text | NO |  |
| operation | text | NO |  |
| changed_columns | ARRAY | NO |  |
| actor_id | text | YES |  |
| correlation_id | text | YES |  |
| occurred_at | timestamp with time zone | NO | now() |
| database_user | text | YES | SESSION_USER |
| transaction_id | bigint | YES | txid_current() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.schema_versions

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| version | text | NO |  |
| checksum | text | NO |  |
| applied_at | timestamp with time zone | NO | now() |


### hospitalflow.service_catalog

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| code | text | NO |  |
| name | text | NO |  |
| department | text | YES |  |
| category | text | NO |  |
| active | boolean | NO | true |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.service_prices

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| service_id | uuid | NO |  |
| amount | numeric | NO |  |
| currency | character | NO | 'INR'::bpchar |
| effective_from | timestamp with time zone | NO |  |
| effective_to | timestamp with time zone | YES |  |
| created_by | text | YES |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.sessions

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| user_id | text | NO |  |
| ticket | bytea | NO |  |
| expires_at | timestamp with time zone | NO |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.staff_attendance

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| user_id | text | NO |  |
| day | date | NO |  |
| status | text | NO |  |
| check_in | timestamp with time zone | YES |  |
| check_out | timestamp with time zone | YES |  |
| marked_by | text | NO |  |
| approval_status | text | NO | 'Pending'::text |
| reviewed_by | text | YES |  |
| reviewed_at | timestamp with time zone | YES |  |
| review_note | text | NO | ''::text |
| submitted_at | timestamp with time zone | NO | now() |
| total_seconds | bigint | YES |  |


### hospitalflow.staff_leaves

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| hospital_id | text | NO | hf_security.current_hospital() |
| user_id | text | NO |  |
| starts_on | date | NO |  |
| ends_on | date | NO |  |
| reason | text | NO |  |
| status | text | NO | 'Pending'::text |
| created_at | timestamp with time zone | NO | now() |
| resolved_by | text | YES |  |


### hospitalflow.staff_members

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| user_id | text | YES |  |
| doctor_id | text | YES |  |
| employee_number | text | NO |  |
| department | text | NO |  |
| job_title | text | NO |  |
| active | boolean | NO | true |
| created_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.staff_onboarding

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| user_id | text | NO |  |
| must_change_password | boolean | NO | true |
| expires_at | timestamp with time zone | NO | (now() + '24:00:00'::interval) |
| activated_at | timestamp with time zone | YES |  |


### hospitalflow.stock_movements

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| medicine_id | text | NO |  |
| quantity | integer | NO |  |
| reason | text | NO |  |
| at | timestamp with time zone | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.stock_reservations

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| prescription_id | text | NO |  |
| medicine_id | text | NO |  |
| quantity | integer | NO |  |
| status | text | NO |  |
| created_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.suppliers

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| code | text | NO |  |
| name | text | NO |  |
| contact_email | text | YES |  |
| contact_phone | text | YES |  |
| active | boolean | NO | true |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.system_settings

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| key | text | NO |  |
| value | text | NO |  |


### hospitalflow.user_departments

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| user_id | text | NO |  |
| department | text | NO |  |
| hospital_id | text | NO | hf_security.current_hospital() |


### hospitalflow.user_permissions

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| user_id | text | NO |  |
| permission | text | NO |  |


### hospitalflow.user_preferences

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| user_id | text | NO |  |
| theme | text | NO |  |
| updated_at | timestamp with time zone | NO | now() |
| hospital_id | text | YES |  |


### hospitalflow.users

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| name | text | NO |  |
| email | text | NO |  |
| role | text | NO |  |
| password_hash | text | NO |  |
| active | boolean | NO | true |
| created_at | timestamp with time zone | NO | now() |
| email_confirmed | boolean | NO | true |
| registration_id | text | NO |  |


### hospitalflow.wards

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| name | text | NO |  |
| department | text | YES |  |
| active | boolean | NO | true |


### hospitalflow.work_tasks

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| assigned_to | text | NO |  |
| created_by | text | NO |  |
| title | text | NO |  |
| location | text | NO |  |
| due_at | timestamp with time zone | NO |  |
| status | text | NO | 'Assigned'::text |
| created_at | timestamp with time zone | NO | now() |
| updated_at | timestamp with time zone | NO | now() |
| hospital_id | text | NO | hf_security.current_hospital() |

## Stored procedures and functions

| Schema | Routine | Kind | Arguments | Security definer |
| --- | --- | --- | --- | --- |
| hf_api | accrue_due_care_charges | FUNCTION |  | True |
| hf_api | accrue_stay_charges | FUNCTION | p_admission text, p_strict boolean | True |
| hf_api | admit_patient | PROCEDURE | INOUT p_id text, IN p_patient text, IN p_bed text, IN p_reason text | False |
| hf_api | approve_purchase_order | PROCEDURE | IN p_id uuid | False |
| hf_api | billing_receipt | FUNCTION | p_bill text | True |
| hf_api | book_appointment | PROCEDURE | INOUT p_id text, IN p_patient text, IN p_doctor text, IN p_at timestamp with time zone, IN p_type text | False |
| hf_api | booking_actor | FUNCTION |  | True |
| hf_api | booking_command | FUNCTION | p_action text, p jsonb, p_test boolean | True |
| hf_api | booking_command_base | FUNCTION | p_action text, p jsonb, p_test boolean | True |
| hf_api | booking_slots | FUNCTION | p_doctor text, p_day date, p_exclude text | True |
| hf_api | booking_state | FUNCTION |  | True |
| hf_api | booking_state_base | FUNCTION |  | True |
| hf_api | can_book_provider | FUNCTION | p_doctor text | True |
| hf_api | can_review_attendance | FUNCTION |  | True |
| hf_api | care_command | FUNCTION | p_action text, p jsonb, p_key uuid, p_hash text | True |
| hf_api | care_event | FUNCTION | p_patient text, p_activity text, p_comments text, p_ref text, p_details jsonb | True |
| hf_api | care_lab_orders | FUNCTION |  | True |
| hf_api | care_line_category | FUNCTION | p_line text | True |
| hf_api | care_stays | FUNCTION |  | True |
| hf_api | claim_outbox | FUNCTION | p_limit integer, p_lease_seconds integer | False |
| hf_api | complete_outbox | PROCEDURE | IN p_event uuid, IN p_token uuid, IN p_success boolean, IN p_error_code text | False |
| hf_api | create_bill | PROCEDURE | INOUT p_id text, IN p_patient text, IN p_description text, IN p_amount numeric | False |
| hf_api | discharge_patient | PROCEDURE | IN p_id text, IN p_summary text | False |
| hf_api | dispense_prescription | PROCEDURE | IN p_id text, INOUT p_bill text | False |
| hf_api | doctor_unavailable | FUNCTION | p_doctor text, p_at timestamp with time zone | True |
| hf_api | enterprise_command | FUNCTION | p_action text, p jsonb, p_key uuid, p_hash text, p_test boolean | True |
| hf_api | execute | FUNCTION | p_action text, p_payload jsonb, p_key uuid, p_hash text | False |
| hf_api | finance_state | FUNCTION |  | True |
| hf_api | hospital_leave_calendar | FUNCTION |  | True |
| hf_api | hospital_today | FUNCTION |  | False |
| hf_api | invalidate_care_approval | FUNCTION | p_patient text, p_reason text | True |
| hf_api | invoice_tax_detail | FUNCTION | p_bill text | True |
| hf_api | manage_staff_attendance | FUNCTION | p jsonb | True |
| hf_api | medication_care | FUNCTION |  | True |
| hf_api | new_id | FUNCTION | p_prefix text | False |
| hf_api | person_id | FUNCTION | p_prefix text | False |
| hf_api | positive_number | FUNCTION | p_body jsonb, p_key text, p_integer boolean | False |
| hf_api | post_adjustment | PROCEDURE | IN p_bill text, IN p_amount numeric, IN p_reason text, INOUT p_id text | False |
| hf_api | post_payment | PROCEDURE | IN p_bill text, IN p_amount numeric, IN p_method text, INOUT p_id text | False |
| hf_api | post_service_charge | PROCEDURE | IN p_bill text, IN p_service uuid, IN p_quantity numeric, INOUT p_id text | False |
| hf_api | prescribe_visit | FUNCTION | p_appointment text, p_payload jsonb, p_key uuid, p_hash text | True |
| hf_api | provide_medication | FUNCTION | p_prescription text, p_quantity integer, p_note text, p_key uuid | True |
| hf_api | receive_purchase_order | PROCEDURE | IN p_order uuid, IN p_reference text, IN p_lines jsonb, INOUT p_id uuid | False |
| hf_api | receive_stock | PROCEDURE | INOUT p_movement text, IN p_medicine text, IN p_quantity integer, IN p_reason text | False |
| hf_api | record_release | FUNCTION | p jsonb | True |
| hf_api | refresh_finance_charges | FUNCTION |  | True |
| hf_api | required_text | FUNCTION | p_body jsonb, p_key text, p_max integer | False |
| hf_api | reserve_prescription | PROCEDURE | IN p_prescription text, INOUT p_id uuid | False |
| hf_api | reverse_payment | PROCEDURE | IN p_payment text, IN p_amount numeric, IN p_reason text, INOUT p_id uuid | False |
| hf_api | save_patient | PROCEDURE | INOUT p_id text, IN p_name text, IN p_dob date, IN p_sex text, IN p_phone text | False |
| hf_api | select_booking_hospital | FUNCTION | p_hospital text | True |
| hf_api | set_appointment_status | PROCEDURE | IN p_id text, IN p_status text | False |
| hf_api | snapshot_invoice_tax | FUNCTION | p_bill text | True |
| hf_api | transfer_patient | PROCEDURE | IN p_id text, IN p_bed text, IN p_reason text | False |
| hf_api | year_calendar | FUNCTION | p_year integer | True |
| hf_ops | capture_ddl | FUNCTION |  | True |
| hf_ops | capture_drop | FUNCTION |  | True |
| hf_ops | finish_backup | PROCEDURE | IN p_id uuid, IN p_success boolean, IN p_reference text, IN p_bytes bigint, IN p_sha256 text | True |
| hf_ops | prevent_history_change | FUNCTION |  | False |
| hf_ops | protect_run_evidence | FUNCTION |  | False |
| hf_ops | record_restore_drill | PROCEDURE | IN p_backup uuid, IN p_passed boolean, IN p_evidence text, IN p_seconds integer | True |
| hf_ops | refresh_alerts | PROCEDURE |  | True |
| hf_ops | run_due_jobs | PROCEDURE | IN p_limit integer | True |
| hf_ops | start_backup | PROCEDURE | INOUT p_id uuid | True |
| hf_ops | validate_database | FUNCTION |  | True |
| hf_ops | worker_heartbeat | PROCEDURE | IN p_worker text, IN p_status text | True |
| hf_security | actor_id | FUNCTION |  | False |
| hf_security | audit | FUNCTION | p_action text, p_reference text | False |
| hf_security | auto_hospital_member | FUNCTION |  | True |
| hf_security | bill_completed_care_lab | FUNCTION |  | True |
| hf_security | billing_pharmacy_only | FUNCTION |  | False |
| hf_security | billing_staff | FUNCTION |  | True |
| hf_security | can_access_encounter | FUNCTION | p_encounter uuid | True |
| hf_security | can_access_patient | FUNCTION | p_patient text | True |
| hf_security | can_read_care | FUNCTION | p_patient text | True |
| hf_security | can_read_invoice | FUNCTION | p_bill text | True |
| hf_security | capture_care_activity | FUNCTION |  | True |
| hf_security | capture_invoice_tax | FUNCTION |  | True |
| hf_security | care_role | FUNCTION | p_roles text[] | True |
| hf_security | current_hospital | FUNCTION |  | False |
| hf_security | directory_providers | FUNCTION |  | True |
| hf_security | enrolled_patient | FUNCTION | p_patient text | True |
| hf_security | guard_billing_discount | FUNCTION |  | True |
| hf_security | guard_care_discharge | FUNCTION |  | True |
| hf_security | guard_clinical_author | FUNCTION |  | True |
| hf_security | guard_doctor_visit | FUNCTION |  | True |
| hf_security | guard_dose_outcome | FUNCTION |  | False |
| hf_security | guard_hospital_row | FUNCTION |  | True |
| hf_security | guard_patient_account | FUNCTION |  | True |
| hf_security | is_visit_doctor | FUNCTION | p_doctor text | True |
| hf_security | medicine_invoice | FUNCTION | p_bill text | True |
| hf_security | own_patient | FUNCTION | p_patient text | False |
| hf_security | own_related | FUNCTION | p_kind text, p_id text | True |
| hf_security | patient_email_guard | FUNCTION |  | True |
| hf_security | protect_account | FUNCTION |  | False |
| hf_security | referral_patient_identity | FUNCTION |  | True |
| hf_security | registration_identity | FUNCTION |  | False |
| hf_security | reopen_care_review | FUNCTION |  | True |
| hf_security | require_actor | FUNCTION | p_roles text[] | True |
| hf_security | separate_doctor_permission | FUNCTION |  | True |
| hf_security | validate_person_profile | FUNCTION |  | False |
| hospitalflow | booking_cancel_refund | FUNCTION |  | True |
| hospitalflow | complete_follow_up | FUNCTION |  | True |
| hospitalflow | enqueue_change | FUNCTION |  | True |
| hospitalflow | guard_booking_department | FUNCTION |  | False |
| hospitalflow | maintain_bed_history | FUNCTION |  | True |
| hospitalflow | prevent_ledger_changes | FUNCTION |  | False |
| hospitalflow | record_row_history | FUNCTION |  | True |
| hospitalflow | sync_encounter | FUNCTION |  | True |
| hospitalflow | sync_patient_registration | FUNCTION |  | True |
| hospitalflow | validate_absence | FUNCTION |  | False |
| hospitalflow | validate_appointment_overlap | FUNCTION |  | False |
| hospitalflow | validate_appointment_schedule | FUNCTION |  | False |
| hospitalflow | validate_discharge_readiness | FUNCTION |  | False |
| hospitalflow | validate_dispense_expiry | FUNCTION |  | False |
| hospitalflow | validate_dispense_trace | FUNCTION |  | False |
| hospitalflow | validate_invoice_balance | FUNCTION |  | False |
| hospitalflow | validate_occupancy | FUNCTION |  | False |
| hospitalflow | validate_patient_identity | FUNCTION |  | False |
| hospitalflow | validate_payment_reversal | FUNCTION |  | False |
| hospitalflow | validate_prescription_state | FUNCTION |  | False |
| hospitalflow | validate_provider_session | FUNCTION |  | False |
| hospitalflow | validate_service_price | FUNCTION |  | False |
| hospitalflow | validate_stock_balance | FUNCTION |  | False |

## Views, aliases and materialized reports

| Schema | Type | Object |
| --- | --- | --- |
| hf_ops | EVENT TRIGGER | hospitalflow_ddl_audit |
| hf_ops | EVENT TRIGGER | hospitalflow_drop_audit |
| hf_reporting | MATERIALIZED VIEW | daily_collections |
| hospitalflow | POLICY | activity_log.hospital_fence |
| hospitalflow | POLICY | admission_events.hospital_fence |
| hospitalflow | POLICY | admissions.hospital_fence |
| hospitalflow | POLICY | application_releases.release_admin_read |
| hospitalflow | POLICY | appointment_bookings.hospital_fence |
| hospitalflow | POLICY | appointments.hospital_fence |
| hospitalflow | POLICY | bed_assignments.hospital_fence |
| hospitalflow | POLICY | beds.hospital_fence |
| hospitalflow | POLICY | bill_lines.hospital_fence |
| hospitalflow | POLICY | billing_tax_settings.hospital_read |
| hospitalflow | POLICY | billing_tax_snapshots.hospital_read |
| hospitalflow | POLICY | bills.hospital_fence |
| hospitalflow | POLICY | booking_events.booking_event_fence |
| hospitalflow | POLICY | booking_settings.hospital_fence |
| hospitalflow | POLICY | care_charge_entries.care_financial_reader |
| hospitalflow | POLICY | care_charge_entries.hospital_scope |
| hospitalflow | POLICY | care_discharge_reviews.clinical_reader |
| hospitalflow | POLICY | care_discharge_reviews.hospital_scope |
| hospitalflow | POLICY | care_events.clinical_reader |
| hospitalflow | POLICY | care_events.hospital_scope |
| hospitalflow | POLICY | care_invoices.hospital_scope |
| hospitalflow | POLICY | care_lab_charges.care_financial_reader |
| hospitalflow | POLICY | care_lab_charges.hospital_scope |
| hospitalflow | POLICY | care_managed_orders.clinical_reader |
| hospitalflow | POLICY | care_managed_orders.hospital_scope |
| hospitalflow | POLICY | care_observations.clinical_reader |
| hospitalflow | POLICY | care_observations.hospital_scope |
| hospitalflow | POLICY | care_plans.clinical_reader |
| hospitalflow | POLICY | care_plans.hospital_scope |
| hospitalflow | POLICY | care_rates.hospital_scope |
| hospitalflow | POLICY | clinical_orders.encounter_scope |
| hospitalflow | POLICY | clinical_orders.hospital_fence |
| hospitalflow | POLICY | discharge_tasks.hospital_fence |
| hospitalflow | POLICY | doctors.hospital_fence |
| hospitalflow | POLICY | encounters.hospital_fence |
| hospitalflow | POLICY | follow_ups.hospital_fence |
| hospitalflow | POLICY | follow_ups.patient_scope |
| hospitalflow | POLICY | goods_receipt_lines.hospital_fence |
| hospitalflow | POLICY | goods_receipts.hospital_fence |
| hospitalflow | POLICY | hospital_holidays.hospital_read |
| hospitalflow | POLICY | idempotency_keys.hospital_fence |
| hospitalflow | POLICY | integration_outbox.hospital_fence |
| hospitalflow | POLICY | invoice_discounts.hospital_read |
| hospitalflow | POLICY | invoice_line_context.hospital_fence |
| hospitalflow | POLICY | medication_administrations.medication_insert |
| hospitalflow | POLICY | medication_administrations.medication_read |
| hospitalflow | POLICY | medication_doses.clinical_reader |
| hospitalflow | POLICY | medication_doses.hospital_scope |
| hospitalflow | POLICY | medicine_batch_holds.hospital_fence |
| hospitalflow | POLICY | medicine_batches.hospital_fence |
| hospitalflow | POLICY | medicine_price_history.hospital_read |
| hospitalflow | POLICY | notes.hospital_fence |
| hospitalflow | POLICY | notification_acknowledgements.hospital_fence |
| hospitalflow | POLICY | notifications.hospital_fence |
| hospitalflow | POLICY | outbox_delivery.hospital_fence |
| hospitalflow | POLICY | patient_access_grants.hospital_fence |
| hospitalflow | POLICY | patient_consents.hospital_fence |
| hospitalflow | POLICY | patient_consents.patient_scope |
| hospitalflow | POLICY | patient_contacts.hospital_fence |
| hospitalflow | POLICY | patient_contacts.patient_scope |
| hospitalflow | POLICY | patients.hospital_fence |
| hospitalflow | POLICY | payment_reversals.hospital_fence |
| hospitalflow | POLICY | payments.hospital_fence |
| hospitalflow | POLICY | pharmacy_requests.care_financial_reader |
| hospitalflow | POLICY | pharmacy_requests.hospital_scope |
| hospitalflow | POLICY | portal_payments.hospital_read |
| hospitalflow | POLICY | prescription_authors.hospital_fence |
| hospitalflow | POLICY | prescription_dispensations.hospital_fence |
| hospitalflow | POLICY | prescription_visits.visit_prescription_scope |
| hospitalflow | POLICY | prescriptions.hospital_fence |
| hospitalflow | POLICY | provider_absences.hospital_fence |
| hospitalflow | POLICY | provider_sessions.hospital_fence |
| hospitalflow | POLICY | purchase_order_lines.hospital_fence |
| hospitalflow | POLICY | purchase_orders.hospital_fence |
| hospitalflow | POLICY | referrals.referral_scope |
| hospitalflow | POLICY | row_history.hospital_fence |
| hospitalflow | POLICY | service_catalog.hospital_fence |
| hospitalflow | POLICY | service_prices.hospital_fence |
| hospitalflow | POLICY | staff_attendance.hospital_fence |
| hospitalflow | POLICY | staff_leaves.hospital_fence |
| hospitalflow | POLICY | staff_members.hospital_fence |
| hospitalflow | POLICY | stock_movements.hospital_fence |
| hospitalflow | POLICY | stock_reservations.hospital_fence |
| hospitalflow | POLICY | suppliers.hospital_fence |
| hospitalflow | POLICY | user_departments.hospital_fence |
| hospitalflow | POLICY | work_tasks.hospital_fence |
| hf_ops | SEQUENCE | schema_change_events_id_seq |
| hospitalflow | SEQUENCE | bed_assignments_id_seq |
| hospitalflow | SEQUENCE | booking_events_id_seq |
| hospitalflow | SEQUENCE | data_protection_keys_id_seq |
| hospitalflow | SEQUENCE | document_number |
| hospitalflow | SEQUENCE | person_number |
| hospitalflow | SEQUENCE | row_history_id_seq |
| hospitalflow | TYPE | encounter_kind |
| hospitalflow | TYPE | purchase_status |
| hf_api | VIEW | inventory |
| hf_ops | VIEW | job_health |
| hf_ops | VIEW | latest_integrity_findings |
| hf_ops | VIEW | object_inventory |
| hf_ops | VIEW | outbox_health |
| hf_reporting | VIEW | bed_status |
| hf_reporting | VIEW | inventory |
| hf_reporting | VIEW | open_invoices |
| hf_reporting | VIEW | purchase_order_progress |
| hf_reporting | VIEW | stock_ledger |
| hospitalflow | VIEW | bed_occupancy |
| hospitalflow | VIEW | invoice_balances |
| hospitalflow | VIEW | payment_reversal_receipts |
| hospitalflow | VIEW | stock_alerts |

## Trigger inventory

| Schema | Table and trigger |
| --- | --- |
| hf_ops | backup_runs.immutable_completed_backup |
| hf_ops | integrity_findings.immutable_findings |
| hf_ops | job_definitions.audit_job_configuration |
| hf_ops | job_runs.immutable_completed_run |
| hf_ops | restore_drills.immutable_restore_evidence |
| hf_ops | schema_change_events.immutable_ddl_audit |
| hospitalflow | activity_log.immutable_ledger |
| hospitalflow | activity_log.z_hospital_guard |
| hospitalflow | admission_events.care_activity |
| hospitalflow | admission_events.record_history |
| hospitalflow | admission_events.z_hospital_guard |
| hospitalflow | admissions.admission_consistency |
| hospitalflow | admissions.bed_history |
| hospitalflow | admissions.care_activity |
| hospitalflow | admissions.care_discharge_guard |
| hospitalflow | admissions.discharge_readiness |
| hospitalflow | admissions.encounter_sync |
| hospitalflow | admissions.enqueue_integration_event |
| hospitalflow | admissions.record_history |
| hospitalflow | admissions.z_hospital_guard |
| hospitalflow | application_releases.immutable_ledger |
| hospitalflow | appointment_bookings.booking_department |
| hospitalflow | appointment_bookings.record_history |
| hospitalflow | appointment_bookings.z_hospital_guard |
| hospitalflow | appointments.appointment_overlap |
| hospitalflow | appointments.appointment_schedule |
| hospitalflow | appointments.booking_cancel_refund |
| hospitalflow | appointments.booking_department |
| hospitalflow | appointments.care_activity |
| hospitalflow | appointments.doctor_visit |
| hospitalflow | appointments.encounter_sync |
| hospitalflow | appointments.enqueue_integration_event |
| hospitalflow | appointments.follow_up_completion |
| hospitalflow | appointments.record_history |
| hospitalflow | appointments.z_hospital_guard |
| hospitalflow | bed_assignments.z_hospital_guard |
| hospitalflow | beds.bed_consistency |
| hospitalflow | beds.record_history |
| hospitalflow | beds.z_hospital_guard |
| hospitalflow | bill_lines.capture_inclusive_tax |
| hospitalflow | bill_lines.immutable_ledger |
| hospitalflow | bill_lines.line_balance |
| hospitalflow | bill_lines.record_history |
| hospitalflow | bill_lines.z_hospital_guard |
| hospitalflow | billing_tax_settings.immutable_ledger |
| hospitalflow | billing_tax_settings.record_history |
| hospitalflow | billing_tax_settings.z_hospital_guard |
| hospitalflow | billing_tax_snapshots.immutable_ledger |
| hospitalflow | billing_tax_snapshots.record_history |
| hospitalflow | billing_tax_snapshots.z_hospital_guard |
| hospitalflow | bills.record_history |
| hospitalflow | bills.z_hospital_guard |
| hospitalflow | booking_events.immutable_ledger |
| hospitalflow | booking_settings.z_hospital_guard |
| hospitalflow | care_charge_entries.immutable_ledger |
| hospitalflow | care_charge_entries.record_history |
| hospitalflow | care_charge_entries.z_hospital_guard |
| hospitalflow | care_command_keys.immutable_ledger |
| hospitalflow | care_discharge_reviews.record_history |
| hospitalflow | care_discharge_reviews.z_hospital_guard |
| hospitalflow | care_events.immutable_ledger |
| hospitalflow | care_events.record_history |
| hospitalflow | care_events.z_hospital_guard |
| hospitalflow | care_extra_categories.immutable_ledger |
| hospitalflow | care_invoices.immutable_ledger |
| hospitalflow | care_invoices.record_history |
| hospitalflow | care_invoices.z_hospital_guard |
| hospitalflow | care_lab_charges.immutable_ledger |
| hospitalflow | care_observations.immutable_ledger |
| hospitalflow | care_observations.record_history |
| hospitalflow | care_observations.reopen_care_review |
| hospitalflow | care_observations.z_hospital_guard |
| hospitalflow | care_plans.record_history |
| hospitalflow | care_plans.reopen_care_review |
| hospitalflow | care_plans.z_hospital_guard |
| hospitalflow | care_rates.immutable_ledger |
| hospitalflow | care_rates.record_history |
| hospitalflow | care_rates.z_hospital_guard |
| hospitalflow | clinical_orders.care_lab_billing |
| hospitalflow | clinical_orders.clinical_author |
| hospitalflow | clinical_orders.record_history |
| hospitalflow | clinical_orders.z_hospital_guard |
| hospitalflow | departments.record_history |
| hospitalflow | discharge_tasks.record_history |
| hospitalflow | discharge_tasks.z_hospital_guard |
| hospitalflow | doctors.record_history |
| hospitalflow | doctors.registration_identity |
| hospitalflow | doctors.z_hospital_guard |
| hospitalflow | encounters.record_history |
| hospitalflow | encounters.z_hospital_guard |
| hospitalflow | follow_ups.clinical_author |
| hospitalflow | follow_ups.record_history |
| hospitalflow | follow_ups.z_hospital_guard |
| hospitalflow | goods_receipt_lines.immutable_ledger |
| hospitalflow | goods_receipt_lines.record_history |
| hospitalflow | goods_receipt_lines.z_hospital_guard |
| hospitalflow | goods_receipts.immutable_ledger |
| hospitalflow | goods_receipts.record_history |
| hospitalflow | goods_receipts.z_hospital_guard |
| hospitalflow | hospital_holidays.record_history |
| hospitalflow | hospital_holidays.z_hospital_guard |
| hospitalflow | hospital_memberships.record_history |
| hospitalflow | hospital_profile.record_history |
| hospitalflow | hospitals.record_history |
| hospitalflow | idempotency_keys.z_hospital_guard |
| hospitalflow | integration_outbox.immutable_ledger |
| hospitalflow | integration_outbox.z_hospital_guard |
| hospitalflow | invoice_discounts.billing_discount_editor |
| hospitalflow | invoice_discounts.immutable_ledger |
| hospitalflow | invoice_discounts.record_history |
| hospitalflow | invoice_discounts.z_hospital_guard |
| hospitalflow | invoice_line_context.immutable_ledger |
| hospitalflow | invoice_line_context.record_history |
| hospitalflow | invoice_line_context.z_hospital_guard |
| hospitalflow | medication_administrations.care_activity |
| hospitalflow | medication_administrations.immutable_ledger |
| hospitalflow | medication_administrations.record_history |
| hospitalflow | medication_administrations.reopen_care_review |
| hospitalflow | medication_administrations.z_hospital_guard |
| hospitalflow | medication_doses.immutable_outcome |
| hospitalflow | medication_doses.record_history |
| hospitalflow | medication_doses.reopen_care_review |
| hospitalflow | medication_doses.z_hospital_guard |
| hospitalflow | medicine_batch_holds.record_history |
| hospitalflow | medicine_batch_holds.z_hospital_guard |
| hospitalflow | medicine_batches.record_history |
| hospitalflow | medicine_batches.stock_batch_balance |
| hospitalflow | medicine_batches.z_hospital_guard |
| hospitalflow | medicine_price_history.immutable_ledger |
| hospitalflow | medicine_price_history.record_history |
| hospitalflow | medicine_price_history.z_hospital_guard |
| hospitalflow | notes.care_activity |
| hospitalflow | notes.clinical_author |
| hospitalflow | notes.record_history |
| hospitalflow | notes.reopen_care_review |
| hospitalflow | notes.z_hospital_guard |
| hospitalflow | notification_acknowledgements.immutable_ledger |
| hospitalflow | notification_acknowledgements.record_history |
| hospitalflow | notification_acknowledgements.z_hospital_guard |
| hospitalflow | notifications.z_hospital_guard |
| hospitalflow | outbox_delivery.z_hospital_guard |
| hospitalflow | patient_access_grants.record_history |
| hospitalflow | patient_access_grants.z_hospital_guard |
| hospitalflow | patient_accounts.patient_link_guard |
| hospitalflow | patient_accounts.record_history |
| hospitalflow | patient_accounts.sync_registration |
| hospitalflow | patient_consents.record_history |
| hospitalflow | patient_consents.z_hospital_guard |
| hospitalflow | patient_contacts.record_history |
| hospitalflow | patient_contacts.z_hospital_guard |
| hospitalflow | patient_hospitals.record_history |
| hospitalflow | patients.auto_hospital |
| hospitalflow | patients.care_activity |
| hospitalflow | patients.enqueue_integration_event |
| hospitalflow | patients.linked_email |
| hospitalflow | patients.patient_identity |
| hospitalflow | patients.record_history |
| hospitalflow | patients.registration_identity |
| hospitalflow | patients.z_hospital_guard |
| hospitalflow | payment_reversals.enqueue_integration_event |
| hospitalflow | payment_reversals.immutable_ledger |
| hospitalflow | payment_reversals.payment_reversal_limit |
| hospitalflow | payment_reversals.record_history |
| hospitalflow | payment_reversals.z_hospital_guard |
| hospitalflow | payments.enqueue_integration_event |
| hospitalflow | payments.immutable_ledger |
| hospitalflow | payments.payment_balance |
| hospitalflow | payments.record_history |
| hospitalflow | payments.z_hospital_guard |
| hospitalflow | person_profiles.record_history |
| hospitalflow | person_profiles.validate_profile |
| hospitalflow | pharmacy_requests.immutable_ledger |
| hospitalflow | pharmacy_requests.record_history |
| hospitalflow | pharmacy_requests.z_hospital_guard |
| hospitalflow | portal_payments.immutable_ledger |
| hospitalflow | portal_payments.record_history |
| hospitalflow | portal_payments.z_hospital_guard |
| hospitalflow | prescription_authors.record_history |
| hospitalflow | prescription_authors.z_hospital_guard |
| hospitalflow | prescription_dispensations.care_activity |
| hospitalflow | prescription_dispensations.immutable_ledger |
| hospitalflow | prescription_dispensations.record_history |
| hospitalflow | prescription_dispensations.z_hospital_guard |
| hospitalflow | prescription_visits.immutable_ledger |
| hospitalflow | prescription_visits.record_history |
| hospitalflow | prescription_visits.z_hospital_guard |
| hospitalflow | prescriptions.care_activity |
| hospitalflow | prescriptions.clinical_author |
| hospitalflow | prescriptions.dispense_expiry |
| hospitalflow | prescriptions.dispense_trace |
| hospitalflow | prescriptions.enqueue_integration_event |
| hospitalflow | prescriptions.prescription_state |
| hospitalflow | prescriptions.record_history |
| hospitalflow | prescriptions.reopen_care_review |
| hospitalflow | prescriptions.z_hospital_guard |
| hospitalflow | provider_absences.absence_conflict |
| hospitalflow | provider_absences.record_history |
| hospitalflow | provider_absences.z_hospital_guard |
| hospitalflow | provider_sessions.provider_session_overlap |
| hospitalflow | provider_sessions.record_history |
| hospitalflow | provider_sessions.z_hospital_guard |
| hospitalflow | purchase_order_lines.record_history |
| hospitalflow | purchase_order_lines.z_hospital_guard |
| hospitalflow | purchase_orders.enqueue_integration_event |
| hospitalflow | purchase_orders.record_history |
| hospitalflow | purchase_orders.z_hospital_guard |
| hospitalflow | referrals.care_activity |
| hospitalflow | referrals.record_history |
| hospitalflow | row_history.immutable_ledger |
| hospitalflow | row_history.z_hospital_guard |
| hospitalflow | service_catalog.record_history |
| hospitalflow | service_catalog.z_hospital_guard |
| hospitalflow | service_prices.price_effectivity |
| hospitalflow | service_prices.record_history |
| hospitalflow | service_prices.z_hospital_guard |
| hospitalflow | staff_attendance.record_history |
| hospitalflow | staff_attendance.z_hospital_guard |
| hospitalflow | staff_leaves.record_history |
| hospitalflow | staff_leaves.z_hospital_guard |
| hospitalflow | staff_members.record_history |
| hospitalflow | staff_members.z_hospital_guard |
| hospitalflow | stock_movements.immutable_ledger |
| hospitalflow | stock_movements.record_history |
| hospitalflow | stock_movements.stock_movement_balance |
| hospitalflow | stock_movements.z_hospital_guard |
| hospitalflow | stock_reservations.record_history |
| hospitalflow | stock_reservations.reservation_stock_balance |
| hospitalflow | stock_reservations.z_hospital_guard |
| hospitalflow | suppliers.record_history |
| hospitalflow | suppliers.z_hospital_guard |
| hospitalflow | system_settings.record_history |
| hospitalflow | user_departments.record_history |
| hospitalflow | user_departments.z_hospital_guard |
| hospitalflow | user_permissions.patient_grant_guard |
| hospitalflow | user_permissions.record_history |
| hospitalflow | user_permissions.separate_doctor_permission |
| hospitalflow | user_preferences.record_history |
| hospitalflow | users.auto_hospital |
| hospitalflow | users.patient_role_guard |
| hospitalflow | users.protect_account |
| hospitalflow | users.record_history |
| hospitalflow | users.registration_identity |
| hospitalflow | wards.record_history |
| hospitalflow | work_tasks.record_history |
| hospitalflow | work_tasks.z_hospital_guard |

## Constraint inventory

| Schema | Table | Constraint | Definition |
| --- | --- | --- | --- |
| hf_ops | backup_runs | backup_runs_bytes_check | CHECK ((bytes > 0)) |
| hf_ops | backup_runs | backup_runs_check | CHECK (((completed_at IS NULL) OR (completed_at >= started_at))) |
| hf_ops | backup_runs | backup_runs_pkey | PRIMARY KEY (id) |
| hf_ops | backup_runs | backup_runs_sha256_check | CHECK ((sha256 ~ '^[A-Fa-f0-9]{64}$'::text)) |
| hf_ops | backup_runs | backup_runs_status_check | CHECK ((status = ANY (ARRAY['Running'::text, 'Succeeded'::text, 'Failed'::text]))) |
| hf_ops | daily_snapshots | daily_snapshots_pkey | PRIMARY KEY (day, ward) |
| hf_ops | daily_snapshots | daily_snapshots_ward_fkey | FOREIGN KEY (ward) REFERENCES hospitalflow.wards(name) |
| hf_ops | integrity_findings | integrity_findings_pkey | PRIMARY KEY (id) |
| hf_ops | integrity_findings | integrity_findings_run_id_fkey | FOREIGN KEY (run_id) REFERENCES hf_ops.job_runs(id) |
| hf_ops | integrity_findings | integrity_findings_violations_check | CHECK ((violations >= 0)) |
| hf_ops | job_definitions | job_definitions_failures_check | CHECK ((failures >= 0)) |
| hf_ops | job_definitions | job_definitions_interval_seconds_check | CHECK (((interval_seconds >= 60) AND (interval_seconds <= 604800))) |
| hf_ops | job_definitions | job_definitions_pkey | PRIMARY KEY (name) |
| hf_ops | job_definitions | job_definitions_task_check | CHECK ((task = ANY (ARRAY['refresh_alerts'::text, 'session_cleanup'::text, 'integrity_check'::text, 'daily_snapshot'::text, 'refresh_reports'::text, 'recover_outbox_leases'::text, 'backup_monitor'::text, 'analyze_tables'::text]))) |
| hf_ops | job_definitions | job_definitions_task_key | UNIQUE (task) |
| hf_ops | job_runs | job_runs_check | CHECK (((finished_at IS NULL) OR (finished_at >= started_at))) |
| hf_ops | job_runs | job_runs_job_name_fkey | FOREIGN KEY (job_name) REFERENCES hf_ops.job_definitions(name) |
| hf_ops | job_runs | job_runs_pkey | PRIMARY KEY (id) |
| hf_ops | job_runs | job_runs_status_check | CHECK ((status = ANY (ARRAY['Running'::text, 'Succeeded'::text, 'Failed'::text, 'Skipped'::text]))) |
| hf_ops | restore_drills | restore_drills_backup_id_fkey | FOREIGN KEY (backup_id) REFERENCES hf_ops.backup_runs(id) |
| hf_ops | restore_drills | restore_drills_outcome_check | CHECK ((outcome = ANY (ARRAY['Passed'::text, 'Failed'::text]))) |
| hf_ops | restore_drills | restore_drills_pkey | PRIMARY KEY (id) |
| hf_ops | restore_drills | restore_drills_recovery_seconds_check | CHECK ((recovery_seconds >= 0)) |
| hf_ops | retention_policies | retention_policies_check | CHECK (((NOT purge_enabled) OR (approved_reference IS NOT NULL))) |
| hf_ops | retention_policies | retention_policies_pkey | PRIMARY KEY (entity) |
| hf_ops | retention_policies | retention_policies_retain_days_check | CHECK ((retain_days >= 30)) |
| hf_ops | schema_change_events | schema_change_events_pkey | PRIMARY KEY (id) |
| hf_ops | worker_heartbeats | worker_heartbeats_pkey | PRIMARY KEY (worker) |
| hf_ops | worker_heartbeats | worker_heartbeats_status_check | CHECK ((status = ANY (ARRAY['Started'::text, 'Succeeded'::text, 'Failed'::text]))) |
| hospitalflow | account_mail | account_mail_pkey | PRIMARY KEY (id) |
| hospitalflow | account_mail | account_mail_status_check | CHECK ((status = ANY (ARRAY['Pending'::text, 'Sent'::text, 'Failed'::text]))) |
| hospitalflow | account_mail | account_mail_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | account_tokens | account_tokens_pkey | PRIMARY KEY (token_hash) |
| hospitalflow | account_tokens | account_tokens_purpose_check | CHECK ((purpose = ANY (ARRAY['verify'::text, 'reset'::text]))) |
| hospitalflow | account_tokens | account_tokens_token_hash_check | CHECK ((length(token_hash) = 64)) |
| hospitalflow | account_tokens | account_tokens_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | activity_log | activity_log_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | activity_log | activity_log_pkey | PRIMARY KEY (id) |
| hospitalflow | admission_events | admission_events_actor_id_fkey | FOREIGN KEY (actor_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | admission_events | admission_events_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | admission_events | admission_events_from_bed_fkey | FOREIGN KEY (from_bed) REFERENCES hospitalflow.beds(id) |
| hospitalflow | admission_events | admission_events_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | admission_events | admission_events_kind_check | CHECK ((kind = ANY (ARRAY['Admission'::text, 'Transfer'::text, 'Discharge'::text]))) |
| hospitalflow | admission_events | admission_events_pkey | PRIMARY KEY (id) |
| hospitalflow | admission_events | admission_events_reason_check | CHECK (((length(TRIM(BOTH FROM reason)) >= 1) AND (length(TRIM(BOTH FROM reason)) <= 4000))) |
| hospitalflow | admission_events | admission_events_to_bed_fkey | FOREIGN KEY (to_bed) REFERENCES hospitalflow.beds(id) |
| hospitalflow | admissions | admission_consistency | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | admissions | admissions_bed_id_fkey | FOREIGN KEY (bed_id) REFERENCES hospitalflow.beds(id) |
| hospitalflow | admissions | admissions_check | CHECK ((((status = 'Admitted'::text) AND (discharged IS NULL)) OR ((status = 'Discharged'::text) AND (discharged IS NOT NULL) AND (discharged >= at)))) |
| hospitalflow | admissions | admissions_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | admissions | admissions_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | admissions | admissions_pkey | PRIMARY KEY (id) |
| hospitalflow | admissions | admissions_status_check | CHECK ((status = ANY (ARRAY['Admitted'::text, 'Discharged'::text]))) |
| hospitalflow | admissions | discharge_readiness | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | application_releases | application_releases_pkey | PRIMARY KEY (version) |
| hospitalflow | application_releases | application_releases_version_check | CHECK ((version ~ '^[0-9]+\.[0-9]\.[0-9]$'::text)) |
| hospitalflow | appointment_bookings | appointment_bookings_amount_check | CHECK ((amount > (0)::numeric)) |
| hospitalflow | appointment_bookings | appointment_bookings_appointment_id_fkey | FOREIGN KEY (appointment_id) REFERENCES hospitalflow.appointments(id) |
| hospitalflow | appointment_bookings | appointment_bookings_appointment_id_key | UNIQUE (appointment_id) |
| hospitalflow | appointment_bookings | appointment_bookings_created_by_fkey | FOREIGN KEY (created_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | appointment_bookings | appointment_bookings_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | appointment_bookings | appointment_bookings_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | appointment_bookings | appointment_bookings_method_check | CHECK ((method = ANY (ARRAY['UPI'::text, 'Netbanking'::text, 'Card'::text, 'QR'::text, 'Cash'::text]))) |
| hospitalflow | appointment_bookings | appointment_bookings_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | appointment_bookings | appointment_bookings_payment_mode_check | CHECK ((payment_mode = ANY (ARRAY['Test'::text, 'Cash'::text, 'Disabled'::text]))) |
| hospitalflow | appointment_bookings | appointment_bookings_pkey | PRIMARY KEY (id) |
| hospitalflow | appointment_bookings | appointment_bookings_state_check | CHECK ((state = ANY (ARRAY['Pending'::text, 'Paid'::text, 'Expired'::text, 'Cancelled'::text, 'Refund pending'::text, 'Refunded'::text]))) |
| hospitalflow | appointment_bookings | appointment_bookings_visit_type_check | CHECK ((visit_type = ANY (ARRAY['Consultation'::text, 'Follow-up'::text, 'Review'::text]))) |
| hospitalflow | appointments | appointments_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | appointments | appointments_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | appointments | appointments_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | appointments | appointments_pkey | PRIMARY KEY (id) |
| hospitalflow | appointments | appointments_status_check | CHECK ((status = ANY (ARRAY['Scheduled'::text, 'Checked in'::text, 'In consultation'::text, 'Completed'::text, 'Cancelled'::text, 'No show'::text]))) |
| hospitalflow | auth_attempts | auth_attempts_failures_check | CHECK ((failures >= 0)) |
| hospitalflow | auth_attempts | auth_attempts_pkey | PRIMARY KEY (key_hash) |
| hospitalflow | bed_assignments | bed_assignments_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | bed_assignments | bed_assignments_bed_id_fkey | FOREIGN KEY (bed_id) REFERENCES hospitalflow.beds(id) |
| hospitalflow | bed_assignments | bed_assignments_check | CHECK (((to_time IS NULL) OR (to_time >= from_time))) |
| hospitalflow | bed_assignments | bed_assignments_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | bed_assignments | bed_assignments_pkey | PRIMARY KEY (id) |
| hospitalflow | beds | bed_consistency | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | beds | beds_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | beds | beds_pkey | PRIMARY KEY (id) |
| hospitalflow | beds | beds_status_check | CHECK ((status = ANY (ARRAY['Available'::text, 'Occupied'::text, 'Cleaning'::text, 'Maintenance'::text]))) |
| hospitalflow | beds | beds_ward_fkey | FOREIGN KEY (ward) REFERENCES hospitalflow.wards(name) |
| hospitalflow | bill_lines | bill_lines_amount_check | CHECK ((amount <> (0)::numeric)) |
| hospitalflow | bill_lines | bill_lines_bill_id_fkey | FOREIGN KEY (bill_id) REFERENCES hospitalflow.bills(id) |
| hospitalflow | bill_lines | bill_lines_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | bill_lines | bill_lines_pkey | PRIMARY KEY (id) |
| hospitalflow | bill_lines | capture_inclusive_tax | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | bill_lines | line_balance | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | billing_tax_settings | billing_tax_settings_bed_rate_check | CHECK (((bed_rate >= (0)::numeric) AND (bed_rate <= (100)::numeric))) |
| hospitalflow | billing_tax_settings | billing_tax_settings_configured_by_fkey | FOREIGN KEY (configured_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | billing_tax_settings | billing_tax_settings_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | billing_tax_settings | billing_tax_settings_medicine_rate_check | CHECK (((medicine_rate >= (0)::numeric) AND (medicine_rate <= (100)::numeric))) |
| hospitalflow | billing_tax_settings | billing_tax_settings_other_rate_check | CHECK (((other_rate >= (0)::numeric) AND (other_rate <= (100)::numeric))) |
| hospitalflow | billing_tax_settings | billing_tax_settings_pkey | PRIMARY KEY (id) |
| hospitalflow | billing_tax_snapshots | billing_tax_snapshots_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | billing_tax_snapshots | billing_tax_snapshots_line_id_fkey | FOREIGN KEY (line_id) REFERENCES hospitalflow.bill_lines(id) |
| hospitalflow | billing_tax_snapshots | billing_tax_snapshots_pkey | PRIMARY KEY (line_id) |
| hospitalflow | billing_tax_snapshots | billing_tax_snapshots_rate_check | CHECK (((rate >= (0)::numeric) AND (rate <= (100)::numeric))) |
| hospitalflow | billing_tax_snapshots | billing_tax_snapshots_setting_id_fkey | FOREIGN KEY (setting_id) REFERENCES hospitalflow.billing_tax_settings(id) |
| hospitalflow | bills | bills_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | bills | bills_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | bills | bills_pkey | PRIMARY KEY (id) |
| hospitalflow | booking_events | booking_events_actor_id_fkey | FOREIGN KEY (actor_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | booking_events | booking_events_booking_id_fkey | FOREIGN KEY (booking_id) REFERENCES hospitalflow.appointment_bookings(id) |
| hospitalflow | booking_events | booking_events_pkey | PRIMARY KEY (id) |
| hospitalflow | booking_settings | booking_settings_fee_check | CHECK (((fee >= (200)::numeric) AND (fee <= (750)::numeric))) |
| hospitalflow | booking_settings | booking_settings_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | booking_settings | booking_settings_pkey | PRIMARY KEY (hospital_id) |
| hospitalflow | care_charge_entries | care_charge_entries_admission_id_charge_day_category_key | UNIQUE (admission_id, charge_day, category) |
| hospitalflow | care_charge_entries | care_charge_entries_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | care_charge_entries | care_charge_entries_amount_check | CHECK ((amount >= (0)::numeric)) |
| hospitalflow | care_charge_entries | care_charge_entries_bed_id_fkey | FOREIGN KEY (bed_id) REFERENCES hospitalflow.beds(id) |
| hospitalflow | care_charge_entries | care_charge_entries_category_check | CHECK ((category = ANY (ARRAY['Bed'::text, 'Ward'::text, 'ICU'::text, 'Nursing'::text]))) |
| hospitalflow | care_charge_entries | care_charge_entries_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | care_charge_entries | care_charge_entries_line_id_fkey | FOREIGN KEY (line_id) REFERENCES hospitalflow.bill_lines(id) |
| hospitalflow | care_charge_entries | care_charge_entries_line_id_key | UNIQUE (line_id) |
| hospitalflow | care_charge_entries | care_charge_entries_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | care_charge_entries | care_charge_entries_pkey | PRIMARY KEY (id) |
| hospitalflow | care_charge_entries | care_charge_entries_rate_id_fkey | FOREIGN KEY (rate_id) REFERENCES hospitalflow.care_rates(id) |
| hospitalflow | care_command_keys | care_command_keys_actor_id_fkey | FOREIGN KEY (actor_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | care_command_keys | care_command_keys_pkey | PRIMARY KEY (actor_id, key) |
| hospitalflow | care_discharge_reviews | care_discharge_reviews_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | care_discharge_reviews | care_discharge_reviews_completed_by_fkey | FOREIGN KEY (completed_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | care_discharge_reviews | care_discharge_reviews_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | care_discharge_reviews | care_discharge_reviews_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | care_discharge_reviews | care_discharge_reviews_nurse_id_fkey | FOREIGN KEY (nurse_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | care_discharge_reviews | care_discharge_reviews_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | care_discharge_reviews | care_discharge_reviews_pkey | PRIMARY KEY (admission_id) |
| hospitalflow | care_events | care_events_actor_id_fkey | FOREIGN KEY (actor_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | care_events | care_events_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | care_events | care_events_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | care_events | care_events_pkey | PRIMARY KEY (id) |
| hospitalflow | care_extra_categories | care_extra_categories_line_id_fkey | FOREIGN KEY (line_id) REFERENCES hospitalflow.bill_lines(id) |
| hospitalflow | care_extra_categories | care_extra_categories_pkey | PRIMARY KEY (line_id) |
| hospitalflow | care_invoices | care_invoices_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | care_invoices | care_invoices_bill_id_fkey | FOREIGN KEY (bill_id) REFERENCES hospitalflow.bills(id) |
| hospitalflow | care_invoices | care_invoices_bill_id_key | UNIQUE (bill_id) |
| hospitalflow | care_invoices | care_invoices_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | care_invoices | care_invoices_pkey | PRIMARY KEY (admission_id) |
| hospitalflow | care_lab_charges | care_lab_charges_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | care_lab_charges | care_lab_charges_line_id_fkey | FOREIGN KEY (line_id) REFERENCES hospitalflow.bill_lines(id) |
| hospitalflow | care_lab_charges | care_lab_charges_line_id_key | UNIQUE (line_id) |
| hospitalflow | care_lab_charges | care_lab_charges_order_id_fkey | FOREIGN KEY (order_id) REFERENCES hospitalflow.clinical_orders(id) |
| hospitalflow | care_lab_charges | care_lab_charges_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | care_lab_charges | care_lab_charges_pkey | PRIMARY KEY (order_id) |
| hospitalflow | care_lab_charges | care_lab_charges_price_id_fkey | FOREIGN KEY (price_id) REFERENCES hospitalflow.service_prices(id) |
| hospitalflow | care_managed_orders | care_managed_orders_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | care_managed_orders | care_managed_orders_order_id_fkey | FOREIGN KEY (order_id) REFERENCES hospitalflow.clinical_orders(id) |
| hospitalflow | care_managed_orders | care_managed_orders_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | care_managed_orders | care_managed_orders_pkey | PRIMARY KEY (order_id) |
| hospitalflow | care_observations | care_observations_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | care_observations | care_observations_health_status_check | CHECK (((length(health_status) >= 1) AND (length(health_status) <= 1000))) |
| hospitalflow | care_observations | care_observations_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | care_observations | care_observations_notes_check | CHECK (((length(notes) >= 1) AND (length(notes) <= 4000))) |
| hospitalflow | care_observations | care_observations_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | care_observations | care_observations_pkey | PRIMARY KEY (id) |
| hospitalflow | care_observations | care_observations_progress_check | CHECK (((length(progress) >= 1) AND (length(progress) <= 2000))) |
| hospitalflow | care_observations | care_observations_recorded_by_fkey | FOREIGN KEY (recorded_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | care_plans | care_plans_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | care_plans | care_plans_admission_id_key | UNIQUE (admission_id) |
| hospitalflow | care_plans | care_plans_appointment_id_fkey | FOREIGN KEY (appointment_id) REFERENCES hospitalflow.appointments(id) |
| hospitalflow | care_plans | care_plans_diagnosis_check | CHECK (((length(diagnosis) >= 1) AND (length(diagnosis) <= 2000))) |
| hospitalflow | care_plans | care_plans_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | care_plans | care_plans_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | care_plans | care_plans_instructions_check | CHECK (((length(instructions) >= 1) AND (length(instructions) <= 4000))) |
| hospitalflow | care_plans | care_plans_nurse_id_fkey | FOREIGN KEY (nurse_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | care_plans | care_plans_nursing_days_check | CHECK (((nursing_days >= 1) AND (nursing_days <= 365))) |
| hospitalflow | care_plans | care_plans_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | care_plans | care_plans_pkey | PRIMARY KEY (id) |
| hospitalflow | care_plans | care_plans_planned_days_check | CHECK (((planned_days >= 1) AND (planned_days <= 365))) |
| hospitalflow | care_plans | care_plans_requested_ward_fkey | FOREIGN KEY (requested_ward) REFERENCES hospitalflow.wards(name) |
| hospitalflow | care_plans | care_plans_status_check | CHECK ((status = ANY (ARRAY['Requested'::text, 'Accepted'::text, 'Admitted'::text, 'Discharged'::text]))) |
| hospitalflow | care_rates | care_rates_bed_daily_check | CHECK ((bed_daily >= (0)::numeric)) |
| hospitalflow | care_rates | care_rates_configured_by_fkey | FOREIGN KEY (configured_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | care_rates | care_rates_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | care_rates | care_rates_icu_daily_check | CHECK ((icu_daily >= (0)::numeric)) |
| hospitalflow | care_rates | care_rates_nursing_daily_check | CHECK ((nursing_daily >= (0)::numeric)) |
| hospitalflow | care_rates | care_rates_pkey | PRIMARY KEY (id) |
| hospitalflow | care_rates | care_rates_ward_daily_check | CHECK ((ward_daily >= (0)::numeric)) |
| hospitalflow | care_rates | care_rates_ward_fkey | FOREIGN KEY (ward) REFERENCES hospitalflow.wards(name) |
| hospitalflow | clinical_orders | clinical_orders_check | CHECK (((status = 'Completed'::text) = (completed_at IS NOT NULL))) |
| hospitalflow | clinical_orders | clinical_orders_encounter_id_fkey | FOREIGN KEY (encounter_id) REFERENCES hospitalflow.encounters(id) |
| hospitalflow | clinical_orders | clinical_orders_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | clinical_orders | clinical_orders_ordered_by_fkey | FOREIGN KEY (ordered_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | clinical_orders | clinical_orders_pkey | PRIMARY KEY (id) |
| hospitalflow | clinical_orders | clinical_orders_service_id_fkey | FOREIGN KEY (service_id) REFERENCES hospitalflow.service_catalog(id) |
| hospitalflow | clinical_orders | clinical_orders_status_check | CHECK ((status = ANY (ARRAY['Requested'::text, 'In progress'::text, 'Completed'::text, 'Cancelled'::text]))) |
| hospitalflow | data_protection_keys | data_protection_keys_pkey | PRIMARY KEY (id) |
| hospitalflow | departments | departments_name_check | CHECK (((length(name) >= 1) AND (length(name) <= 80))) |
| hospitalflow | departments | departments_pkey | PRIMARY KEY (name) |
| hospitalflow | discharge_tasks | discharge_tasks_admission_id_code_key | UNIQUE (admission_id, code) |
| hospitalflow | discharge_tasks | discharge_tasks_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | discharge_tasks | discharge_tasks_check | CHECK (((completed_by IS NULL) = (completed_at IS NULL))) |
| hospitalflow | discharge_tasks | discharge_tasks_completed_by_fkey | FOREIGN KEY (completed_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | discharge_tasks | discharge_tasks_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | discharge_tasks | discharge_tasks_pkey | PRIMARY KEY (id) |
| hospitalflow | doctors | doctors_check | CHECK ((start < "end")) |
| hospitalflow | doctors | doctors_department_fkey | FOREIGN KEY (department) REFERENCES hospitalflow.departments(name) |
| hospitalflow | doctors | doctors_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | doctors | doctors_pkey | PRIMARY KEY (id) |
| hospitalflow | doctors | doctors_registration_id_key | UNIQUE (registration_id) |
| hospitalflow | email_changes | email_changes_password_fingerprint_check | CHECK ((length(password_fingerprint) = 64)) |
| hospitalflow | email_changes | email_changes_pkey | PRIMARY KEY (token_hash) |
| hospitalflow | email_changes | email_changes_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | encounters | encounters_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | encounters | encounters_admission_id_key | UNIQUE (admission_id) |
| hospitalflow | encounters | encounters_appointment_id_fkey | FOREIGN KEY (appointment_id) REFERENCES hospitalflow.appointments(id) |
| hospitalflow | encounters | encounters_appointment_id_key | UNIQUE (appointment_id) |
| hospitalflow | encounters | encounters_check | CHECK ((((kind = 'Outpatient'::hospitalflow.encounter_kind) AND (appointment_id IS NOT NULL) AND (admission_id IS NULL)) OR ((kind = 'Inpatient'::hospitalflow.encounter_kind) AND (admission_id IS NOT NULL) AND (appointment_id IS NULL)))) |
| hospitalflow | encounters | encounters_check1 | CHECK (((closed_at IS NULL) OR (closed_at >= opened_at))) |
| hospitalflow | encounters | encounters_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | encounters | encounters_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | encounters | encounters_pkey | PRIMARY KEY (id) |
| hospitalflow | encounters | encounters_status_check | CHECK ((status = ANY (ARRAY['Open'::text, 'Completed'::text, 'Cancelled'::text]))) |
| hospitalflow | follow_ups | follow_ups_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | follow_ups | follow_ups_appointment_id_fkey | FOREIGN KEY (appointment_id) REFERENCES hospitalflow.appointments(id) |
| hospitalflow | follow_ups | follow_ups_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | follow_ups | follow_ups_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | follow_ups | follow_ups_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | follow_ups | follow_ups_pkey | PRIMARY KEY (id) |
| hospitalflow | follow_ups | follow_ups_status_check | CHECK ((status = ANY (ARRAY['Pending'::text, 'Booked'::text, 'Completed'::text, 'Cancelled'::text]))) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_movement_id_fkey | FOREIGN KEY (movement_id) REFERENCES hospitalflow.stock_movements(id) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_movement_id_key | UNIQUE (movement_id) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_pkey | PRIMARY KEY (id) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_purchase_order_line_id_fkey | FOREIGN KEY (purchase_order_line_id) REFERENCES hospitalflow.purchase_order_lines(id) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_quantity_check | CHECK ((quantity > 0)) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_receipt_id_fkey | FOREIGN KEY (receipt_id) REFERENCES hospitalflow.goods_receipts(id) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_receipt_id_purchase_order_line_id_key | UNIQUE (receipt_id, purchase_order_line_id) |
| hospitalflow | goods_receipts | goods_receipts_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | goods_receipts | goods_receipts_pkey | PRIMARY KEY (id) |
| hospitalflow | goods_receipts | goods_receipts_purchase_order_id_fkey | FOREIGN KEY (purchase_order_id) REFERENCES hospitalflow.purchase_orders(id) |
| hospitalflow | goods_receipts | goods_receipts_purchase_order_id_reference_key | UNIQUE (purchase_order_id, reference) |
| hospitalflow | goods_receipts | goods_receipts_received_by_fkey | FOREIGN KEY (received_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | hospital_holidays | hospital_holidays_check | CHECK ((((on_date IS NOT NULL) AND (annual_month IS NULL) AND (annual_day IS NULL)) OR ((on_date IS NULL) AND ((annual_month >= 1) AND (annual_month <= 12)) AND ((annual_day >= 1) AND ((annual_day)::numeric <= EXTRACT(day FROM (make_date(2000, annual_month, 1) + '1 mon -1 days'::interval))))))) |
| hospitalflow | hospital_holidays | hospital_holidays_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | hospital_holidays | hospital_holidays_kind_check | CHECK ((kind = ANY (ARRAY['National'::text, 'Festival'::text, 'Regional'::text, 'Hospital'::text]))) |
| hospitalflow | hospital_holidays | hospital_holidays_name_check | CHECK (((length(name) >= 1) AND (length(name) <= 150))) |
| hospitalflow | hospital_holidays | hospital_holidays_pkey | PRIMARY KEY (id) |
| hospitalflow | hospital_holidays | hospital_holidays_updated_by_fkey | FOREIGN KEY (updated_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | hospital_memberships | hospital_memberships_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | hospital_memberships | hospital_memberships_pkey | PRIMARY KEY (user_id, hospital_id) |
| hospitalflow | hospital_memberships | hospital_memberships_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | hospital_profile | hospital_profile_id_check | CHECK ((id = 1)) |
| hospitalflow | hospital_profile | hospital_profile_name_check | CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 150))) |
| hospitalflow | hospital_profile | hospital_profile_pkey | PRIMARY KEY (id) |
| hospitalflow | hospitals | hospitals_name_check | CHECK (((length(name) >= 2) AND (length(name) <= 150))) |
| hospitalflow | hospitals | hospitals_pkey | PRIMARY KEY (id) |
| hospitalflow | idempotency_hash_keys | idempotency_hash_keys_id_check | CHECK ((id = 1)) |
| hospitalflow | idempotency_hash_keys | idempotency_hash_keys_pkey | PRIMARY KEY (id) |
| hospitalflow | idempotency_hash_keys | idempotency_hash_keys_secret_check | CHECK ((octet_length(secret) = 32)) |
| hospitalflow | idempotency_keys | idempotency_keys_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | idempotency_keys | idempotency_keys_pkey | PRIMARY KEY (user_id, key) |
| hospitalflow | idempotency_keys | idempotency_keys_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | integration_outbox | integration_outbox_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | integration_outbox | integration_outbox_payload_check | CHECK ((jsonb_typeof(payload) = 'object'::text)) |
| hospitalflow | integration_outbox | integration_outbox_pkey | PRIMARY KEY (id) |
| hospitalflow | integration_outbox | minimal_outbox_payload | CHECK (((payload - ARRAY['reference'::text, 'status'::text, 'kind'::text]) = '{}'::jsonb)) |
| hospitalflow | invoice_discounts | invoice_discounts_amount_check | CHECK ((amount > (0)::numeric)) |
| hospitalflow | invoice_discounts | invoice_discounts_bill_id_fkey | FOREIGN KEY (bill_id) REFERENCES hospitalflow.bills(id) |
| hospitalflow | invoice_discounts | invoice_discounts_created_by_fkey | FOREIGN KEY (created_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | invoice_discounts | invoice_discounts_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | invoice_discounts | invoice_discounts_line_id_fkey | FOREIGN KEY (line_id) REFERENCES hospitalflow.bill_lines(id) |
| hospitalflow | invoice_discounts | invoice_discounts_pkey | PRIMARY KEY (line_id) |
| hospitalflow | invoice_discounts | invoice_discounts_reason_check | CHECK (((length(reason) >= 1) AND (length(reason) <= 500))) |
| hospitalflow | invoice_line_context | invoice_line_context_check | CHECK ((num_nonnulls(service_price_id, medicine_id) = 1)) |
| hospitalflow | invoice_line_context | invoice_line_context_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | invoice_line_context | invoice_line_context_line_id_fkey | FOREIGN KEY (line_id) REFERENCES hospitalflow.bill_lines(id) |
| hospitalflow | invoice_line_context | invoice_line_context_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | invoice_line_context | invoice_line_context_pkey | PRIMARY KEY (line_id) |
| hospitalflow | invoice_line_context | invoice_line_context_quantity_check | CHECK ((quantity > (0)::numeric)) |
| hospitalflow | invoice_line_context | invoice_line_context_service_price_id_fkey | FOREIGN KEY (service_price_id) REFERENCES hospitalflow.service_prices(id) |
| hospitalflow | invoice_line_context | invoice_line_context_unit_price_check | CHECK ((unit_price > (0)::numeric)) |
| hospitalflow | medication_administrations | medication_administrations_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | medication_administrations | medication_administrations_note_check | CHECK (((length(note) >= 1) AND (length(note) <= 1000))) |
| hospitalflow | medication_administrations | medication_administrations_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | medication_administrations | medication_administrations_pkey | PRIMARY KEY (id) |
| hospitalflow | medication_administrations | medication_administrations_prescription_id_fkey | FOREIGN KEY (prescription_id) REFERENCES hospitalflow.prescriptions(id) |
| hospitalflow | medication_administrations | medication_administrations_provided_by_fkey | FOREIGN KEY (provided_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | medication_administrations | medication_administrations_provided_by_retry_key_key | UNIQUE (provided_by, retry_key) |
| hospitalflow | medication_administrations | medication_administrations_quantity_check | CHECK ((quantity > 0)) |
| hospitalflow | medication_doses | medication_doses_administration_id_fkey | FOREIGN KEY (administration_id) REFERENCES hospitalflow.medication_administrations(id) |
| hospitalflow | medication_doses | medication_doses_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | medication_doses | medication_doses_check | CHECK ((((status = 'Scheduled'::text) AND (recorded_at IS NULL) AND (actual_at IS NULL)) OR ((status = 'Given'::text) AND (actual_at IS NOT NULL) AND (recorded_at IS NOT NULL) AND (administration_id IS NOT NULL)) OR ((status = 'Not given'::text) AND (actual_at IS NULL) AND (recorded_at IS NOT NULL) AND (administration_id IS NULL)))) |
| hospitalflow | medication_doses | medication_doses_created_by_fkey | FOREIGN KEY (created_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | medication_doses | medication_doses_dose_check | CHECK (((length(dose) >= 1) AND (length(dose) <= 200))) |
| hospitalflow | medication_doses | medication_doses_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | medication_doses | medication_doses_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | medication_doses | medication_doses_pkey | PRIMARY KEY (id) |
| hospitalflow | medication_doses | medication_doses_prescription_id_fkey | FOREIGN KEY (prescription_id) REFERENCES hospitalflow.prescriptions(id) |
| hospitalflow | medication_doses | medication_doses_quantity_check | CHECK ((quantity > 0)) |
| hospitalflow | medication_doses | medication_doses_recorded_by_fkey | FOREIGN KEY (recorded_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | medication_doses | medication_doses_status_check | CHECK ((status = ANY (ARRAY['Scheduled'::text, 'Given'::text, 'Not given'::text]))) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_check | CHECK (((released_by IS NULL) = (released_at IS NULL))) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_check1 | CHECK (((released_at IS NULL) OR (released_at >= held_at))) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_held_by_fkey | FOREIGN KEY (held_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_pkey | PRIMARY KEY (id) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_released_by_fkey | FOREIGN KEY (released_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | medicine_batches | medicine_batches_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | medicine_batches | medicine_batches_hospital_id_name_batch_key | UNIQUE (hospital_id, name, batch) |
| hospitalflow | medicine_batches | medicine_batches_pkey | PRIMARY KEY (id) |
| hospitalflow | medicine_batches | medicine_batches_price_check | CHECK ((price > (0)::numeric)) |
| hospitalflow | medicine_batches | medicine_batches_quantity_check | CHECK ((quantity >= 0)) |
| hospitalflow | medicine_batches | medicine_batches_reorder_check | CHECK ((reorder > 0)) |
| hospitalflow | medicine_batches | stock_batch_balance | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | medicine_price_history | medicine_price_history_created_by_fkey | FOREIGN KEY (created_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | medicine_price_history | medicine_price_history_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | medicine_price_history | medicine_price_history_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | medicine_price_history | medicine_price_history_new_price_check | CHECK ((new_price > (0)::numeric)) |
| hospitalflow | medicine_price_history | medicine_price_history_pkey | PRIMARY KEY (id) |
| hospitalflow | network_operators | network_operators_pkey | PRIMARY KEY (user_id) |
| hospitalflow | network_operators | network_operators_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | notes | notes_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | notes | notes_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | notes | notes_pkey | PRIMARY KEY (id) |
| hospitalflow | notes | notes_text_check | CHECK ((length(text) <= 4000)) |
| hospitalflow | notification_acknowledgements | notification_acknowledgements_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | notification_acknowledgements | notification_acknowledgements_notification_id_fkey | FOREIGN KEY (notification_id) REFERENCES hospitalflow.notifications(id) |
| hospitalflow | notification_acknowledgements | notification_acknowledgements_pkey | PRIMARY KEY (notification_id, user_id) |
| hospitalflow | notification_acknowledgements | notification_acknowledgements_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | notifications | notifications_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | notifications | notifications_pkey | PRIMARY KEY (id) |
| hospitalflow | outbox_delivery | outbox_delivery_attempts_check | CHECK ((attempts >= 0)) |
| hospitalflow | outbox_delivery | outbox_delivery_check | CHECK (((status = 'Leased'::text) = ((lease_token IS NOT NULL) AND (lease_until IS NOT NULL)))) |
| hospitalflow | outbox_delivery | outbox_delivery_check1 | CHECK (((status = 'Delivered'::text) = (delivered_at IS NOT NULL))) |
| hospitalflow | outbox_delivery | outbox_delivery_event_id_fkey | FOREIGN KEY (event_id) REFERENCES hospitalflow.integration_outbox(id) |
| hospitalflow | outbox_delivery | outbox_delivery_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | outbox_delivery | outbox_delivery_pkey | PRIMARY KEY (event_id) |
| hospitalflow | outbox_delivery | outbox_delivery_status_check | CHECK ((status = ANY (ARRAY['Pending'::text, 'Leased'::text, 'Delivered'::text, 'Dead letter'::text]))) |
| hospitalflow | patient_access_grants | patient_access_grants_check | CHECK ((expires_at > created_at)) |
| hospitalflow | patient_access_grants | patient_access_grants_granted_by_fkey | FOREIGN KEY (granted_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | patient_access_grants | patient_access_grants_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | patient_access_grants | patient_access_grants_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | patient_access_grants | patient_access_grants_pkey | PRIMARY KEY (id) |
| hospitalflow | patient_access_grants | patient_access_grants_purpose_check | CHECK (((length(TRIM(BOTH FROM purpose)) >= 1) AND (length(TRIM(BOTH FROM purpose)) <= 200))) |
| hospitalflow | patient_access_grants | patient_access_grants_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | patient_accounts | patient_accounts_check | CHECK (((must_change_password AND (activated_at IS NULL)) OR ((NOT must_change_password) AND (activated_at IS NOT NULL)))) |
| hospitalflow | patient_accounts | patient_accounts_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | patient_accounts | patient_accounts_patient_id_key | UNIQUE (patient_id) |
| hospitalflow | patient_accounts | patient_accounts_pkey | PRIMARY KEY (user_id) |
| hospitalflow | patient_accounts | patient_accounts_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | patient_consents | patient_consents_check | CHECK (((expires_at IS NULL) OR (expires_at > granted_at))) |
| hospitalflow | patient_consents | patient_consents_check1 | CHECK (((revoked_at IS NULL) OR (revoked_at >= granted_at))) |
| hospitalflow | patient_consents | patient_consents_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | patient_consents | patient_consents_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | patient_consents | patient_consents_pkey | PRIMARY KEY (id) |
| hospitalflow | patient_consents | patient_consents_recorded_by_fkey | FOREIGN KEY (recorded_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | patient_contacts | contact_mobile_ten_digits | CHECK ((phone ~ '^[0-9]{10}$'::text)) |
| hospitalflow | patient_contacts | patient_contacts_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | patient_contacts | patient_contacts_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | patient_contacts | patient_contacts_pkey | PRIMARY KEY (id) |
| hospitalflow | patient_hospitals | patient_hospitals_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | patient_hospitals | patient_hospitals_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | patient_hospitals | patient_hospitals_pkey | PRIMARY KEY (patient_id, hospital_id) |
| hospitalflow | patient_login_challenges | first_login_challenge_user_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | patient_login_challenges | patient_login_challenges_attempts_check | CHECK (((attempts >= 0) AND (attempts <= 5))) |
| hospitalflow | patient_login_challenges | patient_login_challenges_pkey | PRIMARY KEY (token_hash) |
| hospitalflow | patient_login_challenges | patient_login_challenges_token_hash_check | CHECK ((length(token_hash) = 64)) |
| hospitalflow | patient_sms | patient_sms_pkey | PRIMARY KEY (id) |
| hospitalflow | patient_sms | patient_sms_status_check | CHECK ((status = ANY (ARRAY['Pending'::text, 'Local pickup'::text, 'Failed'::text]))) |
| hospitalflow | patient_sms | patient_sms_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.patient_accounts(user_id) |
| hospitalflow | patients | patient_contact_lengths | CHECK ((((address IS NULL) OR (length(address) <= 1000)) AND ((emergency_contact IS NULL) OR (length(emergency_contact) <= 200)))) |
| hospitalflow | patients | patient_email_format | CHECK (((email IS NULL) OR ((length(email) <= 150) AND (email = lower(TRIM(BOTH FROM email))) AND (email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'::text)))) |
| hospitalflow | patients | patient_mobile_ten_digits | CHECK ((phone ~ '^[0-9]{10}$'::text)) |
| hospitalflow | patients | patients_dob_check | CHECK ((dob >= '1900-01-01'::date)) |
| hospitalflow | patients | patients_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | patients | patients_name_check | CHECK (((length(name) >= 1) AND (length(name) <= 100))) |
| hospitalflow | patients | patients_phone_check | CHECK (((length(phone) >= 7) AND (length(phone) <= 20))) |
| hospitalflow | patients | patients_pkey | PRIMARY KEY (id) |
| hospitalflow | patients | patients_registration_id_key | UNIQUE (registration_id) |
| hospitalflow | patients | patients_sex_check | CHECK ((sex = ANY (ARRAY['Male'::text, 'Female'::text, 'Other'::text, 'Prefer not to say'::text]))) |
| hospitalflow | payment_reversals | payment_reversal_limit | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | payment_reversals | payment_reversals_amount_check | CHECK ((amount > (0)::numeric)) |
| hospitalflow | payment_reversals | payment_reversals_approved_by_fkey | FOREIGN KEY (approved_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | payment_reversals | payment_reversals_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | payment_reversals | payment_reversals_payment_id_fkey | FOREIGN KEY (payment_id) REFERENCES hospitalflow.payments(id) |
| hospitalflow | payment_reversals | payment_reversals_pkey | PRIMARY KEY (id) |
| hospitalflow | payment_reversals | payment_reversals_reason_check | CHECK (((length(TRIM(BOTH FROM reason)) >= 1) AND (length(TRIM(BOTH FROM reason)) <= 500))) |
| hospitalflow | payments | payment_balance | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | payments | payments_amount_check | CHECK ((amount > (0)::numeric)) |
| hospitalflow | payments | payments_bill_id_fkey | FOREIGN KEY (bill_id) REFERENCES hospitalflow.bills(id) |
| hospitalflow | payments | payments_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | payments | payments_method_check | CHECK ((method = ANY (ARRAY['Cash'::text, 'Card'::text, 'UPI'::text, 'Bank transfer'::text]))) |
| hospitalflow | payments | payments_pkey | PRIMARY KEY (id) |
| hospitalflow | person_profiles | person_profiles_address_check | CHECK ((length(address) <= 1000)) |
| hospitalflow | person_profiles | person_profiles_department_fkey | FOREIGN KEY (department) REFERENCES hospitalflow.departments(name) |
| hospitalflow | person_profiles | person_profiles_dob_check | CHECK ((dob >= '1900-01-01'::date)) |
| hospitalflow | person_profiles | person_profiles_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | person_profiles | person_profiles_doctor_id_key | UNIQUE (doctor_id) |
| hospitalflow | person_profiles | person_profiles_job_title_check | CHECK ((length(job_title) <= 100)) |
| hospitalflow | person_profiles | person_profiles_occupation_check | CHECK ((occupation = ANY (ARRAY['Guard'::text, 'Washerman'::text, 'Housekeeping'::text, 'Other'::text]))) |
| hospitalflow | person_profiles | person_profiles_pkey | PRIMARY KEY (user_id) |
| hospitalflow | person_profiles | person_profiles_sex_check | CHECK ((sex = ANY (ARRAY['Male'::text, 'Female'::text, 'Other'::text, 'Prefer not to say'::text]))) |
| hospitalflow | person_profiles | person_profiles_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | person_profiles | profile_mobile_ten_digits | CHECK (((mobile IS NULL) OR (mobile ~ '^[0-9]{10}$'::text))) |
| hospitalflow | pharmacy_requests | pharmacy_requests_comments_check | CHECK (((length(comments) >= 1) AND (length(comments) <= 1000))) |
| hospitalflow | pharmacy_requests | pharmacy_requests_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | pharmacy_requests | pharmacy_requests_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | pharmacy_requests | pharmacy_requests_pkey | PRIMARY KEY (id) |
| hospitalflow | pharmacy_requests | pharmacy_requests_prescription_id_fkey | FOREIGN KEY (prescription_id) REFERENCES hospitalflow.prescriptions(id) |
| hospitalflow | pharmacy_requests | pharmacy_requests_requested_by_fkey | FOREIGN KEY (requested_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | portal_payments | portal_payments_amount_check | CHECK ((amount > (0)::numeric)) |
| hospitalflow | portal_payments | portal_payments_bill_id_fkey | FOREIGN KEY (bill_id) REFERENCES hospitalflow.bills(id) |
| hospitalflow | portal_payments | portal_payments_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | portal_payments | portal_payments_method_check | CHECK ((method = ANY (ARRAY['UPI'::text, 'Netbanking'::text, 'Card'::text, 'QR'::text]))) |
| hospitalflow | portal_payments | portal_payments_mode_check | CHECK ((mode = 'Test'::text)) |
| hospitalflow | portal_payments | portal_payments_paid_by_fkey | FOREIGN KEY (paid_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | portal_payments | portal_payments_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | portal_payments | portal_payments_payment_id_fkey | FOREIGN KEY (payment_id) REFERENCES hospitalflow.payments(id) |
| hospitalflow | portal_payments | portal_payments_payment_id_key | UNIQUE (payment_id) |
| hospitalflow | portal_payments | portal_payments_pkey | PRIMARY KEY (id) |
| hospitalflow | prescription_authors | prescription_authors_created_by_fkey | FOREIGN KEY (created_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | prescription_authors | prescription_authors_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | prescription_authors | prescription_authors_pkey | PRIMARY KEY (prescription_id) |
| hospitalflow | prescription_authors | prescription_authors_prescription_id_fkey | FOREIGN KEY (prescription_id) REFERENCES hospitalflow.prescriptions(id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_bill_id_fkey | FOREIGN KEY (bill_id) REFERENCES hospitalflow.bills(id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_bill_id_key | UNIQUE (bill_id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_dispensed_by_fkey | FOREIGN KEY (dispensed_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_movement_id_fkey | FOREIGN KEY (movement_id) REFERENCES hospitalflow.stock_movements(id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_movement_id_key | UNIQUE (movement_id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_pkey | PRIMARY KEY (id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_prescription_id_fkey | FOREIGN KEY (prescription_id) REFERENCES hospitalflow.prescriptions(id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_prescription_id_key | UNIQUE (prescription_id) |
| hospitalflow | prescription_visits | prescription_visits_appointment_id_fkey | FOREIGN KEY (appointment_id) REFERENCES hospitalflow.appointments(id) |
| hospitalflow | prescription_visits | prescription_visits_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | prescription_visits | prescription_visits_pkey | PRIMARY KEY (prescription_id) |
| hospitalflow | prescription_visits | prescription_visits_prescription_id_fkey | FOREIGN KEY (prescription_id) REFERENCES hospitalflow.prescriptions(id) |
| hospitalflow | prescriptions | dispense_trace | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | prescriptions | prescriptions_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | prescriptions | prescriptions_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | prescriptions | prescriptions_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | prescriptions | prescriptions_pkey | PRIMARY KEY (id) |
| hospitalflow | prescriptions | prescriptions_quantity_check | CHECK ((quantity > 0)) |
| hospitalflow | prescriptions | prescriptions_status_check | CHECK ((status = ANY (ARRAY['Pending'::text, 'Dispensed'::text, 'Cancelled'::text]))) |
| hospitalflow | provider_absences | provider_absences_approved_by_fkey | FOREIGN KEY (approved_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | provider_absences | provider_absences_check | CHECK ((ends_at > starts_at)) |
| hospitalflow | provider_absences | provider_absences_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | provider_absences | provider_absences_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | provider_absences | provider_absences_pkey | PRIMARY KEY (id) |
| hospitalflow | provider_sessions | provider_sessions_capacity_check | CHECK ((capacity = 1)) |
| hospitalflow | provider_sessions | provider_sessions_check | CHECK ((ends_at > starts_at)) |
| hospitalflow | provider_sessions | provider_sessions_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | provider_sessions | provider_sessions_doctor_id_starts_at_key | UNIQUE (doctor_id, starts_at) |
| hospitalflow | provider_sessions | provider_sessions_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | provider_sessions | provider_sessions_pkey | PRIMARY KEY (id) |
| hospitalflow | purchase_order_lines | purchase_order_lines_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | purchase_order_lines | purchase_order_lines_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | purchase_order_lines | purchase_order_lines_pkey | PRIMARY KEY (id) |
| hospitalflow | purchase_order_lines | purchase_order_lines_purchase_order_id_fkey | FOREIGN KEY (purchase_order_id) REFERENCES hospitalflow.purchase_orders(id) |
| hospitalflow | purchase_order_lines | purchase_order_lines_purchase_order_id_medicine_id_key | UNIQUE (purchase_order_id, medicine_id) |
| hospitalflow | purchase_order_lines | purchase_order_lines_quantity_check | CHECK ((quantity > 0)) |
| hospitalflow | purchase_order_lines | purchase_order_lines_unit_cost_check | CHECK ((unit_cost > (0)::numeric)) |
| hospitalflow | purchase_orders | purchase_orders_approved_by_fkey | FOREIGN KEY (approved_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | purchase_orders | purchase_orders_check | CHECK (((status = ANY (ARRAY['Draft'::hospitalflow.purchase_status, 'Cancelled'::hospitalflow.purchase_status])) OR (approved_by IS NOT NULL))) |
| hospitalflow | purchase_orders | purchase_orders_created_by_fkey | FOREIGN KEY (created_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | purchase_orders | purchase_orders_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | purchase_orders | purchase_orders_number_key | UNIQUE (number) |
| hospitalflow | purchase_orders | purchase_orders_pkey | PRIMARY KEY (id) |
| hospitalflow | purchase_orders | purchase_orders_supplier_id_fkey | FOREIGN KEY (supplier_id) REFERENCES hospitalflow.suppliers(id) |
| hospitalflow | referrals | referral_destination | CHECK (((source_hospital_id <> target_hospital_id) OR (target_doctor_id IS NOT NULL))) |
| hospitalflow | referrals | referrals_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | referrals | referrals_pkey | PRIMARY KEY (id) |
| hospitalflow | referrals | referrals_reason_check | CHECK (((length(TRIM(BOTH FROM reason)) >= 5) AND (length(TRIM(BOTH FROM reason)) <= 2000))) |
| hospitalflow | referrals | referrals_referred_by_fkey | FOREIGN KEY (referred_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | referrals | referrals_resolved_by_fkey | FOREIGN KEY (resolved_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | referrals | referrals_source_hospital_id_fkey | FOREIGN KEY (source_hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | referrals | referrals_status_check | CHECK ((status = ANY (ARRAY['Pending'::text, 'Accepted'::text, 'Declined'::text, 'Cancelled'::text]))) |
| hospitalflow | referrals | referrals_target_doctor_id_fkey | FOREIGN KEY (target_doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | referrals | referrals_target_hospital_id_fkey | FOREIGN KEY (target_hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | roles | roles_pkey | PRIMARY KEY (name) |
| hospitalflow | row_history | row_history_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | row_history | row_history_pkey | PRIMARY KEY (id) |
| hospitalflow | schema_versions | schema_versions_pkey | PRIMARY KEY (version) |
| hospitalflow | service_catalog | service_catalog_category_check | CHECK ((category = ANY (ARRAY['Consultation'::text, 'Room'::text, 'Laboratory'::text, 'Imaging'::text, 'Procedure'::text, 'Other'::text]))) |
| hospitalflow | service_catalog | service_catalog_department_fkey | FOREIGN KEY (department) REFERENCES hospitalflow.departments(name) |
| hospitalflow | service_catalog | service_catalog_hospital_id_code_key | UNIQUE (hospital_id, code) |
| hospitalflow | service_catalog | service_catalog_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | service_catalog | service_catalog_pkey | PRIMARY KEY (id) |
| hospitalflow | service_prices | service_prices_amount_check | CHECK ((amount > (0)::numeric)) |
| hospitalflow | service_prices | service_prices_check | CHECK (((effective_to IS NULL) OR (effective_to > effective_from))) |
| hospitalflow | service_prices | service_prices_created_by_fkey | FOREIGN KEY (created_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | service_prices | service_prices_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | service_prices | service_prices_pkey | PRIMARY KEY (id) |
| hospitalflow | service_prices | service_prices_service_id_effective_from_key | UNIQUE (service_id, effective_from) |
| hospitalflow | service_prices | service_prices_service_id_fkey | FOREIGN KEY (service_id) REFERENCES hospitalflow.service_catalog(id) |
| hospitalflow | sessions | sessions_pkey | PRIMARY KEY (id) |
| hospitalflow | sessions | sessions_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | staff_attendance | staff_attendance_approval_status_check | CHECK ((approval_status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text]))) |
| hospitalflow | staff_attendance | staff_attendance_check | CHECK (((check_out IS NULL) OR (check_out >= check_in))) |
| hospitalflow | staff_attendance | staff_attendance_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | staff_attendance | staff_attendance_hospital_id_user_id_day_key | UNIQUE (hospital_id, user_id, day) |
| hospitalflow | staff_attendance | staff_attendance_marked_by_fkey | FOREIGN KEY (marked_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | staff_attendance | staff_attendance_pkey | PRIMARY KEY (id) |
| hospitalflow | staff_attendance | staff_attendance_review_note_check | CHECK ((length(review_note) <= 500)) |
| hospitalflow | staff_attendance | staff_attendance_reviewed_by_fkey | FOREIGN KEY (reviewed_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | staff_attendance | staff_attendance_status_check | CHECK ((status = ANY (ARRAY['Present'::text, 'Absent'::text]))) |
| hospitalflow | staff_attendance | staff_attendance_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | staff_leaves | staff_leaves_check | CHECK (((ends_on >= starts_on) AND ((ends_on - starts_on) <= 90))) |
| hospitalflow | staff_leaves | staff_leaves_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | staff_leaves | staff_leaves_pkey | PRIMARY KEY (id) |
| hospitalflow | staff_leaves | staff_leaves_reason_check | CHECK (((length(reason) >= 5) AND (length(reason) <= 500))) |
| hospitalflow | staff_leaves | staff_leaves_resolved_by_fkey | FOREIGN KEY (resolved_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | staff_leaves | staff_leaves_status_check | CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text, 'Cancelled'::text]))) |
| hospitalflow | staff_leaves | staff_leaves_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | staff_members | staff_members_department_fkey | FOREIGN KEY (department) REFERENCES hospitalflow.departments(name) |
| hospitalflow | staff_members | staff_members_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | staff_members | staff_members_doctor_id_key | UNIQUE (doctor_id) |
| hospitalflow | staff_members | staff_members_hospital_id_employee_number_key | UNIQUE (hospital_id, employee_number) |
| hospitalflow | staff_members | staff_members_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | staff_members | staff_members_pkey | PRIMARY KEY (id) |
| hospitalflow | staff_members | staff_members_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | staff_members | staff_members_user_id_key | UNIQUE (user_id) |
| hospitalflow | staff_onboarding | staff_onboarding_check | CHECK ((must_change_password OR (activated_at IS NOT NULL))) |
| hospitalflow | staff_onboarding | staff_onboarding_pkey | PRIMARY KEY (user_id) |
| hospitalflow | staff_onboarding | staff_onboarding_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | stock_movements | stock_movement_balance | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | stock_movements | stock_movements_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | stock_movements | stock_movements_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | stock_movements | stock_movements_pkey | PRIMARY KEY (id) |
| hospitalflow | stock_movements | stock_movements_quantity_check | CHECK ((quantity <> 0)) |
| hospitalflow | stock_reservations | reservation_stock_balance | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | stock_reservations | stock_reservations_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | stock_reservations | stock_reservations_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | stock_reservations | stock_reservations_pkey | PRIMARY KEY (id) |
| hospitalflow | stock_reservations | stock_reservations_prescription_id_fkey | FOREIGN KEY (prescription_id) REFERENCES hospitalflow.prescriptions(id) |
| hospitalflow | stock_reservations | stock_reservations_prescription_id_key | UNIQUE (prescription_id) |
| hospitalflow | stock_reservations | stock_reservations_quantity_check | CHECK ((quantity > 0)) |
| hospitalflow | stock_reservations | stock_reservations_status_check | CHECK ((status = ANY (ARRAY['Active'::text, 'Consumed'::text, 'Released'::text]))) |
| hospitalflow | suppliers | supplier_mobile_ten_digits | CHECK (((contact_phone IS NULL) OR (contact_phone ~ '^[0-9]{10}$'::text))) |
| hospitalflow | suppliers | suppliers_hospital_id_code_key | UNIQUE (hospital_id, code) |
| hospitalflow | suppliers | suppliers_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | suppliers | suppliers_pkey | PRIMARY KEY (id) |
| hospitalflow | system_settings | system_settings_pkey | PRIMARY KEY (key) |
| hospitalflow | user_departments | user_departments_department_fkey | FOREIGN KEY (department) REFERENCES hospitalflow.departments(name) |
| hospitalflow | user_departments | user_departments_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | user_departments | user_departments_pkey | PRIMARY KEY (user_id, department) |
| hospitalflow | user_departments | user_departments_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | user_permissions | user_permissions_permission_check | CHECK ((permission = ANY (ARRAY['Reception'::text, 'Doctor'::text, 'Nurse'::text, 'Pharmacist'::text, 'Billing'::text]))) |
| hospitalflow | user_permissions | user_permissions_pkey | PRIMARY KEY (user_id, permission) |
| hospitalflow | user_permissions | user_permissions_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | user_preferences | user_preferences_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | user_preferences | user_preferences_pkey | PRIMARY KEY (user_id) |
| hospitalflow | user_preferences | user_preferences_theme_check | CHECK ((theme = ANY (ARRAY['Default'::text, 'Dark'::text]))) |
| hospitalflow | user_preferences | user_preferences_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | users | users_name_check | CHECK (((length(name) >= 1) AND (length(name) <= 100))) |
| hospitalflow | users | users_pkey | PRIMARY KEY (id) |
| hospitalflow | users | users_registration_id_key | UNIQUE (registration_id) |
| hospitalflow | users | users_role_fkey | FOREIGN KEY (role) REFERENCES hospitalflow.roles(name) |
| hospitalflow | wards | wards_department_fkey | FOREIGN KEY (department) REFERENCES hospitalflow.departments(name) |
| hospitalflow | wards | wards_name_check | CHECK (((length(name) >= 1) AND (length(name) <= 100))) |
| hospitalflow | wards | wards_pkey | PRIMARY KEY (name) |
| hospitalflow | work_tasks | work_tasks_assigned_to_fkey | FOREIGN KEY (assigned_to) REFERENCES hospitalflow.users(id) |
| hospitalflow | work_tasks | work_tasks_created_by_fkey | FOREIGN KEY (created_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | work_tasks | work_tasks_hospital_id_fkey | FOREIGN KEY (hospital_id) REFERENCES hospitalflow.hospitals(id) |
| hospitalflow | work_tasks | work_tasks_location_check | CHECK (((length(location) >= 1) AND (length(location) <= 150))) |
| hospitalflow | work_tasks | work_tasks_pkey | PRIMARY KEY (id) |
| hospitalflow | work_tasks | work_tasks_status_check | CHECK ((status = ANY (ARRAY['Assigned'::text, 'In progress'::text, 'Completed'::text]))) |
| hospitalflow | work_tasks | work_tasks_title_check | CHECK (((length(title) >= 2) AND (length(title) <= 150))) |

## Database job definitions

Intervals are enforced by the database dispatcher. A separately installed scheduler must invoke it; a row in this table alone does not prove execution.

| Job | Task | Interval seconds | Enabled definition |
| --- | --- | --- | --- |
| backup-freshness | backup_monitor | 86400 | True |
| expired-sessions | session_cleanup | 3600 | True |
| integrity-monitor | integrity_check | 900 | True |
| operational-alerts | refresh_alerts | 60 | True |
| outbox-lease-recovery | recover_outbox_leases | 60 | True |
| planner-statistics | analyze_tables | 86400 | True |
| report-cache | refresh_reports | 900 | True |
| ward-daily-snapshot | daily_snapshot | 3600 | True |

