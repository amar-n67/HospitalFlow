-- Additive database foundation. Existing identifiers and application columns are preserved.
CREATE SCHEMA hf_api;
CREATE SCHEMA hf_security;
CREATE SCHEMA hf_reporting;
CREATE SCHEMA hf_ops;
REVOKE ALL ON SCHEMA hf_api,hf_security,hf_reporting,hf_ops FROM PUBLIC;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='hospitalflow_job_runner') THEN CREATE ROLE hospitalflow_job_runner NOLOGIN;END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='hospitalflow_report_reader') THEN CREATE ROLE hospitalflow_report_reader NOLOGIN;END IF;
END $$;
CREATE SEQUENCE hospitalflow.document_number AS bigint START WITH 10001;
CREATE TYPE hospitalflow.encounter_kind AS ENUM('Outpatient','Inpatient');
CREATE TYPE hospitalflow.purchase_status AS ENUM('Draft','Approved','Partially received','Received','Cancelled');
CREATE TABLE hospitalflow.hospital_profile(
 id smallint PRIMARY KEY CHECK(id=1),name text NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 150),
 currency char(3) NOT NULL DEFAULT 'INR',timezone text NOT NULL DEFAULT 'Asia/Kolkata',updated_at timestamptz NOT NULL DEFAULT now());
INSERT INTO hospitalflow.hospital_profile(id,name) VALUES(1,'HospitalFlow');
ALTER TABLE hospitalflow.departments ADD COLUMN active boolean NOT NULL DEFAULT true;
ALTER TABLE hospitalflow.wards ADD COLUMN department text REFERENCES hospitalflow.departments(name),ADD COLUMN active boolean NOT NULL DEFAULT true;
ALTER TABLE hospitalflow.doctors ADD COLUMN active boolean NOT NULL DEFAULT true;
CREATE TABLE hospitalflow.staff_members(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id text UNIQUE REFERENCES hospitalflow.users(id),doctor_id text UNIQUE REFERENCES hospitalflow.doctors(id),
 employee_number text NOT NULL UNIQUE,department text NOT NULL REFERENCES hospitalflow.departments(name),job_title text NOT NULL,active boolean NOT NULL DEFAULT true,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.user_departments(user_id text NOT NULL REFERENCES hospitalflow.users(id),department text NOT NULL REFERENCES hospitalflow.departments(name),PRIMARY KEY(user_id,department));
CREATE TABLE hospitalflow.patient_access_grants(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id text NOT NULL REFERENCES hospitalflow.users(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),
 purpose text NOT NULL CHECK(length(trim(purpose)) BETWEEN 1 AND 200),expires_at timestamptz NOT NULL,granted_by text NOT NULL REFERENCES hospitalflow.users(id),created_at timestamptz NOT NULL DEFAULT now(),CHECK(expires_at>created_at));
CREATE INDEX patient_access_grants_lookup ON hospitalflow.patient_access_grants(user_id,patient_id,expires_at);
CREATE TABLE hospitalflow.patient_contacts(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),name text NOT NULL,relationship text NOT NULL,phone text NOT NULL,
 is_emergency boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX patient_contacts_patient_idx ON hospitalflow.patient_contacts(patient_id);
CREATE TABLE hospitalflow.patient_consents(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),purpose text NOT NULL,
 granted_at timestamptz NOT NULL,expires_at timestamptz,revoked_at timestamptz,evidence_reference text NOT NULL,recorded_by text NOT NULL REFERENCES hospitalflow.users(id),
 CHECK(expires_at IS NULL OR expires_at>granted_at),CHECK(revoked_at IS NULL OR revoked_at>=granted_at));
CREATE TABLE hospitalflow.provider_absences(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),doctor_id text NOT NULL REFERENCES hospitalflow.doctors(id),starts_at timestamptz NOT NULL,ends_at timestamptz NOT NULL,
 reason_code text NOT NULL,approved_by text NOT NULL REFERENCES hospitalflow.users(id),cancelled_at timestamptz,CHECK(ends_at>starts_at));
CREATE INDEX provider_absences_doctor_time_idx ON hospitalflow.provider_absences(doctor_id,starts_at,ends_at) WHERE cancelled_at IS NULL;
CREATE TABLE hospitalflow.provider_sessions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),doctor_id text NOT NULL REFERENCES hospitalflow.doctors(id),starts_at timestamptz NOT NULL,ends_at timestamptz NOT NULL,
 capacity integer NOT NULL DEFAULT 1 CHECK(capacity=1),CHECK(ends_at>starts_at),UNIQUE(doctor_id,starts_at));
