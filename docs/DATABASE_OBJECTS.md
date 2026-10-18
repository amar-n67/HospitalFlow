# Installed HospitalFlow database catalogue

Generated from the installed PostgreSQL metadata on `localhost:5432/hospitalflow`. No patient records, password hashes or credentials are included. Regenerate with `python3 scripts/export_database_catalog.py`.

| Object type | Count |
| --- | --- |
| EVENT TRIGGER | 2 |
| FUNCTION | 37 |
| INDEX | 130 |
| MATERIALIZED VIEW | 1 |
| POLICY | 4 |
| PROCEDURE | 23 |
| SEQUENCE | 5 |
| TABLE | 68 |
| TRIGGER | 92 |
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


### hospitalflow.beds

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| ward | text | NO |  |
| category | text | NO |  |
| status | text | NO |  |


### hospitalflow.bill_lines

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| bill_id | text | NO |  |
| description | text | NO |  |
| amount | numeric | NO |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.bills

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| patient_id | text | NO |  |
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


### hospitalflow.doctors

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| name | text | NO |  |
| department | text | NO |  |
| start | time without time zone | NO |  |
| end | time without time zone | NO |  |
| active | boolean | NO | true |


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


### hospitalflow.goods_receipt_lines

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| receipt_id | uuid | NO |  |
| purchase_order_line_id | uuid | NO |  |
| quantity | integer | NO |  |
| movement_id | text | NO |  |


### hospitalflow.goods_receipts

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| purchase_order_id | uuid | NO |  |
| reference | text | NO |  |
| received_by | text | NO |  |
| received_at | timestamp with time zone | NO | now() |


### hospitalflow.hospital_profile

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | smallint | NO |  |
| name | text | NO |  |
| currency | character | NO | 'INR'::bpchar |
| timezone | text | NO | 'Asia/Kolkata'::text |
| updated_at | timestamp with time zone | NO | now() |


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


### hospitalflow.integration_outbox

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| event_type | text | NO |  |
| aggregate_type | text | NO |  |
| aggregate_id | text | NO |  |
| payload | jsonb | NO | '{}'::jsonb |
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


### hospitalflow.notes

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| patient_id | text | NO |  |
| text | text | NO |  |
| kind | text | NO |  |
| at | timestamp with time zone | NO |  |


### hospitalflow.notification_acknowledgements

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| notification_id | text | NO |  |
| user_id | text | NO |  |
| reason | text | NO |  |
| at | timestamp with time zone | NO | now() |


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


### hospitalflow.patients

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| name | text | NO |  |
| dob | date | NO |  |
| sex | text | NO |  |
| phone | text | NO |  |
| created | timestamp with time zone | NO |  |


### hospitalflow.payment_reversals

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| payment_id | text | NO |  |
| amount | numeric | NO |  |
| reason | text | NO |  |
| approved_by | text | NO |  |
| at | timestamp with time zone | NO | now() |


### hospitalflow.payments

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| bill_id | text | NO |  |
| amount | numeric | NO |  |
| method | text | NO |  |
| at | timestamp with time zone | NO |  |


### hospitalflow.prescription_authors

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| prescription_id | text | NO |  |
| created_by | text | NO |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.prescription_dispensations

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| prescription_id | text | NO |  |
| movement_id | text | NO |  |
| bill_id | text | NO |  |
| dispensed_by | text | NO |  |
| at | timestamp with time zone | NO | now() |


### hospitalflow.prescriptions

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| patient_id | text | NO |  |
| medicine_id | text | NO |  |
| quantity | integer | NO |  |
| instructions | text | NO |  |
| status | text | NO |  |


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


### hospitalflow.provider_sessions

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| doctor_id | text | NO |  |
| starts_at | timestamp with time zone | NO |  |
| ends_at | timestamp with time zone | NO |  |
| capacity | integer | NO | 1 |


### hospitalflow.purchase_order_lines

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| purchase_order_id | uuid | NO |  |
| medicine_id | text | NO |  |
| quantity | integer | NO |  |
| unit_cost | numeric | NO |  |


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


### hospitalflow.sessions

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| user_id | text | NO |  |
| ticket | bytea | NO |  |
| expires_at | timestamp with time zone | NO |  |
| created_at | timestamp with time zone | NO | now() |


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


### hospitalflow.stock_movements

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | text | NO |  |
| medicine_id | text | NO |  |
| quantity | integer | NO |  |
| reason | text | NO |  |
| at | timestamp with time zone | NO |  |


### hospitalflow.stock_reservations

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| prescription_id | text | NO |  |
| medicine_id | text | NO |  |
| quantity | integer | NO |  |
| status | text | NO |  |
| created_at | timestamp with time zone | NO | now() |


### hospitalflow.suppliers

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| id | uuid | NO | gen_random_uuid() |
| code | text | NO |  |
| name | text | NO |  |
| contact_email | text | YES |  |
| contact_phone | text | YES |  |
| active | boolean | NO | true |


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