CREATE TABLE hospitalflow.encounters(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),kind hospitalflow.encounter_kind NOT NULL,
 appointment_id text UNIQUE REFERENCES hospitalflow.appointments(id),admission_id text UNIQUE REFERENCES hospitalflow.admissions(id),
 opened_at timestamptz NOT NULL,closed_at timestamptz,status text NOT NULL CHECK(status IN ('Open','Completed','Cancelled')),
 CHECK((kind='Outpatient' AND appointment_id IS NOT NULL AND admission_id IS NULL) OR(kind='Inpatient' AND admission_id IS NOT NULL AND appointment_id IS NULL)),CHECK(closed_at IS NULL OR closed_at>=opened_at));
CREATE INDEX encounters_patient_idx ON hospitalflow.encounters(patient_id,opened_at DESC);
INSERT INTO hospitalflow.encounters(patient_id,kind,appointment_id,opened_at,closed_at,status)
 SELECT patient_id,'Outpatient',id,at,CASE WHEN status IN ('Completed','Cancelled','No show') THEN greatest(at,now()) END,
 CASE WHEN status='Completed' THEN 'Completed' WHEN status IN ('Cancelled','No show') THEN 'Cancelled' ELSE 'Open' END FROM hospitalflow.appointments;
INSERT INTO hospitalflow.encounters(patient_id,kind,admission_id,opened_at,closed_at,status)
 SELECT patient_id,'Inpatient',id,at,discharged,CASE WHEN status='Discharged' THEN 'Completed' ELSE 'Open' END FROM hospitalflow.admissions;
CREATE TABLE hospitalflow.service_catalog(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),code text NOT NULL UNIQUE,name text NOT NULL,department text REFERENCES hospitalflow.departments(name),
 category text NOT NULL CHECK(category IN ('Consultation','Room','Laboratory','Imaging','Procedure','Other')),active boolean NOT NULL DEFAULT true);
CREATE TABLE hospitalflow.service_prices(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),service_id uuid NOT NULL REFERENCES hospitalflow.service_catalog(id),
 amount numeric(14,2) NOT NULL CHECK(amount>0),currency char(3) NOT NULL DEFAULT 'INR',effective_from timestamptz NOT NULL,effective_to timestamptz,created_by text REFERENCES hospitalflow.users(id),
 CHECK(effective_to IS NULL OR effective_to>effective_from),UNIQUE(service_id,effective_from));
CREATE INDEX service_prices_effective_idx ON hospitalflow.service_prices(service_id,effective_from DESC);
CREATE TABLE hospitalflow.invoice_line_context(line_id text PRIMARY KEY REFERENCES hospitalflow.bill_lines(id),service_price_id uuid REFERENCES hospitalflow.service_prices(id),
 medicine_id text REFERENCES hospitalflow.medicine_batches(id),quantity numeric(14,3) NOT NULL CHECK(quantity>0),unit_price numeric(14,2) NOT NULL CHECK(unit_price>0),currency char(3) NOT NULL DEFAULT 'INR',
 CHECK(num_nonnulls(service_price_id,medicine_id)=1));
CREATE TABLE hospitalflow.payment_reversals(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),payment_id text NOT NULL REFERENCES hospitalflow.payments(id),amount numeric(14,2) NOT NULL CHECK(amount>0),
 reason text NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 500),approved_by text NOT NULL REFERENCES hospitalflow.users(id),at timestamptz NOT NULL DEFAULT now());
CREATE INDEX payment_reversals_payment_idx ON hospitalflow.payment_reversals(payment_id);
CREATE TABLE hospitalflow.clinical_orders(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),encounter_id uuid NOT NULL REFERENCES hospitalflow.encounters(id),service_id uuid NOT NULL REFERENCES hospitalflow.service_catalog(id),
 ordered_by text NOT NULL REFERENCES hospitalflow.users(id),status text NOT NULL CHECK(status IN ('Requested','In progress','Completed','Cancelled')),created_at timestamptz NOT NULL DEFAULT now(),completed_at timestamptz,
 CHECK((status='Completed')=(completed_at IS NOT NULL)));
CREATE TABLE hospitalflow.discharge_tasks(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),admission_id text NOT NULL REFERENCES hospitalflow.admissions(id),code text NOT NULL,
 required boolean NOT NULL DEFAULT true,completed_by text REFERENCES hospitalflow.users(id),completed_at timestamptz,UNIQUE(admission_id,code),CHECK((completed_by IS NULL)=(completed_at IS NULL)));
CREATE TABLE hospitalflow.follow_ups(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),admission_id text REFERENCES hospitalflow.admissions(id),
 due_at timestamptz NOT NULL,doctor_id text REFERENCES hospitalflow.doctors(id),instructions text NOT NULL,status text NOT NULL CHECK(status IN ('Pending','Booked','Completed','Cancelled')),appointment_id text REFERENCES hospitalflow.appointments(id),created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX follow_ups_pending_idx ON hospitalflow.follow_ups(due_at) WHERE status='Pending';
CREATE TABLE hospitalflow.suppliers(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),code text NOT NULL UNIQUE,name text NOT NULL,contact_email text,contact_phone text,active boolean NOT NULL DEFAULT true);
CREATE TABLE hospitalflow.purchase_orders(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),supplier_id uuid NOT NULL REFERENCES hospitalflow.suppliers(id),number text NOT NULL UNIQUE,
 status hospitalflow.purchase_status NOT NULL DEFAULT 'Draft',created_by text NOT NULL REFERENCES hospitalflow.users(id),approved_by text REFERENCES hospitalflow.users(id),created_at timestamptz NOT NULL DEFAULT now(),CHECK(status IN ('Draft','Cancelled') OR approved_by IS NOT NULL));
CREATE TABLE hospitalflow.purchase_order_lines(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),purchase_order_id uuid NOT NULL REFERENCES hospitalflow.purchase_orders(id),medicine_id text NOT NULL REFERENCES hospitalflow.medicine_batches(id),
 quantity integer NOT NULL CHECK(quantity>0),unit_cost numeric(14,2) NOT NULL CHECK(unit_cost>0),UNIQUE(purchase_order_id,medicine_id));
CREATE TABLE hospitalflow.goods_receipts(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),purchase_order_id uuid NOT NULL REFERENCES hospitalflow.purchase_orders(id),reference text NOT NULL,
 received_by text NOT NULL REFERENCES hospitalflow.users(id),received_at timestamptz NOT NULL DEFAULT now(),UNIQUE(purchase_order_id,reference));
CREATE TABLE hospitalflow.goods_receipt_lines(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),receipt_id uuid NOT NULL REFERENCES hospitalflow.goods_receipts(id),purchase_order_line_id uuid NOT NULL REFERENCES hospitalflow.purchase_order_lines(id),
 quantity integer NOT NULL CHECK(quantity>0),movement_id text NOT NULL UNIQUE REFERENCES hospitalflow.stock_movements(id),UNIQUE(receipt_id,purchase_order_line_id));
CREATE TABLE hospitalflow.medicine_batch_holds(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),medicine_id text NOT NULL REFERENCES hospitalflow.medicine_batches(id),reason text NOT NULL,
 held_by text NOT NULL REFERENCES hospitalflow.users(id),held_at timestamptz NOT NULL DEFAULT now(),released_by text REFERENCES hospitalflow.users(id),released_at timestamptz,
 CHECK((released_by IS NULL)=(released_at IS NULL)),CHECK(released_at IS NULL OR released_at>=held_at));
CREATE UNIQUE INDEX batch_active_hold_unique ON hospitalflow.medicine_batch_holds(medicine_id) WHERE released_at IS NULL;
CREATE TABLE hospitalflow.stock_reservations(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),prescription_id text NOT NULL UNIQUE REFERENCES hospitalflow.prescriptions(id),medicine_id text NOT NULL REFERENCES hospitalflow.medicine_batches(id),
 quantity integer NOT NULL CHECK(quantity>0),status text NOT NULL CHECK(status IN ('Active','Consumed','Released')),created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX stock_reservations_active_idx ON hospitalflow.stock_reservations(medicine_id) WHERE status='Active';
CREATE TABLE hospitalflow.prescription_dispensations(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),prescription_id text NOT NULL UNIQUE REFERENCES hospitalflow.prescriptions(id),
 movement_id text NOT NULL UNIQUE REFERENCES hospitalflow.stock_movements(id),bill_id text NOT NULL UNIQUE REFERENCES hospitalflow.bills(id),dispensed_by text NOT NULL REFERENCES hospitalflow.users(id),at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.notification_acknowledgements(notification_id text NOT NULL REFERENCES hospitalflow.notifications(id),user_id text NOT NULL REFERENCES hospitalflow.users(id),reason text NOT NULL,at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(notification_id,user_id));
CREATE TABLE hospitalflow.integration_outbox(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_type text NOT NULL,aggregate_type text NOT NULL,aggregate_id text NOT NULL,
 payload jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(payload)='object'),created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.outbox_delivery(event_id uuid PRIMARY KEY REFERENCES hospitalflow.integration_outbox(id),status text NOT NULL DEFAULT 'Pending' CHECK(status IN ('Pending','Leased','Delivered','Dead letter')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),next_attempt_at timestamptz NOT NULL DEFAULT now(),lease_token uuid,lease_until timestamptz,last_error_code text,delivered_at timestamptz,
 CHECK((status='Leased')=(lease_token IS NOT NULL AND lease_until IS NOT NULL)),CHECK((status='Delivered')=(delivered_at IS NOT NULL)));