### hospitalflow.user_permissions

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| user_id | text | NO |  |
| permission | text | NO |  |


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


### hospitalflow.wards

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| name | text | NO |  |
| department | text | YES |  |
| active | boolean | NO | true |

## Stored procedures and functions

| Schema | Routine | Kind | Arguments | Security definer |
| --- | --- | --- | --- | --- |
| hf_api | admit_patient | PROCEDURE | INOUT p_id text, IN p_patient text, IN p_bed text, IN p_reason text | False |
| hf_api | approve_purchase_order | PROCEDURE | IN p_id uuid | False |
| hf_api | book_appointment | PROCEDURE | INOUT p_id text, IN p_patient text, IN p_doctor text, IN p_at timestamp with time zone, IN p_type text | False |
| hf_api | claim_outbox | FUNCTION | p_limit integer, p_lease_seconds integer | False |
| hf_api | complete_outbox | PROCEDURE | IN p_event uuid, IN p_token uuid, IN p_success boolean, IN p_error_code text | False |
| hf_api | create_bill | PROCEDURE | INOUT p_id text, IN p_patient text, IN p_description text, IN p_amount numeric | False |
| hf_api | discharge_patient | PROCEDURE | IN p_id text, IN p_summary text | False |
| hf_api | dispense_prescription | PROCEDURE | IN p_id text, INOUT p_bill text | False |
| hf_api | execute | FUNCTION | p_action text, p_payload jsonb, p_key uuid, p_hash text | False |
| hf_api | hospital_today | FUNCTION |  | False |
| hf_api | new_id | FUNCTION | p_prefix text | False |
| hf_api | positive_number | FUNCTION | p_body jsonb, p_key text, p_integer boolean | False |
| hf_api | post_adjustment | PROCEDURE | IN p_bill text, IN p_amount numeric, IN p_reason text, INOUT p_id text | False |
| hf_api | post_payment | PROCEDURE | IN p_bill text, IN p_amount numeric, IN p_method text, INOUT p_id text | False |
| hf_api | post_service_charge | PROCEDURE | IN p_bill text, IN p_service uuid, IN p_quantity numeric, INOUT p_id text | False |
| hf_api | receive_purchase_order | PROCEDURE | IN p_order uuid, IN p_reference text, IN p_lines jsonb, INOUT p_id uuid | False |
| hf_api | receive_stock | PROCEDURE | INOUT p_movement text, IN p_medicine text, IN p_quantity integer, IN p_reason text | False |
| hf_api | required_text | FUNCTION | p_body jsonb, p_key text, p_max integer | False |
| hf_api | reserve_prescription | PROCEDURE | IN p_prescription text, INOUT p_id uuid | False |
| hf_api | reverse_payment | PROCEDURE | IN p_payment text, IN p_amount numeric, IN p_reason text, INOUT p_id uuid | False |
| hf_api | save_patient | PROCEDURE | INOUT p_id text, IN p_name text, IN p_dob date, IN p_sex text, IN p_phone text | False |
| hf_api | set_appointment_status | PROCEDURE | IN p_id text, IN p_status text | False |
| hf_api | transfer_patient | PROCEDURE | IN p_id text, IN p_bed text, IN p_reason text | False |
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
| hf_security | can_access_encounter | FUNCTION | p_encounter uuid | True |
| hf_security | can_access_patient | FUNCTION | p_patient text | True |
| hf_security | protect_account | FUNCTION |  | False |
| hf_security | require_actor | FUNCTION | p_roles text[] | True |
| hospitalflow | complete_follow_up | FUNCTION |  | True |
| hospitalflow | enqueue_change | FUNCTION |  | True |
| hospitalflow | maintain_bed_history | FUNCTION |  | True |
| hospitalflow | prevent_ledger_changes | FUNCTION |  | False |
| hospitalflow | record_row_history | FUNCTION |  | True |
| hospitalflow | sync_encounter | FUNCTION |  | True |
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
| hospitalflow | POLICY | clinical_orders.encounter_scope |
| hospitalflow | POLICY | follow_ups.patient_scope |
| hospitalflow | POLICY | patient_consents.patient_scope |
| hospitalflow | POLICY | patient_contacts.patient_scope |
| hf_ops | SEQUENCE | schema_change_events_id_seq |
| hospitalflow | SEQUENCE | bed_assignments_id_seq |
| hospitalflow | SEQUENCE | data_protection_keys_id_seq |
| hospitalflow | SEQUENCE | document_number |
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
| hospitalflow | admission_events.record_history |
| hospitalflow | admissions.admission_consistency |
| hospitalflow | admissions.bed_history |
| hospitalflow | admissions.discharge_readiness |
| hospitalflow | admissions.encounter_sync |
| hospitalflow | admissions.enqueue_integration_event |
| hospitalflow | admissions.record_history |
| hospitalflow | appointments.appointment_overlap |
| hospitalflow | appointments.appointment_schedule |
| hospitalflow | appointments.encounter_sync |
| hospitalflow | appointments.enqueue_integration_event |
| hospitalflow | appointments.follow_up_completion |
| hospitalflow | appointments.record_history |
| hospitalflow | beds.bed_consistency |
| hospitalflow | beds.record_history |
| hospitalflow | bill_lines.immutable_ledger |
| hospitalflow | bill_lines.line_balance |
| hospitalflow | bill_lines.record_history |
| hospitalflow | bills.record_history |
| hospitalflow | clinical_orders.record_history |
| hospitalflow | departments.record_history |
| hospitalflow | discharge_tasks.record_history |
| hospitalflow | doctors.record_history |
| hospitalflow | encounters.record_history |
| hospitalflow | follow_ups.record_history |
| hospitalflow | goods_receipt_lines.immutable_ledger |
| hospitalflow | goods_receipt_lines.record_history |
| hospitalflow | goods_receipts.immutable_ledger |
| hospitalflow | goods_receipts.record_history |
| hospitalflow | hospital_profile.record_history |
| hospitalflow | integration_outbox.immutable_ledger |
| hospitalflow | invoice_line_context.immutable_ledger |
| hospitalflow | invoice_line_context.record_history |
| hospitalflow | medicine_batch_holds.record_history |
| hospitalflow | medicine_batches.record_history |
| hospitalflow | medicine_batches.stock_batch_balance |
| hospitalflow | notes.record_history |
| hospitalflow | notification_acknowledgements.immutable_ledger |
| hospitalflow | notification_acknowledgements.record_history |
| hospitalflow | patient_access_grants.record_history |
| hospitalflow | patient_consents.record_history |
| hospitalflow | patient_contacts.record_history |
| hospitalflow | patients.enqueue_integration_event |
| hospitalflow | patients.patient_identity |
| hospitalflow | patients.record_history |
| hospitalflow | payment_reversals.enqueue_integration_event |
| hospitalflow | payment_reversals.immutable_ledger |
| hospitalflow | payment_reversals.payment_reversal_limit |
| hospitalflow | payment_reversals.record_history |
| hospitalflow | payments.enqueue_integration_event |
| hospitalflow | payments.immutable_ledger |
| hospitalflow | payments.payment_balance |
| hospitalflow | payments.record_history |
| hospitalflow | prescription_authors.record_history |
| hospitalflow | prescription_dispensations.immutable_ledger |
| hospitalflow | prescription_dispensations.record_history |
| hospitalflow | prescriptions.dispense_expiry |
| hospitalflow | prescriptions.dispense_trace |
| hospitalflow | prescriptions.enqueue_integration_event |
| hospitalflow | prescriptions.prescription_state |
| hospitalflow | prescriptions.record_history |
| hospitalflow | provider_absences.absence_conflict |
| hospitalflow | provider_absences.record_history |
| hospitalflow | provider_sessions.provider_session_overlap |
| hospitalflow | provider_sessions.record_history |
| hospitalflow | purchase_order_lines.record_history |
| hospitalflow | purchase_orders.enqueue_integration_event |
| hospitalflow | purchase_orders.record_history |
| hospitalflow | row_history.immutable_ledger |
| hospitalflow | service_catalog.record_history |
| hospitalflow | service_prices.price_effectivity |
| hospitalflow | service_prices.record_history |
| hospitalflow | staff_members.record_history |
| hospitalflow | stock_movements.immutable_ledger |
| hospitalflow | stock_movements.record_history |
| hospitalflow | stock_movements.stock_movement_balance |
| hospitalflow | stock_reservations.record_history |
| hospitalflow | stock_reservations.reservation_stock_balance |
| hospitalflow | suppliers.record_history |
| hospitalflow | system_settings.record_history |
| hospitalflow | user_departments.record_history |
| hospitalflow | user_permissions.record_history |
| hospitalflow | users.protect_account |
| hospitalflow | users.record_history |
| hospitalflow | wards.record_history |

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
| hospitalflow | activity_log | activity_log_pkey | PRIMARY KEY (id) |
| hospitalflow | admission_events | admission_events_actor_id_fkey | FOREIGN KEY (actor_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | admission_events | admission_events_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | admission_events | admission_events_from_bed_fkey | FOREIGN KEY (from_bed) REFERENCES hospitalflow.beds(id) |
| hospitalflow | admission_events | admission_events_kind_check | CHECK ((kind = ANY (ARRAY['Admission'::text, 'Transfer'::text, 'Discharge'::text]))) |
| hospitalflow | admission_events | admission_events_pkey | PRIMARY KEY (id) |
| hospitalflow | admission_events | admission_events_reason_check | CHECK (((length(TRIM(BOTH FROM reason)) >= 1) AND (length(TRIM(BOTH FROM reason)) <= 4000))) |
| hospitalflow | admission_events | admission_events_to_bed_fkey | FOREIGN KEY (to_bed) REFERENCES hospitalflow.beds(id) |
| hospitalflow | admissions | admission_consistency | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | admissions | admissions_bed_id_fkey | FOREIGN KEY (bed_id) REFERENCES hospitalflow.beds(id) |
| hospitalflow | admissions | admissions_check | CHECK ((((status = 'Admitted'::text) AND (discharged IS NULL)) OR ((status = 'Discharged'::text) AND (discharged IS NOT NULL) AND (discharged >= at)))) |
| hospitalflow | admissions | admissions_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | admissions | admissions_pkey | PRIMARY KEY (id) |
| hospitalflow | admissions | admissions_status_check | CHECK ((status = ANY (ARRAY['Admitted'::text, 'Discharged'::text]))) |
| hospitalflow | admissions | discharge_readiness | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | appointments | appointments_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | appointments | appointments_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | appointments | appointments_pkey | PRIMARY KEY (id) |
| hospitalflow | appointments | appointments_status_check | CHECK ((status = ANY (ARRAY['Scheduled'::text, 'Checked in'::text, 'In consultation'::text, 'Completed'::text, 'Cancelled'::text, 'No show'::text]))) |
| hospitalflow | auth_attempts | auth_attempts_failures_check | CHECK ((failures >= 0)) |
| hospitalflow | auth_attempts | auth_attempts_pkey | PRIMARY KEY (key_hash) |
| hospitalflow | bed_assignments | bed_assignments_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | bed_assignments | bed_assignments_bed_id_fkey | FOREIGN KEY (bed_id) REFERENCES hospitalflow.beds(id) |
| hospitalflow | bed_assignments | bed_assignments_check | CHECK (((to_time IS NULL) OR (to_time >= from_time))) |
| hospitalflow | bed_assignments | bed_assignments_pkey | PRIMARY KEY (id) |
| hospitalflow | beds | bed_consistency | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | beds | beds_pkey | PRIMARY KEY (id) |
| hospitalflow | beds | beds_status_check | CHECK ((status = ANY (ARRAY['Available'::text, 'Occupied'::text, 'Cleaning'::text, 'Maintenance'::text]))) |
| hospitalflow | beds | beds_ward_fkey | FOREIGN KEY (ward) REFERENCES hospitalflow.wards(name) |
| hospitalflow | bill_lines | bill_lines_amount_check | CHECK ((amount <> (0)::numeric)) |
| hospitalflow | bill_lines | bill_lines_bill_id_fkey | FOREIGN KEY (bill_id) REFERENCES hospitalflow.bills(id) |
| hospitalflow | bill_lines | bill_lines_pkey | PRIMARY KEY (id) |
| hospitalflow | bill_lines | line_balance | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | bills | bills_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | bills | bills_pkey | PRIMARY KEY (id) |
| hospitalflow | clinical_orders | clinical_orders_check | CHECK (((status = 'Completed'::text) = (completed_at IS NOT NULL))) |
| hospitalflow | clinical_orders | clinical_orders_encounter_id_fkey | FOREIGN KEY (encounter_id) REFERENCES hospitalflow.encounters(id) |
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
| hospitalflow | discharge_tasks | discharge_tasks_pkey | PRIMARY KEY (id) |
| hospitalflow | doctors | doctors_check | CHECK ((start < "end")) |
| hospitalflow | doctors | doctors_department_fkey | FOREIGN KEY (department) REFERENCES hospitalflow.departments(name) |
| hospitalflow | doctors | doctors_pkey | PRIMARY KEY (id) |
| hospitalflow | encounters | encounters_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | encounters | encounters_admission_id_key | UNIQUE (admission_id) |
| hospitalflow | encounters | encounters_appointment_id_fkey | FOREIGN KEY (appointment_id) REFERENCES hospitalflow.appointments(id) |
| hospitalflow | encounters | encounters_appointment_id_key | UNIQUE (appointment_id) |
| hospitalflow | encounters | encounters_check | CHECK ((((kind = 'Outpatient'::hospitalflow.encounter_kind) AND (appointment_id IS NOT NULL) AND (admission_id IS NULL)) OR ((kind = 'Inpatient'::hospitalflow.encounter_kind) AND (admission_id IS NOT NULL) AND (appointment_id IS NULL)))) |
| hospitalflow | encounters | encounters_check1 | CHECK (((closed_at IS NULL) OR (closed_at >= opened_at))) |
| hospitalflow | encounters | encounters_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | encounters | encounters_pkey | PRIMARY KEY (id) |
| hospitalflow | encounters | encounters_status_check | CHECK ((status = ANY (ARRAY['Open'::text, 'Completed'::text, 'Cancelled'::text]))) |
| hospitalflow | follow_ups | follow_ups_admission_id_fkey | FOREIGN KEY (admission_id) REFERENCES hospitalflow.admissions(id) |
| hospitalflow | follow_ups | follow_ups_appointment_id_fkey | FOREIGN KEY (appointment_id) REFERENCES hospitalflow.appointments(id) |
| hospitalflow | follow_ups | follow_ups_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | follow_ups | follow_ups_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | follow_ups | follow_ups_pkey | PRIMARY KEY (id) |
| hospitalflow | follow_ups | follow_ups_status_check | CHECK ((status = ANY (ARRAY['Pending'::text, 'Booked'::text, 'Completed'::text, 'Cancelled'::text]))) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_movement_id_fkey | FOREIGN KEY (movement_id) REFERENCES hospitalflow.stock_movements(id) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_movement_id_key | UNIQUE (movement_id) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_pkey | PRIMARY KEY (id) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_purchase_order_line_id_fkey | FOREIGN KEY (purchase_order_line_id) REFERENCES hospitalflow.purchase_order_lines(id) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_quantity_check | CHECK ((quantity > 0)) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_receipt_id_fkey | FOREIGN KEY (receipt_id) REFERENCES hospitalflow.goods_receipts(id) |
| hospitalflow | goods_receipt_lines | goods_receipt_lines_receipt_id_purchase_order_line_id_key | UNIQUE (receipt_id, purchase_order_line_id) |
| hospitalflow | goods_receipts | goods_receipts_pkey | PRIMARY KEY (id) |
| hospitalflow | goods_receipts | goods_receipts_purchase_order_id_fkey | FOREIGN KEY (purchase_order_id) REFERENCES hospitalflow.purchase_orders(id) |
| hospitalflow | goods_receipts | goods_receipts_purchase_order_id_reference_key | UNIQUE (purchase_order_id, reference) |
| hospitalflow | goods_receipts | goods_receipts_received_by_fkey | FOREIGN KEY (received_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | hospital_profile | hospital_profile_id_check | CHECK ((id = 1)) |
| hospitalflow | hospital_profile | hospital_profile_name_check | CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 150))) |
| hospitalflow | hospital_profile | hospital_profile_pkey | PRIMARY KEY (id) |
| hospitalflow | idempotency_hash_keys | idempotency_hash_keys_id_check | CHECK ((id = 1)) |
| hospitalflow | idempotency_hash_keys | idempotency_hash_keys_pkey | PRIMARY KEY (id) |
| hospitalflow | idempotency_hash_keys | idempotency_hash_keys_secret_check | CHECK ((octet_length(secret) = 32)) |
| hospitalflow | idempotency_keys | idempotency_keys_pkey | PRIMARY KEY (user_id, key) |
| hospitalflow | idempotency_keys | idempotency_keys_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | integration_outbox | integration_outbox_payload_check | CHECK ((jsonb_typeof(payload) = 'object'::text)) |
| hospitalflow | integration_outbox | integration_outbox_pkey | PRIMARY KEY (id) |
| hospitalflow | integration_outbox | minimal_outbox_payload | CHECK (((payload - ARRAY['reference'::text, 'status'::text, 'kind'::text]) = '{}'::jsonb)) |
| hospitalflow | invoice_line_context | invoice_line_context_check | CHECK ((num_nonnulls(service_price_id, medicine_id) = 1)) |
| hospitalflow | invoice_line_context | invoice_line_context_line_id_fkey | FOREIGN KEY (line_id) REFERENCES hospitalflow.bill_lines(id) |
| hospitalflow | invoice_line_context | invoice_line_context_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | invoice_line_context | invoice_line_context_pkey | PRIMARY KEY (line_id) |
| hospitalflow | invoice_line_context | invoice_line_context_quantity_check | CHECK ((quantity > (0)::numeric)) |
| hospitalflow | invoice_line_context | invoice_line_context_service_price_id_fkey | FOREIGN KEY (service_price_id) REFERENCES hospitalflow.service_prices(id) |
| hospitalflow | invoice_line_context | invoice_line_context_unit_price_check | CHECK ((unit_price > (0)::numeric)) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_check | CHECK (((released_by IS NULL) = (released_at IS NULL))) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_check1 | CHECK (((released_at IS NULL) OR (released_at >= held_at))) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_held_by_fkey | FOREIGN KEY (held_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_pkey | PRIMARY KEY (id) |
| hospitalflow | medicine_batch_holds | medicine_batch_holds_released_by_fkey | FOREIGN KEY (released_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | medicine_batches | medicine_batches_name_batch_key | UNIQUE (name, batch) |
| hospitalflow | medicine_batches | medicine_batches_pkey | PRIMARY KEY (id) |
| hospitalflow | medicine_batches | medicine_batches_price_check | CHECK ((price > (0)::numeric)) |
| hospitalflow | medicine_batches | medicine_batches_quantity_check | CHECK ((quantity >= 0)) |
| hospitalflow | medicine_batches | medicine_batches_reorder_check | CHECK ((reorder > 0)) |
| hospitalflow | medicine_batches | stock_batch_balance | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | notes | notes_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | notes | notes_pkey | PRIMARY KEY (id) |
| hospitalflow | notes | notes_text_check | CHECK ((length(text) <= 4000)) |
| hospitalflow | notification_acknowledgements | notification_acknowledgements_notification_id_fkey | FOREIGN KEY (notification_id) REFERENCES hospitalflow.notifications(id) |
| hospitalflow | notification_acknowledgements | notification_acknowledgements_pkey | PRIMARY KEY (notification_id, user_id) |
| hospitalflow | notification_acknowledgements | notification_acknowledgements_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | notifications | notifications_pkey | PRIMARY KEY (id) |
| hospitalflow | outbox_delivery | outbox_delivery_attempts_check | CHECK ((attempts >= 0)) |
| hospitalflow | outbox_delivery | outbox_delivery_check | CHECK (((status = 'Leased'::text) = ((lease_token IS NOT NULL) AND (lease_until IS NOT NULL)))) |
| hospitalflow | outbox_delivery | outbox_delivery_check1 | CHECK (((status = 'Delivered'::text) = (delivered_at IS NOT NULL))) |
| hospitalflow | outbox_delivery | outbox_delivery_event_id_fkey | FOREIGN KEY (event_id) REFERENCES hospitalflow.integration_outbox(id) |
| hospitalflow | outbox_delivery | outbox_delivery_pkey | PRIMARY KEY (event_id) |
| hospitalflow | outbox_delivery | outbox_delivery_status_check | CHECK ((status = ANY (ARRAY['Pending'::text, 'Leased'::text, 'Delivered'::text, 'Dead letter'::text]))) |
| hospitalflow | patient_access_grants | patient_access_grants_check | CHECK ((expires_at > created_at)) |
| hospitalflow | patient_access_grants | patient_access_grants_granted_by_fkey | FOREIGN KEY (granted_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | patient_access_grants | patient_access_grants_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | patient_access_grants | patient_access_grants_pkey | PRIMARY KEY (id) |
| hospitalflow | patient_access_grants | patient_access_grants_purpose_check | CHECK (((length(TRIM(BOTH FROM purpose)) >= 1) AND (length(TRIM(BOTH FROM purpose)) <= 200))) |
| hospitalflow | patient_access_grants | patient_access_grants_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | patient_consents | patient_consents_check | CHECK (((expires_at IS NULL) OR (expires_at > granted_at))) |
| hospitalflow | patient_consents | patient_consents_check1 | CHECK (((revoked_at IS NULL) OR (revoked_at >= granted_at))) |
| hospitalflow | patient_consents | patient_consents_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | patient_consents | patient_consents_pkey | PRIMARY KEY (id) |
| hospitalflow | patient_consents | patient_consents_recorded_by_fkey | FOREIGN KEY (recorded_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | patient_contacts | patient_contacts_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | patient_contacts | patient_contacts_pkey | PRIMARY KEY (id) |
| hospitalflow | patients | patients_dob_check | CHECK ((dob >= '1900-01-01'::date)) |
| hospitalflow | patients | patients_name_check | CHECK (((length(name) >= 1) AND (length(name) <= 100))) |
| hospitalflow | patients | patients_phone_check | CHECK (((length(phone) >= 7) AND (length(phone) <= 20))) |
| hospitalflow | patients | patients_pkey | PRIMARY KEY (id) |
| hospitalflow | patients | patients_sex_check | CHECK ((sex = ANY (ARRAY['Male'::text, 'Female'::text, 'Other'::text, 'Prefer not to say'::text]))) |
| hospitalflow | payment_reversals | payment_reversal_limit | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | payment_reversals | payment_reversals_amount_check | CHECK ((amount > (0)::numeric)) |
| hospitalflow | payment_reversals | payment_reversals_approved_by_fkey | FOREIGN KEY (approved_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | payment_reversals | payment_reversals_payment_id_fkey | FOREIGN KEY (payment_id) REFERENCES hospitalflow.payments(id) |
| hospitalflow | payment_reversals | payment_reversals_pkey | PRIMARY KEY (id) |
| hospitalflow | payment_reversals | payment_reversals_reason_check | CHECK (((length(TRIM(BOTH FROM reason)) >= 1) AND (length(TRIM(BOTH FROM reason)) <= 500))) |
| hospitalflow | payments | payment_balance | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | payments | payments_amount_check | CHECK ((amount > (0)::numeric)) |
| hospitalflow | payments | payments_bill_id_fkey | FOREIGN KEY (bill_id) REFERENCES hospitalflow.bills(id) |
| hospitalflow | payments | payments_method_check | CHECK ((method = ANY (ARRAY['Cash'::text, 'Card'::text, 'UPI'::text, 'Bank transfer'::text]))) |
| hospitalflow | payments | payments_pkey | PRIMARY KEY (id) |
| hospitalflow | prescription_authors | prescription_authors_created_by_fkey | FOREIGN KEY (created_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | prescription_authors | prescription_authors_pkey | PRIMARY KEY (prescription_id) |
| hospitalflow | prescription_authors | prescription_authors_prescription_id_fkey | FOREIGN KEY (prescription_id) REFERENCES hospitalflow.prescriptions(id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_bill_id_fkey | FOREIGN KEY (bill_id) REFERENCES hospitalflow.bills(id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_bill_id_key | UNIQUE (bill_id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_dispensed_by_fkey | FOREIGN KEY (dispensed_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_movement_id_fkey | FOREIGN KEY (movement_id) REFERENCES hospitalflow.stock_movements(id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_movement_id_key | UNIQUE (movement_id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_pkey | PRIMARY KEY (id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_prescription_id_fkey | FOREIGN KEY (prescription_id) REFERENCES hospitalflow.prescriptions(id) |
| hospitalflow | prescription_dispensations | prescription_dispensations_prescription_id_key | UNIQUE (prescription_id) |
| hospitalflow | prescriptions | dispense_trace | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | prescriptions | prescriptions_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | prescriptions | prescriptions_patient_id_fkey | FOREIGN KEY (patient_id) REFERENCES hospitalflow.patients(id) |
| hospitalflow | prescriptions | prescriptions_pkey | PRIMARY KEY (id) |
| hospitalflow | prescriptions | prescriptions_quantity_check | CHECK ((quantity > 0)) |
| hospitalflow | prescriptions | prescriptions_status_check | CHECK ((status = ANY (ARRAY['Pending'::text, 'Dispensed'::text, 'Cancelled'::text]))) |
| hospitalflow | provider_absences | provider_absences_approved_by_fkey | FOREIGN KEY (approved_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | provider_absences | provider_absences_check | CHECK ((ends_at > starts_at)) |
| hospitalflow | provider_absences | provider_absences_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | provider_absences | provider_absences_pkey | PRIMARY KEY (id) |
| hospitalflow | provider_sessions | provider_sessions_capacity_check | CHECK ((capacity = 1)) |
| hospitalflow | provider_sessions | provider_sessions_check | CHECK ((ends_at > starts_at)) |
| hospitalflow | provider_sessions | provider_sessions_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | provider_sessions | provider_sessions_doctor_id_starts_at_key | UNIQUE (doctor_id, starts_at) |
| hospitalflow | provider_sessions | provider_sessions_pkey | PRIMARY KEY (id) |
| hospitalflow | purchase_order_lines | purchase_order_lines_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | purchase_order_lines | purchase_order_lines_pkey | PRIMARY KEY (id) |
| hospitalflow | purchase_order_lines | purchase_order_lines_purchase_order_id_fkey | FOREIGN KEY (purchase_order_id) REFERENCES hospitalflow.purchase_orders(id) |
| hospitalflow | purchase_order_lines | purchase_order_lines_purchase_order_id_medicine_id_key | UNIQUE (purchase_order_id, medicine_id) |
| hospitalflow | purchase_order_lines | purchase_order_lines_quantity_check | CHECK ((quantity > 0)) |
| hospitalflow | purchase_order_lines | purchase_order_lines_unit_cost_check | CHECK ((unit_cost > (0)::numeric)) |
| hospitalflow | purchase_orders | purchase_orders_approved_by_fkey | FOREIGN KEY (approved_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | purchase_orders | purchase_orders_check | CHECK (((status = ANY (ARRAY['Draft'::hospitalflow.purchase_status, 'Cancelled'::hospitalflow.purchase_status])) OR (approved_by IS NOT NULL))) |
| hospitalflow | purchase_orders | purchase_orders_created_by_fkey | FOREIGN KEY (created_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | purchase_orders | purchase_orders_number_key | UNIQUE (number) |
| hospitalflow | purchase_orders | purchase_orders_pkey | PRIMARY KEY (id) |
| hospitalflow | purchase_orders | purchase_orders_supplier_id_fkey | FOREIGN KEY (supplier_id) REFERENCES hospitalflow.suppliers(id) |
| hospitalflow | roles | roles_pkey | PRIMARY KEY (name) |
| hospitalflow | row_history | row_history_pkey | PRIMARY KEY (id) |
| hospitalflow | schema_versions | schema_versions_pkey | PRIMARY KEY (version) |
| hospitalflow | service_catalog | service_catalog_category_check | CHECK ((category = ANY (ARRAY['Consultation'::text, 'Room'::text, 'Laboratory'::text, 'Imaging'::text, 'Procedure'::text, 'Other'::text]))) |
| hospitalflow | service_catalog | service_catalog_code_key | UNIQUE (code) |
| hospitalflow | service_catalog | service_catalog_department_fkey | FOREIGN KEY (department) REFERENCES hospitalflow.departments(name) |
| hospitalflow | service_catalog | service_catalog_pkey | PRIMARY KEY (id) |
| hospitalflow | service_prices | service_prices_amount_check | CHECK ((amount > (0)::numeric)) |
| hospitalflow | service_prices | service_prices_check | CHECK (((effective_to IS NULL) OR (effective_to > effective_from))) |
| hospitalflow | service_prices | service_prices_created_by_fkey | FOREIGN KEY (created_by) REFERENCES hospitalflow.users(id) |
| hospitalflow | service_prices | service_prices_pkey | PRIMARY KEY (id) |
| hospitalflow | service_prices | service_prices_service_id_effective_from_key | UNIQUE (service_id, effective_from) |
| hospitalflow | service_prices | service_prices_service_id_fkey | FOREIGN KEY (service_id) REFERENCES hospitalflow.service_catalog(id) |
| hospitalflow | sessions | sessions_pkey | PRIMARY KEY (id) |
| hospitalflow | sessions | sessions_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | staff_members | staff_members_department_fkey | FOREIGN KEY (department) REFERENCES hospitalflow.departments(name) |
| hospitalflow | staff_members | staff_members_doctor_id_fkey | FOREIGN KEY (doctor_id) REFERENCES hospitalflow.doctors(id) |
| hospitalflow | staff_members | staff_members_doctor_id_key | UNIQUE (doctor_id) |
| hospitalflow | staff_members | staff_members_employee_number_key | UNIQUE (employee_number) |
| hospitalflow | staff_members | staff_members_pkey | PRIMARY KEY (id) |
| hospitalflow | staff_members | staff_members_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | staff_members | staff_members_user_id_key | UNIQUE (user_id) |
| hospitalflow | stock_movements | stock_movement_balance | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | stock_movements | stock_movements_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | stock_movements | stock_movements_pkey | PRIMARY KEY (id) |
| hospitalflow | stock_movements | stock_movements_quantity_check | CHECK ((quantity <> 0)) |
| hospitalflow | stock_reservations | reservation_stock_balance | TRIGGER DEFERRABLE INITIALLY DEFERRED |
| hospitalflow | stock_reservations | stock_reservations_medicine_id_fkey | FOREIGN KEY (medicine_id) REFERENCES hospitalflow.medicine_batches(id) |
| hospitalflow | stock_reservations | stock_reservations_pkey | PRIMARY KEY (id) |
| hospitalflow | stock_reservations | stock_reservations_prescription_id_fkey | FOREIGN KEY (prescription_id) REFERENCES hospitalflow.prescriptions(id) |
| hospitalflow | stock_reservations | stock_reservations_prescription_id_key | UNIQUE (prescription_id) |
| hospitalflow | stock_reservations | stock_reservations_quantity_check | CHECK ((quantity > 0)) |
| hospitalflow | stock_reservations | stock_reservations_status_check | CHECK ((status = ANY (ARRAY['Active'::text, 'Consumed'::text, 'Released'::text]))) |
| hospitalflow | suppliers | suppliers_code_key | UNIQUE (code) |
| hospitalflow | suppliers | suppliers_pkey | PRIMARY KEY (id) |
| hospitalflow | system_settings | system_settings_pkey | PRIMARY KEY (key) |
| hospitalflow | user_departments | user_departments_department_fkey | FOREIGN KEY (department) REFERENCES hospitalflow.departments(name) |
| hospitalflow | user_departments | user_departments_pkey | PRIMARY KEY (user_id, department) |
| hospitalflow | user_departments | user_departments_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | user_permissions | user_permissions_permission_check | CHECK ((permission = ANY (ARRAY['Reception'::text, 'Doctor'::text, 'Nurse'::text, 'Pharmacist'::text, 'Billing'::text]))) |
| hospitalflow | user_permissions | user_permissions_pkey | PRIMARY KEY (user_id, permission) |
| hospitalflow | user_permissions | user_permissions_user_id_fkey | FOREIGN KEY (user_id) REFERENCES hospitalflow.users(id) |
| hospitalflow | users | users_name_check | CHECK (((length(name) >= 1) AND (length(name) <= 100))) |
| hospitalflow | users | users_pkey | PRIMARY KEY (id) |
| hospitalflow | users | users_role_fkey | FOREIGN KEY (role) REFERENCES hospitalflow.roles(name) |
| hospitalflow | wards | wards_department_fkey | FOREIGN KEY (department) REFERENCES hospitalflow.departments(name) |
| hospitalflow | wards | wards_name_check | CHECK (((length(name) >= 1) AND (length(name) <= 100))) |
| hospitalflow | wards | wards_pkey | PRIMARY KEY (name) |

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