CREATE INDEX outbox_delivery_due_idx ON hospitalflow.outbox_delivery(next_attempt_at) WHERE status='Pending';
CREATE TABLE hf_ops.job_definitions(name text PRIMARY KEY,task text NOT NULL UNIQUE CHECK(task IN ('refresh_alerts','session_cleanup','integrity_check','daily_snapshot','refresh_reports','recover_outbox_leases','backup_monitor','analyze_tables')),
 interval_seconds integer NOT NULL CHECK(interval_seconds BETWEEN 60 AND 604800),enabled boolean NOT NULL DEFAULT true,next_run_at timestamptz NOT NULL DEFAULT now(),last_started_at timestamptz,last_finished_at timestamptz,last_status text,failures integer NOT NULL DEFAULT 0 CHECK(failures>=0));
CREATE TABLE hf_ops.job_runs(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),job_name text NOT NULL REFERENCES hf_ops.job_definitions(name),started_at timestamptz NOT NULL DEFAULT now(),finished_at timestamptz,
 status text NOT NULL CHECK(status IN ('Running','Succeeded','Failed','Skipped')),error_code text,CHECK(finished_at IS NULL OR finished_at>=started_at));
CREATE INDEX job_runs_recent_idx ON hf_ops.job_runs(started_at DESC);
CREATE TABLE hf_ops.integrity_findings(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),run_id uuid NOT NULL REFERENCES hf_ops.job_runs(id),check_name text NOT NULL,violations bigint NOT NULL CHECK(violations>=0),checked_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hf_ops.daily_snapshots(day date NOT NULL,ward text NOT NULL REFERENCES hospitalflow.wards(name),staffed_beds bigint NOT NULL,occupied_beds bigint NOT NULL,available_beds bigint NOT NULL,captured_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(day,ward));
CREATE TABLE hf_ops.backup_runs(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),started_at timestamptz NOT NULL DEFAULT now(),completed_at timestamptz,status text NOT NULL CHECK(status IN ('Running','Succeeded','Failed')),
 file_reference text,bytes bigint CHECK(bytes>0),sha256 text CHECK(sha256~'^[A-Fa-f0-9]{64}$'),error_code text,CHECK(completed_at IS NULL OR completed_at>=started_at));
CREATE TABLE hf_ops.restore_drills(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),backup_id uuid NOT NULL REFERENCES hf_ops.backup_runs(id),performed_at timestamptz NOT NULL DEFAULT now(),
 outcome text NOT NULL CHECK(outcome IN ('Passed','Failed')),evidence_reference text NOT NULL,recovery_seconds integer CHECK(recovery_seconds>=0));
INSERT INTO hf_ops.job_definitions(name,task,interval_seconds) VALUES
 ('operational-alerts','refresh_alerts',60),('expired-sessions','session_cleanup',3600),('integrity-monitor','integrity_check',900),('ward-daily-snapshot','daily_snapshot',3600),
 ('report-cache','refresh_reports',900),('outbox-lease-recovery','recover_outbox_leases',60),('backup-freshness','backup_monitor',86400),('planner-statistics','analyze_tables',86400);
CREATE TABLE hf_ops.retention_policies(entity text PRIMARY KEY,retain_days integer CHECK(retain_days>=30),purge_enabled boolean NOT NULL DEFAULT false,approved_reference text,
 CHECK(NOT purge_enabled OR approved_reference IS NOT NULL));
INSERT INTO hf_ops.retention_policies(entity) VALUES('clinical_records'),('financial_records'),('activity_log'),('row_history'),('job_runs'),('idempotency_keys');
COMMENT ON TABLE hf_ops.retention_policies IS 'No clinical, financial, audit or retry history is purged automatically. Retention requires institutional policy and a separately reviewed archive/purge workflow.';
REVOKE ALL ON ALL TABLES IN SCHEMA hf_ops FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA hf_ops FROM PUBLIC;
CREATE TABLE hospitalflow.prescription_authors(prescription_id text PRIMARY KEY REFERENCES hospitalflow.prescriptions(id),created_by text NOT NULL REFERENCES hospitalflow.users(id),created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.admission_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),admission_id text NOT NULL REFERENCES hospitalflow.admissions(id),
 kind text NOT NULL CHECK(kind IN ('Admission','Transfer','Discharge')),from_bed text REFERENCES hospitalflow.beds(id),to_bed text REFERENCES hospitalflow.beds(id),
 reason text NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 4000),actor_id text NOT NULL REFERENCES hospitalflow.users(id),at timestamptz NOT NULL DEFAULT now());
CREATE INDEX admission_events_admission_idx ON hospitalflow.admission_events(admission_id,at);
