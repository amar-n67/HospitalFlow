-- HospitalFlow schema-only installer. Generated; edit numbered migrations, then regenerate.
-- Run only in a NEW EMPTY PostgreSQL 17 database as its migration owner.
-- This does not contain passwords, patient data, or application bootstrap accounts.
-- After installing, run the application's --migrate bootstrap job to create its random
-- request-fingerprint key and initial administrator, then apply grant_runtime.sql.
BEGIN;
DO $$ BEGIN IF to_regclass('hospitalflow.users') IS NOT NULL THEN RAISE EXCEPTION 'Refusing to install over an existing HospitalFlow database. Apply numbered migrations instead.';END IF;END $$;
CREATE SCHEMA IF NOT EXISTS hospitalflow;
CREATE TABLE hospitalflow.schema_versions(version text PRIMARY KEY,checksum text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now());

-- 001_relational.sql
CREATE SCHEMA IF NOT EXISTS hospitalflow;
SET search_path TO hospitalflow, public;
CREATE TABLE roles(name text PRIMARY KEY);
INSERT INTO roles VALUES ('Administrator'),('Reception'),('Doctor'),('Nurse'),('Pharmacist'),('Billing');
CREATE TABLE departments(name text PRIMARY KEY CHECK(length(name) BETWEEN 1 AND 80));
CREATE TABLE wards(name text PRIMARY KEY CHECK(length(name) BETWEEN 1 AND 100));
CREATE TABLE users(
 id text PRIMARY KEY, name text NOT NULL CHECK(length(name) BETWEEN 1 AND 100),
 email text NOT NULL, role text NOT NULL REFERENCES roles(name), password_hash text NOT NULL,
 active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now());
CREATE UNIQUE INDEX users_email_unique ON users(lower(email));
CREATE TABLE patients(
 id text PRIMARY KEY, name text NOT NULL CHECK(length(name) BETWEEN 1 AND 100),
 dob date NOT NULL CHECK(dob >= DATE '1900-01-01'),
 sex text NOT NULL CHECK(sex IN ('Male','Female','Other','Prefer not to say')),
 phone text NOT NULL CHECK(length(phone) BETWEEN 7 AND 20), created timestamptz NOT NULL);
CREATE INDEX patients_name_idx ON patients(lower(name));
CREATE INDEX patients_phone_dob_idx ON patients(phone,dob);
CREATE TABLE doctors(id text PRIMARY KEY, name text NOT NULL, department text NOT NULL REFERENCES departments(name),
 start time NOT NULL, "end" time NOT NULL, CHECK(start < "end"));
CREATE TABLE appointments(id text PRIMARY KEY, patient_id text NOT NULL REFERENCES patients(id),
 doctor_id text NOT NULL REFERENCES doctors(id), at timestamptz NOT NULL, type text NOT NULL,
 status text NOT NULL CHECK(status IN ('Scheduled','Checked in','In consultation','Completed','Cancelled','No show')),
 checked_in timestamptz);
CREATE INDEX appointments_at_idx ON appointments(at);
CREATE INDEX appointments_patient_idx ON appointments(patient_id,at);
CREATE INDEX appointments_doctor_idx ON appointments(doctor_id,at);
-- No extension privileges required. A transaction-wide lock also protects interval checks in the trigger below.
CREATE TABLE beds(id text PRIMARY KEY, ward text NOT NULL REFERENCES wards(name), category text NOT NULL,
 status text NOT NULL CHECK(status IN ('Available','Occupied','Cleaning','Maintenance')));
CREATE INDEX beds_ward_status_idx ON beds(ward,status);
CREATE TABLE admissions(id text PRIMARY KEY, patient_id text NOT NULL REFERENCES patients(id),
 bed_id text NOT NULL REFERENCES beds(id), reason text NOT NULL, at timestamptz NOT NULL,
 status text NOT NULL CHECK(status IN ('Admitted','Discharged')), discharged timestamptz,
 CHECK((status='Admitted' AND discharged IS NULL) OR (status='Discharged' AND discharged IS NOT NULL AND discharged >= at)));
CREATE UNIQUE INDEX admissions_active_bed_unique ON admissions(bed_id) WHERE status='Admitted';
CREATE UNIQUE INDEX admissions_active_patient_unique ON admissions(patient_id) WHERE status='Admitted';
CREATE INDEX admissions_patient_idx ON admissions(patient_id,at);
CREATE TABLE bed_assignments(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 admission_id text NOT NULL REFERENCES admissions(id), bed_id text NOT NULL REFERENCES beds(id),
 from_time timestamptz NOT NULL, to_time timestamptz, CHECK(to_time IS NULL OR to_time>=from_time));
CREATE UNIQUE INDEX assignments_active_bed_unique ON bed_assignments(bed_id) WHERE to_time IS NULL;
CREATE UNIQUE INDEX assignments_active_admission_unique ON bed_assignments(admission_id) WHERE to_time IS NULL;
CREATE TABLE medicine_batches(id text PRIMARY KEY, name text NOT NULL, batch text NOT NULL, expiry date NOT NULL,
 quantity integer NOT NULL CHECK(quantity>=0), reorder integer NOT NULL CHECK(reorder>0),
 price numeric(14,2) NOT NULL CHECK(price>0), UNIQUE(name,batch));
CREATE INDEX medicine_expiry_idx ON medicine_batches(expiry);
CREATE TABLE prescriptions(id text PRIMARY KEY, patient_id text NOT NULL REFERENCES patients(id),
 medicine_id text NOT NULL REFERENCES medicine_batches(id), quantity integer NOT NULL CHECK(quantity>0),
 instructions text NOT NULL, status text NOT NULL CHECK(status IN ('Pending','Dispensed')));
CREATE INDEX prescriptions_patient_status_idx ON prescriptions(patient_id,status);
CREATE TABLE stock_movements(id text PRIMARY KEY, medicine_id text NOT NULL REFERENCES medicine_batches(id),
 quantity integer NOT NULL CHECK(quantity<>0), reason text NOT NULL, at timestamptz NOT NULL);
CREATE INDEX stock_movements_medicine_idx ON stock_movements(medicine_id,at);
CREATE TABLE bills(id text PRIMARY KEY, patient_id text NOT NULL REFERENCES patients(id), created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX bills_patient_idx ON bills(patient_id);
CREATE TABLE bill_lines(id text PRIMARY KEY, bill_id text NOT NULL REFERENCES bills(id), description text NOT NULL,
 amount numeric(14,2) NOT NULL CHECK(amount<>0), created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX bill_lines_bill_idx ON bill_lines(bill_id);
CREATE TABLE payments(id text PRIMARY KEY, bill_id text NOT NULL REFERENCES bills(id), amount numeric(14,2) NOT NULL CHECK(amount>0),
 method text NOT NULL CHECK(method IN ('Cash','Card','UPI','Bank transfer')), at timestamptz NOT NULL);
CREATE INDEX payments_bill_idx ON payments(bill_id,at);
CREATE TABLE notes(id text PRIMARY KEY, patient_id text NOT NULL REFERENCES patients(id), text text NOT NULL CHECK(length(text)<=4000),
 kind text NOT NULL, at timestamptz NOT NULL);
CREATE INDEX notes_patient_idx ON notes(patient_id,at);
CREATE TABLE activity_log(id text PRIMARY KEY, actor text NOT NULL, action text NOT NULL, reference text NOT NULL,
 at timestamptz NOT NULL DEFAULT now(), outcome text NOT NULL DEFAULT 'Success', actor_id text,
 correlation_id text, source_ip text, method text, status_code integer);
CREATE INDEX activity_log_at_idx ON activity_log(at DESC);
CREATE INDEX activity_log_actor_idx ON activity_log(actor_id,at DESC);
CREATE INDEX activity_log_correlation_idx ON activity_log(correlation_id);
CREATE TABLE row_history(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, table_name text NOT NULL,
 record_id text NOT NULL, operation text NOT NULL, changed_columns text[] NOT NULL,
 actor_id text, correlation_id text, occurred_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX row_history_record_idx ON row_history(table_name,record_id,occurred_at DESC);
CREATE TABLE auth_attempts(key_hash text PRIMARY KEY, failures integer NOT NULL CHECK(failures>=0), blocked_until timestamptz NOT NULL);
CREATE TABLE sessions(id text PRIMARY KEY, user_id text NOT NULL REFERENCES users(id), ticket bytea NOT NULL,
 expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX sessions_expiry_idx ON sessions(expires_at);
CREATE TABLE data_protection_keys(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 friendly_name text NOT NULL, xml text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE idempotency_keys(user_id text NOT NULL REFERENCES users(id), key uuid NOT NULL, action text NOT NULL,
 request_hash text NOT NULL, reference text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,key));
CREATE TABLE notifications(id text PRIMARY KEY, rule text NOT NULL, reference text NOT NULL,
 title text NOT NULL, message text NOT NULL, target text NOT NULL,
 opened_at timestamptz NOT NULL DEFAULT now(), resolved_at timestamptz);
CREATE UNIQUE INDEX notifications_open_unique ON notifications(rule,reference) WHERE resolved_at IS NULL;
CREATE TABLE system_settings(key text PRIMARY KEY, value text NOT NULL);
INSERT INTO system_settings VALUES ('hospital_timezone','Asia/Kolkata'),('currency','INR');

CREATE VIEW invoice_balances AS
 SELECT b.id,b.patient_id,COALESCE(l.total,0)::numeric(14,2) AS total,
 COALESCE(p.paid,0)::numeric(14,2) AS paid,(COALESCE(l.total,0)-COALESCE(p.paid,0))::numeric(14,2) AS balance
 FROM bills b LEFT JOIN (SELECT bill_id,sum(amount) total FROM bill_lines GROUP BY bill_id) l ON l.bill_id=b.id
 LEFT JOIN (SELECT bill_id,sum(amount) paid FROM payments GROUP BY bill_id) p ON p.bill_id=b.id;
CREATE VIEW bed_occupancy AS SELECT ward,count(*) AS staffed_beds,
 count(*) FILTER(WHERE status='Occupied') AS occupied_beds,
 count(*) FILTER(WHERE status='Available') AS available_beds,
 round(100.0*count(*) FILTER(WHERE status='Occupied')/NULLIF(count(*),0),2) AS occupancy_percent FROM beds GROUP BY ward;
CREATE VIEW stock_alerts AS SELECT id,name,batch,quantity,reorder,expiry,
 quantity<=reorder AS low_stock, expiry<=current_date AS expired, expiry<=current_date+30 AS near_expiry FROM medicine_batches;

CREATE FUNCTION prevent_ledger_changes() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN RAISE EXCEPTION 'Ledger records are append-only' USING ERRCODE='23514'; END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['activity_log','row_history','stock_movements','bill_lines','payments'] LOOP
 EXECUTE format('CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_ledger_changes()',t);
 END LOOP; END $$;

CREATE FUNCTION record_row_history() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=hospitalflow,pg_temp AS $$
 DECLARE doc jsonb; cols text[]; BEGIN
 doc:=to_jsonb(NEW);
 IF TG_OP='UPDATE' THEN
  SELECT array_agg(key ORDER BY key) INTO cols FROM jsonb_each(doc) WHERE value IS DISTINCT FROM to_jsonb(OLD)->key;
 ELSE SELECT array_agg(key ORDER BY key) INTO cols FROM jsonb_each(doc); END IF;
 IF cols IS NULL THEN RETURN NEW; END IF;
 INSERT INTO row_history(table_name,record_id,operation,changed_columns,actor_id,correlation_id)
 VALUES(TG_TABLE_NAME,doc->>'id',TG_OP,cols,nullif(current_setting('hospitalflow.actor_id',true),''),nullif(current_setting('hospitalflow.correlation_id',true),''));
 RETURN NEW; END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['users','patients','doctors','appointments','beds','admissions','medicine_batches','prescriptions','stock_movements','bills','bill_lines','payments','notes'] LOOP
 EXECUTE format('CREATE TRIGGER record_history AFTER INSERT OR UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION record_row_history()',t);
 END LOOP; END $$;

CREATE FUNCTION maintain_bed_history() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=hospitalflow,pg_temp AS $$
 BEGIN
 IF TG_OP='UPDATE' AND (OLD.bed_id IS DISTINCT FROM NEW.bed_id OR NEW.status='Discharged') THEN
 UPDATE bed_assignments SET to_time=COALESCE(NEW.discharged,now()) WHERE admission_id=NEW.id AND to_time IS NULL;
 END IF;
 IF NEW.status='Admitted' AND (TG_OP='INSERT' OR OLD.bed_id IS DISTINCT FROM NEW.bed_id) THEN
 INSERT INTO bed_assignments(admission_id,bed_id,from_time) VALUES(NEW.id,NEW.bed_id,CASE WHEN TG_OP='INSERT' THEN NEW.at ELSE now() END);
 END IF; RETURN NEW; END $$;
CREATE TRIGGER bed_history AFTER INSERT OR UPDATE ON admissions FOR EACH ROW EXECUTE FUNCTION maintain_bed_history();

CREATE FUNCTION validate_appointment_overlap() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN
 PERFORM pg_advisory_xact_lock(74192301);
 IF NEW.status NOT IN ('Cancelled','No show') AND EXISTS(SELECT 1 FROM hospitalflow.appointments a
 WHERE a.id<>NEW.id AND a.status NOT IN ('Cancelled','No show') AND (a.doctor_id=NEW.doctor_id OR a.patient_id=NEW.patient_id)
 AND a.at<NEW.at+interval '30 minutes' AND a.at+interval '30 minutes'>NEW.at) THEN
 RAISE EXCEPTION 'Appointment overlaps an existing visit' USING ERRCODE='23505'; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER appointment_overlap BEFORE INSERT OR UPDATE ON appointments FOR EACH ROW EXECUTE FUNCTION validate_appointment_overlap();

CREATE FUNCTION validate_invoice_balance() RETURNS trigger LANGUAGE plpgsql AS $$
 DECLARE target text; BEGIN
 PERFORM pg_advisory_xact_lock(74192301);
 target:=NEW.bill_id;
 IF EXISTS(SELECT 1 FROM hospitalflow.invoice_balances WHERE id=target AND balance<0) THEN
 RAISE EXCEPTION 'Payment or adjustment exceeds invoice balance' USING ERRCODE='23514'; END IF;
 RETURN NEW; END $$;
CREATE CONSTRAINT TRIGGER payment_balance AFTER INSERT ON payments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_invoice_balance();
CREATE CONSTRAINT TRIGGER line_balance AFTER INSERT ON bill_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_invoice_balance();

CREATE FUNCTION validate_occupancy() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN
 IF EXISTS(SELECT 1 FROM hospitalflow.beds b WHERE (b.status='Occupied') IS DISTINCT FROM EXISTS(SELECT 1 FROM hospitalflow.admissions a WHERE a.bed_id=b.id AND a.status='Admitted')) THEN
 RAISE EXCEPTION 'Bed status and active admission disagree' USING ERRCODE='23514'; END IF;
 RETURN NULL; END $$;
CREATE CONSTRAINT TRIGGER bed_consistency AFTER INSERT OR UPDATE ON beds DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_occupancy();
CREATE CONSTRAINT TRIGGER admission_consistency AFTER INSERT OR UPDATE ON admissions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_occupancy();
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hospitalflow FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.001_relational.sql','0245E80A8A058DF24065407F511AA50012F4C6F3C9AA54E2511A439D9D1EC884');

-- 002_workflow_integrity.sql
SET search_path TO hospitalflow,public;
CREATE FUNCTION validate_stock_balance() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN
 IF EXISTS(SELECT 1 FROM hospitalflow.medicine_batches m WHERE m.quantity<>(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_movements WHERE medicine_id=m.id)) THEN
 RAISE EXCEPTION 'Stock balance must match its movement ledger' USING ERRCODE='23514';END IF;
 RETURN NULL;END $$;
CREATE CONSTRAINT TRIGGER stock_batch_balance AFTER INSERT OR UPDATE ON medicine_batches DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_stock_balance();
CREATE CONSTRAINT TRIGGER stock_movement_balance AFTER INSERT ON stock_movements DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_stock_balance();
CREATE FUNCTION validate_dispense_expiry() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN
 IF NEW.status='Dispensed' AND (TG_OP='INSERT' OR OLD.status<>'Dispensed') AND EXISTS(SELECT 1 FROM hospitalflow.medicine_batches WHERE id=NEW.medicine_id AND expiry<=current_date) THEN
 RAISE EXCEPTION 'Expired medicine cannot be dispensed' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER dispense_expiry BEFORE INSERT OR UPDATE ON prescriptions FOR EACH ROW EXECUTE FUNCTION validate_dispense_expiry();
CREATE FUNCTION validate_discharge_readiness() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN
 IF NEW.status='Discharged' AND (TG_OP='INSERT' OR OLD.status<>'Discharged') AND
 (EXISTS(SELECT 1 FROM hospitalflow.invoice_balances WHERE patient_id=NEW.patient_id AND balance>0) OR
 EXISTS(SELECT 1 FROM hospitalflow.prescriptions WHERE patient_id=NEW.patient_id AND status='Pending')) THEN
 RAISE EXCEPTION 'Discharge requires settled invoices and completed prescriptions' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE CONSTRAINT TRIGGER discharge_readiness AFTER INSERT OR UPDATE ON admissions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_discharge_readiness();
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hospitalflow FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.002_workflow_integrity.sql','1D687BE41C84221C4204E47E9A987B5494731B4DC577752421535764E81F2919');

-- 003_request_fingerprints.sql
CREATE TABLE hospitalflow.idempotency_hash_keys(
 id smallint PRIMARY KEY CHECK(id=1), secret bytea NOT NULL CHECK(octet_length(secret)=32));

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.003_request_fingerprints.sql','0BBB013558AAEEFDF39AADBF39730BBC0F310A51F1A38372E3047679F767E3FB');

-- 004_enterprise_foundation.sql
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

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.004_enterprise_foundation.sql','F59FA70DA02F94436A3DDB96F6FB49127CBC59F1E8AF914ECF944F4F52830223');

-- 005_database_api.sql
CREATE FUNCTION hf_security.actor_id() RETURNS text LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('hospitalflow.actor_id',true),'') $$;
CREATE FUNCTION hf_security.require_actor(p_roles text[]) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE u hospitalflow.users%ROWTYPE;BEGIN
 SELECT * INTO u FROM hospitalflow.users WHERE id=nullif(current_setting('hospitalflow.actor_id',true),'') AND active;
 IF NOT FOUND OR (u.role<>'Administrator' AND NOT(u.role=ANY(p_roles))) THEN RAISE EXCEPTION 'Active authorized application identity required' USING ERRCODE='42501';END IF;
 RETURN u.id;END $$;
CREATE FUNCTION hf_security.can_access_patient(p_patient text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM hospitalflow.users u WHERE u.id=nullif(current_setting('hospitalflow.actor_id',true),'') AND u.active AND
 (u.role='Administrator' OR EXISTS(SELECT 1 FROM hospitalflow.patient_access_grants g WHERE g.user_id=u.id AND g.patient_id=p_patient AND g.expires_at>now()) OR
 EXISTS(SELECT 1 FROM hospitalflow.admissions a JOIN hospitalflow.beds b ON b.id=a.bed_id JOIN hospitalflow.wards w ON w.name=b.ward JOIN hospitalflow.user_departments d ON d.department=w.department WHERE a.patient_id=p_patient AND a.status='Admitted' AND d.user_id=u.id))) $$;
CREATE FUNCTION hf_security.audit(p_action text,p_reference text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE v_actor text;v_name text;BEGIN
 v_actor:=nullif(current_setting('hospitalflow.actor_id',true),'');SELECT name INTO v_name FROM hospitalflow.users WHERE id=v_actor AND active;
 IF v_name IS NULL THEN RAISE EXCEPTION 'Audit requires an active actor' USING ERRCODE='42501';END IF;
 INSERT INTO hospitalflow.activity_log(id,actor,action,reference,at,actor_id,correlation_id,method)
 VALUES(gen_random_uuid()::text,v_name,p_action,p_reference,clock_timestamp(),v_actor,nullif(current_setting('hospitalflow.correlation_id',true),''),'SQL');END $$;
CREATE FUNCTION hf_api.new_id(p_prefix text) RETURNS text LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF p_prefix!~'^[A-Z]{2,8}$' THEN RAISE EXCEPTION 'Invalid identifier prefix' USING ERRCODE='23514';END IF;
 RETURN p_prefix||'-'||nextval('hospitalflow.document_number')::text;END $$;
CREATE FUNCTION hf_api.required_text(p_body jsonb,p_key text,p_max integer DEFAULT 500) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text;BEGIN v:=trim(p_body->>p_key);IF jsonb_typeof(p_body->p_key)<>'string' OR v IS NULL OR length(v) NOT BETWEEN 1 AND p_max THEN
 RAISE EXCEPTION 'Required text field is invalid: %',p_key USING ERRCODE='23514';END IF;RETURN v;END $$;
CREATE FUNCTION hf_api.positive_number(p_body jsonb,p_key text,p_integer boolean DEFAULT false) RETURNS numeric LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE n numeric;BEGIN IF jsonb_typeof(p_body->p_key) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Numeric field required: %',p_key USING ERRCODE='23514';END IF;
 n:=(p_body->>p_key)::numeric;IF n<=0 OR n>10000000 OR (p_integer AND(n<>trunc(n) OR n>100000)) OR (NOT p_integer AND n<>round(n,2)) THEN
 RAISE EXCEPTION 'Positive value out of range: %',p_key USING ERRCODE='23514';END IF;RETURN n;END $$;
CREATE FUNCTION hf_api.hospital_today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE (SELECT value FROM hospitalflow.system_settings WHERE key='hospital_timezone'))::date $$;

CREATE PROCEDURE hf_api.save_patient(INOUT p_id text,IN p_name text,IN p_dob date,IN p_sex text,IN p_phone text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY['Reception']);PERFORM pg_advisory_xact_lock(74192301);
 IF length(trim(p_name)) NOT BETWEEN 1 AND 100 OR p_dob IS NULL OR p_dob<date '1900-01-01' OR p_dob>hf_api.hospital_today() OR p_phone!~'^\+?[0-9 ()-]{7,20}$' OR p_sex NOT IN ('Male','Female','Other','Prefer not to say') THEN RAISE EXCEPTION 'Invalid patient details' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.patients WHERE id IS DISTINCT FROM p_id AND dob=p_dob AND(lower(name)=lower(trim(p_name)) OR phone=p_phone)) THEN RAISE EXCEPTION 'Possible duplicate patient; review existing identity' USING ERRCODE='23505';END IF;
 IF p_id IS NULL THEN p_id:=hf_api.new_id('HF');INSERT INTO hospitalflow.patients VALUES(p_id,trim(p_name),p_dob,p_sex,p_phone,now());
 ELSE UPDATE hospitalflow.patients SET name=trim(p_name),dob=p_dob,sex=p_sex,phone=p_phone WHERE id=p_id;IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found' USING ERRCODE='23503';END IF;END IF;
 PERFORM hf_security.audit('procedure:save-patient',p_id);END $$;
CREATE PROCEDURE hf_api.book_appointment(INOUT p_id text,IN p_patient text,IN p_doctor text,IN p_at timestamptz,IN p_type text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY['Reception']);PERFORM pg_advisory_xact_lock(74192301);
 IF p_at<now() OR p_at IS NULL OR length(trim(p_type)) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'A future appointment and visit type are required' USING ERRCODE='23514';END IF;
 p_id:=hf_api.new_id('APT');INSERT INTO hospitalflow.appointments(id,patient_id,doctor_id,at,type,status) VALUES(p_id,p_patient,p_doctor,p_at,p_type,'Scheduled');
 PERFORM hf_security.audit('procedure:book-appointment',p_id);END $$;
CREATE PROCEDURE hf_api.set_appointment_status(IN p_id text,IN p_status text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE a hospitalflow.appointments%ROWTYPE;BEGIN PERFORM hf_security.require_actor(ARRAY['Reception']);PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO STRICT a FROM hospitalflow.appointments WHERE id=p_id FOR UPDATE;
 IF NOT((a.status='Scheduled' AND p_status IN ('Checked in','Cancelled','No show')) OR(a.status='Checked in' AND p_status IN ('In consultation','Cancelled')) OR(a.status='In consultation' AND p_status='Completed')) OR(p_status='No show' AND a.at>now()) THEN RAISE EXCEPTION 'Invalid appointment status transition' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.appointments SET status=p_status,checked_in=CASE WHEN p_status='Checked in' THEN now() ELSE checked_in END WHERE id=p_id;
 PERFORM hf_security.audit('procedure:appointment-status',p_id);END $$;
CREATE PROCEDURE hf_api.admit_patient(INOUT p_id text,IN p_patient text,IN p_bed text,IN p_reason text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY['Nurse']);PERFORM pg_advisory_xact_lock(74192301);
 IF length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Admission reason required' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.beds SET status='Occupied' WHERE id=p_bed AND status='Available' AND EXISTS(SELECT 1 FROM hospitalflow.wards w WHERE w.name=ward AND w.active);IF NOT FOUND THEN RAISE EXCEPTION 'Bed unavailable' USING ERRCODE='23514';END IF;
 p_id:=hf_api.new_id('ADM');INSERT INTO hospitalflow.admissions(id,patient_id,bed_id,reason,at,status) VALUES(p_id,p_patient,p_bed,p_reason,now(),'Admitted');
 INSERT INTO hospitalflow.admission_events(admission_id,kind,to_bed,reason,actor_id) VALUES(p_id,'Admission',p_bed,p_reason,hf_security.actor_id());
 PERFORM hf_security.audit('procedure:admit-patient',p_id);END $$;
CREATE PROCEDURE hf_api.transfer_patient(IN p_id text,IN p_bed text,IN p_reason text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE a hospitalflow.admissions%ROWTYPE;BEGIN PERFORM hf_security.require_actor(ARRAY['Nurse']);PERFORM pg_advisory_xact_lock(74192301);
 IF length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Transfer reason required' USING ERRCODE='23514';END IF;
 SELECT * INTO STRICT a FROM hospitalflow.admissions WHERE id=p_id AND status='Admitted' FOR UPDATE;
 UPDATE hospitalflow.beds SET status='Occupied' WHERE id=p_bed AND status='Available' AND EXISTS(SELECT 1 FROM hospitalflow.wards w WHERE w.name=ward AND w.active);IF NOT FOUND THEN RAISE EXCEPTION 'Destination bed unavailable' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.beds SET status='Cleaning' WHERE id=a.bed_id;UPDATE hospitalflow.admissions SET bed_id=p_bed WHERE id=p_id;
 INSERT INTO hospitalflow.admission_events(admission_id,kind,from_bed,to_bed,reason,actor_id) VALUES(p_id,'Transfer',a.bed_id,p_bed,p_reason,hf_security.actor_id());
 PERFORM hf_security.audit('procedure:transfer-patient',p_id||':'||a.bed_id||'->'||p_bed);END $$;
CREATE PROCEDURE hf_api.discharge_patient(IN p_id text,IN p_summary text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE a hospitalflow.admissions%ROWTYPE;BEGIN PERFORM hf_security.require_actor(ARRAY['Nurse']);PERFORM pg_advisory_xact_lock(74192301);
 IF length(trim(p_summary)) NOT BETWEEN 1 AND 4000 THEN RAISE EXCEPTION 'Discharge summary required' USING ERRCODE='23514';END IF;
 SELECT * INTO STRICT a FROM hospitalflow.admissions WHERE id=p_id AND status='Admitted' FOR UPDATE;
 IF EXISTS(SELECT 1 FROM hospitalflow.invoice_balances WHERE patient_id=a.patient_id AND balance>0) OR EXISTS(SELECT 1 FROM hospitalflow.prescriptions WHERE patient_id=a.patient_id AND status='Pending') OR EXISTS(SELECT 1 FROM hospitalflow.discharge_tasks WHERE admission_id=p_id AND required AND completed_at IS NULL) THEN RAISE EXCEPTION 'Discharge prerequisites are incomplete' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.notes VALUES(hf_api.new_id('NOTE'),a.patient_id,p_summary,'Discharge summary',now());
 UPDATE hospitalflow.admissions SET status='Discharged',discharged=now() WHERE id=p_id;UPDATE hospitalflow.beds SET status='Cleaning' WHERE id=a.bed_id;
 INSERT INTO hospitalflow.admission_events(admission_id,kind,from_bed,reason,actor_id) VALUES(p_id,'Discharge',a.bed_id,p_summary,hf_security.actor_id());
 PERFORM hf_security.audit('procedure:discharge-patient',p_id);END $$;
CREATE PROCEDURE hf_api.receive_stock(INOUT p_movement text,IN p_medicine text,IN p_quantity integer,IN p_reason text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY['Pharmacist']);PERFORM pg_advisory_xact_lock(74192301);
 IF p_quantity IS NULL OR p_quantity NOT BETWEEN 1 AND 100000 OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid receipt quantity or reference' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.medicine_batches SET quantity=quantity+p_quantity WHERE id=p_medicine AND expiry>hf_api.hospital_today();IF NOT FOUND THEN RAISE EXCEPTION 'Medicine batch missing or expired' USING ERRCODE='23514';END IF;
 p_movement:=hf_api.new_id('MOV');INSERT INTO hospitalflow.stock_movements VALUES(p_movement,p_medicine,p_quantity,p_reason,now());
 PERFORM hf_security.audit('procedure:receive-stock',p_movement);END $$;
CREATE PROCEDURE hf_api.dispense_prescription(IN p_id text,INOUT p_bill text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE r hospitalflow.prescriptions%ROWTYPE;m hospitalflow.medicine_batches%ROWTYPE;v_movement text;v_line text;v_reserved bigint;BEGIN
 PERFORM hf_security.require_actor(ARRAY['Pharmacist']);PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO STRICT r FROM hospitalflow.prescriptions WHERE id=p_id AND status='Pending' FOR UPDATE;
 SELECT * INTO STRICT m FROM hospitalflow.medicine_batches WHERE id=r.medicine_id FOR UPDATE;
 SELECT COALESCE(sum(quantity),0) INTO v_reserved FROM hospitalflow.stock_reservations WHERE medicine_id=m.id AND status='Active' AND prescription_id<>r.id;
 IF m.expiry<=hf_api.hospital_today() OR m.quantity-v_reserved<r.quantity OR EXISTS(SELECT 1 FROM hospitalflow.medicine_batch_holds WHERE medicine_id=m.id AND released_at IS NULL) THEN RAISE EXCEPTION 'Medicine expired, held or insufficient available stock' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.medicine_batches SET quantity=quantity-r.quantity WHERE id=m.id;
 v_movement:=hf_api.new_id('MOV');INSERT INTO hospitalflow.stock_movements VALUES(v_movement,m.id,-r.quantity,r.id,now());
 p_bill:=hf_api.new_id('INV');v_line:=hf_api.new_id('LINE');INSERT INTO hospitalflow.bills(id,patient_id) VALUES(p_bill,r.patient_id);
 INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(v_line,p_bill,m.name||' × '||r.quantity,m.price*r.quantity);
 INSERT INTO hospitalflow.invoice_line_context(line_id,medicine_id,quantity,unit_price) VALUES(v_line,m.id,r.quantity,m.price);
 UPDATE hospitalflow.prescriptions SET status='Dispensed' WHERE id=r.id;UPDATE hospitalflow.stock_reservations SET status='Consumed' WHERE prescription_id=r.id AND status='Active';
 INSERT INTO hospitalflow.prescription_dispensations(prescription_id,movement_id,bill_id,dispensed_by) VALUES(r.id,v_movement,p_bill,hf_security.actor_id());
 PERFORM hf_security.audit('procedure:dispense-prescription',r.id);END $$;
CREATE PROCEDURE hf_api.create_bill(INOUT p_id text,IN p_patient text,IN p_description text,IN p_amount numeric) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY['Billing']);PERFORM pg_advisory_xact_lock(74192301);
 IF p_amount IS NULL OR p_amount<=0 OR p_amount>10000000 OR p_amount<>round(p_amount,2) OR length(trim(p_description)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid invoice charge' USING ERRCODE='23514';END IF;
 p_id:=hf_api.new_id('INV');INSERT INTO hospitalflow.bills(id,patient_id) VALUES(p_id,p_patient);INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(hf_api.new_id('LINE'),p_id,p_description,p_amount);
 PERFORM hf_security.audit('procedure:create-bill',p_id);END $$;
CREATE PROCEDURE hf_api.post_payment(IN p_bill text,IN p_amount numeric,IN p_method text,INOUT p_id text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE v_balance numeric;BEGIN PERFORM hf_security.require_actor(ARRAY['Billing']);PERFORM pg_advisory_xact_lock(74192301);
 PERFORM 1 FROM hospitalflow.bills WHERE id=p_bill FOR UPDATE;SELECT balance INTO STRICT v_balance FROM hospitalflow.invoice_balances WHERE id=p_bill;
 IF p_amount IS NULL OR p_amount<=0 OR p_amount>v_balance OR p_amount<>round(p_amount,2) OR p_method NOT IN ('Cash','Card','UPI','Bank transfer') THEN RAISE EXCEPTION 'Payment exceeds balance or is invalid' USING ERRCODE='23514';END IF;
 p_id:=hf_api.new_id('PAY');INSERT INTO hospitalflow.payments VALUES(p_id,p_bill,p_amount,p_method,now());PERFORM hf_security.audit('procedure:post-payment',p_id);END $$;
CREATE PROCEDURE hf_api.post_adjustment(IN p_bill text,IN p_amount numeric,IN p_reason text,INOUT p_id text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE v_balance numeric;BEGIN PERFORM hf_security.require_actor(ARRAY['Billing']);PERFORM pg_advisory_xact_lock(74192301);
 PERFORM 1 FROM hospitalflow.bills WHERE id=p_bill FOR UPDATE;SELECT balance INTO STRICT v_balance FROM hospitalflow.invoice_balances WHERE id=p_bill;
 IF p_amount IS NULL OR p_amount<=0 OR p_amount>v_balance OR p_amount<>round(p_amount,2) OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid credit adjustment' USING ERRCODE='23514';END IF;
 p_id:=hf_api.new_id('ADJ');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(p_id,p_bill,'Adjustment: '||p_reason,-p_amount);PERFORM hf_security.audit('procedure:post-adjustment',p_id);END $$;
CREATE PROCEDURE hf_api.reverse_payment(IN p_payment text,IN p_amount numeric,IN p_reason text,INOUT p_id uuid) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE v_amount numeric;v_reversed numeric;BEGIN PERFORM hf_security.require_actor(ARRAY[]::text[]);PERFORM pg_advisory_xact_lock(74192301);
 SELECT amount INTO STRICT v_amount FROM hospitalflow.payments WHERE id=p_payment;SELECT COALESCE(sum(amount),0) INTO v_reversed FROM hospitalflow.payment_reversals WHERE payment_id=p_payment;
 IF p_amount IS NULL OR p_amount<=0 OR p_amount<>round(p_amount,2) OR p_amount+v_reversed>v_amount OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid payment reversal' USING ERRCODE='23514';END IF;
 p_id:=gen_random_uuid();INSERT INTO hospitalflow.payment_reversals(id,payment_id,amount,reason,approved_by) VALUES(p_id,p_payment,p_amount,p_reason,hf_security.actor_id());PERFORM hf_security.audit('procedure:reverse-payment',p_id::text);END $$;
CREATE PROCEDURE hf_api.post_service_charge(IN p_bill text,IN p_service uuid,IN p_quantity numeric,INOUT p_id text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE v_price hospitalflow.service_prices%ROWTYPE;v_name text;BEGIN PERFORM hf_security.require_actor(ARRAY['Billing']);PERFORM pg_advisory_xact_lock(74192301);
 IF p_quantity IS NULL OR p_quantity<=0 OR p_quantity>100000 OR p_quantity<>round(p_quantity,3) THEN RAISE EXCEPTION 'Invalid service quantity' USING ERRCODE='23514';END IF;
 SELECT name INTO STRICT v_name FROM hospitalflow.service_catalog WHERE id=p_service AND active;
 SELECT * INTO STRICT v_price FROM hospitalflow.service_prices WHERE service_id=p_service AND effective_from<=now() AND(effective_to IS NULL OR effective_to>now()) ORDER BY effective_from DESC LIMIT 1;
 p_id:=hf_api.new_id('LINE');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(p_id,p_bill,v_name,round(v_price.amount*p_quantity,2));
 INSERT INTO hospitalflow.invoice_line_context(line_id,service_price_id,quantity,unit_price,currency) VALUES(p_id,v_price.id,p_quantity,v_price.amount,v_price.currency);PERFORM hf_security.audit('procedure:post-service-charge',p_id);END $$;
CREATE PROCEDURE hf_api.reserve_prescription(IN p_prescription text,INOUT p_id uuid) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE r hospitalflow.prescriptions%ROWTYPE;v_available bigint;BEGIN PERFORM hf_security.require_actor(ARRAY['Pharmacist']);PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO STRICT r FROM hospitalflow.prescriptions WHERE id=p_prescription AND status='Pending' FOR UPDATE;
 SELECT quantity-(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_reservations WHERE medicine_id=r.medicine_id AND status='Active') INTO STRICT v_available FROM hospitalflow.medicine_batches WHERE id=r.medicine_id AND expiry>hf_api.hospital_today();
 IF v_available<r.quantity OR EXISTS(SELECT 1 FROM hospitalflow.medicine_batch_holds WHERE medicine_id=r.medicine_id AND released_at IS NULL) THEN RAISE EXCEPTION 'Insufficient available stock for reservation' USING ERRCODE='23514';END IF;
 p_id:=gen_random_uuid();INSERT INTO hospitalflow.stock_reservations(id,prescription_id,medicine_id,quantity,status) VALUES(p_id,r.id,r.medicine_id,r.quantity,'Active');PERFORM hf_security.audit('procedure:reserve-prescription',p_id::text);END $$;
CREATE PROCEDURE hf_api.approve_purchase_order(IN p_id uuid) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY[]::text[]);PERFORM pg_advisory_xact_lock(74192301);
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.purchase_order_lines WHERE purchase_order_id=p_id) THEN RAISE EXCEPTION 'Purchase order has no lines' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.purchase_orders SET status='Approved',approved_by=hf_security.actor_id() WHERE id=p_id AND status='Draft' AND EXISTS(SELECT 1 FROM hospitalflow.suppliers WHERE id=supplier_id AND active);
 IF NOT FOUND THEN RAISE EXCEPTION 'Purchase order unavailable for approval' USING ERRCODE='23514';END IF;PERFORM hf_security.audit('procedure:approve-purchase-order',p_id::text);END $$;
CREATE PROCEDURE hf_api.receive_purchase_order(IN p_order uuid,IN p_reference text,IN p_lines jsonb,INOUT p_id uuid) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE item jsonb;l hospitalflow.purchase_order_lines%ROWTYPE;n integer;already bigint;movement text;v_order hospitalflow.purchase_orders%ROWTYPE;BEGIN
 PERFORM hf_security.require_actor(ARRAY['Pharmacist']);PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO STRICT v_order FROM hospitalflow.purchase_orders WHERE id=p_order AND status IN ('Approved','Partially received') FOR UPDATE;
 IF jsonb_typeof(p_lines) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lines)=0 OR length(trim(p_reference)) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Receipt lines and reference required' USING ERRCODE='23514';END IF;
 p_id:=gen_random_uuid();INSERT INTO hospitalflow.goods_receipts(id,purchase_order_id,reference,received_by) VALUES(p_id,p_order,p_reference,hf_security.actor_id());
 FOR item IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
 SELECT * INTO STRICT l FROM hospitalflow.purchase_order_lines WHERE id=(item->>'lineId')::uuid AND purchase_order_id=p_order FOR UPDATE;
 n:=hf_api.positive_number(item,'quantity',true)::integer;SELECT COALESCE(sum(quantity),0) INTO already FROM hospitalflow.goods_receipt_lines WHERE purchase_order_line_id=l.id;
 IF n+already>l.quantity THEN RAISE EXCEPTION 'Receipt exceeds ordered quantity' USING ERRCODE='23514';END IF;
 CALL hf_api.receive_stock(movement,l.medicine_id,n,'Purchase receipt '||p_id::text);
 INSERT INTO hospitalflow.goods_receipt_lines(receipt_id,purchase_order_line_id,quantity,movement_id) VALUES(p_id,l.id,n,movement);
 END LOOP;
 UPDATE hospitalflow.purchase_orders SET status=CASE WHEN EXISTS(SELECT 1 FROM hospitalflow.purchase_order_lines pl WHERE pl.purchase_order_id=p_order AND pl.quantity>(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.goods_receipt_lines WHERE purchase_order_line_id=pl.id)) THEN 'Partially received'::hospitalflow.purchase_status ELSE 'Received'::hospitalflow.purchase_status END WHERE id=p_order;
 PERFORM hf_security.audit('procedure:receive-purchase-order',p_id::text);END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hf_security,hf_api FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA hf_api FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.005_database_api.sql','71931BFA6818D6745FE7CBC71FB25E431B164A757F2222FA82184009741EB294');

-- 006_integrity_reporting_audit.sql
CREATE OR REPLACE VIEW hospitalflow.invoice_balances AS
 SELECT b.id,b.patient_id,COALESCE(l.total,0)::numeric(14,2) total,
 (COALESCE(p.paid,0)-COALESCE(r.reversed,0))::numeric(14,2) paid,
 (COALESCE(l.total,0)-COALESCE(p.paid,0)+COALESCE(r.reversed,0))::numeric(14,2) balance
 FROM hospitalflow.bills b LEFT JOIN(SELECT bill_id,sum(amount) total FROM hospitalflow.bill_lines GROUP BY bill_id)l ON l.bill_id=b.id
 LEFT JOIN(SELECT bill_id,sum(amount) paid FROM hospitalflow.payments GROUP BY bill_id)p ON p.bill_id=b.id
 LEFT JOIN(SELECT p.bill_id,sum(r.amount) reversed FROM hospitalflow.payment_reversals r JOIN hospitalflow.payments p ON p.id=r.payment_id GROUP BY p.bill_id)r ON r.bill_id=b.id;
CREATE OR REPLACE FUNCTION hospitalflow.validate_stock_balance() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE v_id text;BEGIN IF TG_TABLE_NAME='medicine_batches' THEN v_id:=NEW.id;ELSE v_id:=NEW.medicine_id;END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.medicine_batches m WHERE m.id=v_id AND(m.quantity<>(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_movements WHERE medicine_id=m.id) OR m.quantity<(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_reservations WHERE medicine_id=m.id AND status='Active'))) THEN RAISE EXCEPTION 'Stock and reservation ledgers disagree' USING ERRCODE='23514';END IF;RETURN NULL;END $$;
CREATE CONSTRAINT TRIGGER reservation_stock_balance AFTER INSERT OR UPDATE ON hospitalflow.stock_reservations DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_stock_balance();
CREATE OR REPLACE FUNCTION hospitalflow.validate_occupancy() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE ids text[];BEGIN
 IF TG_TABLE_NAME='beds' THEN ids:=ARRAY[NEW.id];ELSIF TG_OP='INSERT' THEN ids:=ARRAY[NEW.bed_id];ELSE ids:=ARRAY[NEW.bed_id,OLD.bed_id];END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.beds b WHERE b.id=ANY(ids) AND((b.status='Occupied') IS DISTINCT FROM EXISTS(SELECT 1 FROM hospitalflow.admissions a WHERE a.bed_id=b.id AND a.status='Admitted'))) THEN RAISE EXCEPTION 'Bed status and active admission disagree' USING ERRCODE='23514';END IF;RETURN NULL;END $$;
CREATE FUNCTION hospitalflow.validate_payment_reversal() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);IF(SELECT sum(amount) FROM hospitalflow.payment_reversals WHERE payment_id=NEW.payment_id)>(SELECT amount FROM hospitalflow.payments WHERE id=NEW.payment_id) THEN RAISE EXCEPTION 'Reversal exceeds original payment' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE CONSTRAINT TRIGGER payment_reversal_limit AFTER INSERT ON hospitalflow.payment_reversals DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_payment_reversal();
CREATE FUNCTION hospitalflow.validate_appointment_schedule() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE d hospitalflow.doctors%ROWTYPE;local_at timestamp;tz text;BEGIN
 IF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status AND NOT((OLD.status='Scheduled' AND NEW.status IN ('Checked in','Cancelled','No show')) OR(OLD.status='Checked in' AND NEW.status IN ('In consultation','Cancelled')) OR(OLD.status='In consultation' AND NEW.status='Completed')) THEN RAISE EXCEPTION 'Invalid appointment status transition' USING ERRCODE='23514';END IF;
 IF TG_OP='UPDATE' AND OLD.status<>'Scheduled' AND(NEW.patient_id IS DISTINCT FROM OLD.patient_id OR NEW.doctor_id IS DISTINCT FROM OLD.doctor_id OR NEW.at IS DISTINCT FROM OLD.at) THEN RAISE EXCEPTION 'An active visit cannot be rescheduled' USING ERRCODE='23514';END IF;
 IF NEW.status IN ('Cancelled','No show','Completed') THEN RETURN NEW;END IF;
 SELECT * INTO STRICT d FROM hospitalflow.doctors WHERE id=NEW.doctor_id AND active;
 SELECT value INTO tz FROM hospitalflow.system_settings WHERE key='hospital_timezone';local_at:=NEW.at AT TIME ZONE tz;
 IF local_at::time<d.start OR local_at::time+interval '30 minutes'>d."end" OR extract(minute FROM local_at)::integer%30<>0 OR extract(second FROM local_at)<>0 OR EXISTS(SELECT 1 FROM hospitalflow.provider_absences WHERE doctor_id=d.id AND cancelled_at IS NULL AND starts_at<NEW.at+interval '30 minutes' AND ends_at>NEW.at) OR(EXISTS(SELECT 1 FROM hospitalflow.provider_sessions ps WHERE ps.doctor_id=d.id AND (ps.starts_at AT TIME ZONE tz)::date=local_at::date) AND NOT EXISTS(SELECT 1 FROM hospitalflow.provider_sessions ps WHERE ps.doctor_id=d.id AND ps.starts_at<=NEW.at AND ps.ends_at>=NEW.at+interval '30 minutes')) THEN RAISE EXCEPTION 'Appointment conflicts with shift, slot boundary or approved absence' USING ERRCODE='23514';END IF;
 RETURN NEW;END $$;
CREATE TRIGGER appointment_schedule BEFORE INSERT OR UPDATE ON hospitalflow.appointments FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_appointment_schedule();
CREATE FUNCTION hospitalflow.validate_patient_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);IF NEW.dob>hf_api.hospital_today() OR NEW.phone!~'^\+?[0-9 ()-]{7,20}$' THEN RAISE EXCEPTION 'Invalid patient birth date or contact number' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.patients WHERE id<>NEW.id AND dob=NEW.dob AND(lower(name)=lower(NEW.name) OR phone=NEW.phone)) THEN RAISE EXCEPTION 'Possible duplicate patient identity' USING ERRCODE='23505';END IF;RETURN NEW;END $$;
CREATE TRIGGER patient_identity BEFORE INSERT OR UPDATE ON hospitalflow.patients FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_patient_identity();
CREATE FUNCTION hospitalflow.validate_service_price() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);
 IF TG_OP='UPDATE' AND(NEW.service_id<>OLD.service_id OR NEW.amount<>OLD.amount OR NEW.currency<>OLD.currency OR NEW.effective_from<>OLD.effective_from) THEN RAISE EXCEPTION 'Post a new effective-dated price instead of changing history' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.service_prices WHERE id<>NEW.id AND service_id=NEW.service_id AND effective_from<COALESCE(NEW.effective_to,'infinity'::timestamptz) AND COALESCE(effective_to,'infinity'::timestamptz)>NEW.effective_from) THEN RAISE EXCEPTION 'Service price periods overlap' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER price_effectivity BEFORE INSERT OR UPDATE ON hospitalflow.service_prices FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_service_price();
CREATE FUNCTION hospitalflow.validate_dispense_trace() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF NEW.status='Dispensed' AND(TG_OP='INSERT' OR OLD.status<>'Dispensed') AND NOT EXISTS(SELECT 1 FROM hospitalflow.prescription_dispensations d JOIN hospitalflow.stock_movements m ON m.id=d.movement_id JOIN hospitalflow.bills b ON b.id=d.bill_id WHERE d.prescription_id=NEW.id AND m.medicine_id=NEW.medicine_id AND m.quantity=-NEW.quantity AND b.patient_id=NEW.patient_id) THEN RAISE EXCEPTION 'Dispense requires linked stock movement and patient invoice' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE CONSTRAINT TRIGGER dispense_trace AFTER INSERT OR UPDATE ON hospitalflow.prescriptions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_dispense_trace();
CREATE OR REPLACE FUNCTION hospitalflow.validate_discharge_readiness() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF NEW.status='Discharged' AND(TG_OP='INSERT' OR OLD.status<>'Discharged') AND(EXISTS(SELECT 1 FROM hospitalflow.invoice_balances WHERE patient_id=NEW.patient_id AND balance>0) OR EXISTS(SELECT 1 FROM hospitalflow.prescriptions WHERE patient_id=NEW.patient_id AND status='Pending') OR EXISTS(SELECT 1 FROM hospitalflow.discharge_tasks WHERE admission_id=NEW.id AND required AND completed_at IS NULL)) THEN RAISE EXCEPTION 'Discharge prerequisites are incomplete' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE FUNCTION hospitalflow.sync_encounter() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF TG_TABLE_NAME='appointments' THEN
 INSERT INTO hospitalflow.encounters(patient_id,kind,appointment_id,opened_at,closed_at,status) VALUES(NEW.patient_id,'Outpatient',NEW.id,NEW.at,CASE WHEN NEW.status IN ('Completed','Cancelled','No show') THEN greatest(NEW.at,now()) END,CASE WHEN NEW.status='Completed' THEN 'Completed' WHEN NEW.status IN ('Cancelled','No show') THEN 'Cancelled' ELSE 'Open' END)
 ON CONFLICT(appointment_id) DO UPDATE SET patient_id=EXCLUDED.patient_id,closed_at=EXCLUDED.closed_at,status=EXCLUDED.status;
 ELSE INSERT INTO hospitalflow.encounters(patient_id,kind,admission_id,opened_at,closed_at,status) VALUES(NEW.patient_id,'Inpatient',NEW.id,NEW.at,NEW.discharged,CASE WHEN NEW.status='Discharged' THEN 'Completed' ELSE 'Open' END)
 ON CONFLICT(admission_id) DO UPDATE SET closed_at=EXCLUDED.closed_at,status=EXCLUDED.status;END IF;RETURN NEW;END $$;
CREATE TRIGGER encounter_sync AFTER INSERT OR UPDATE ON hospitalflow.appointments FOR EACH ROW EXECUTE FUNCTION hospitalflow.sync_encounter();
CREATE TRIGGER encounter_sync AFTER INSERT OR UPDATE ON hospitalflow.admissions FOR EACH ROW EXECUTE FUNCTION hospitalflow.sync_encounter();
CREATE OR REPLACE FUNCTION hospitalflow.record_row_history() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE doc jsonb;cols text[];ref text;BEGIN
 doc:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF TG_OP='UPDATE' THEN SELECT array_agg(key ORDER BY key) INTO cols FROM jsonb_each(doc) WHERE value IS DISTINCT FROM to_jsonb(OLD)->key;
 ELSE SELECT array_agg(key ORDER BY key) INTO cols FROM jsonb_each(doc);END IF;
 IF cols IS NULL THEN RETURN NEW;END IF;
 ref:=COALESCE(doc->>'id',doc->>'line_id',doc->>'name',doc->>'key',(doc->>'notification_id')||':'||(doc->>'user_id'),(doc->>'user_id')||':'||(doc->>'department'),'record');
 INSERT INTO hospitalflow.row_history(table_name,record_id,operation,changed_columns,actor_id,correlation_id) VALUES(TG_TABLE_NAME,ref,TG_OP,cols,nullif(current_setting('hospitalflow.actor_id',true),''),nullif(current_setting('hospitalflow.correlation_id',true),''));
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;END $$;
DO $$ DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['departments','wards','system_settings','hospital_profile','staff_members','user_departments','patient_access_grants','patient_contacts','patient_consents','provider_absences','provider_sessions','encounters','service_catalog','service_prices','invoice_line_context','payment_reversals','clinical_orders','discharge_tasks','follow_ups','suppliers','purchase_orders','purchase_order_lines','goods_receipts','goods_receipt_lines','medicine_batch_holds','stock_reservations','prescription_dispensations','notification_acknowledgements','prescription_authors','admission_events'] LOOP
 EXECUTE format('CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history()',t);END LOOP;
 FOREACH t IN ARRAY ARRAY['payment_reversals','invoice_line_context','goods_receipts','goods_receipt_lines','prescription_dispensations','notification_acknowledgements','integration_outbox'] LOOP
 EXECUTE format('CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes()',t);END LOOP;
END $$;
CREATE FUNCTION hospitalflow.enqueue_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE e uuid;BEGIN IF TG_OP='UPDATE' AND to_jsonb(OLD)=to_jsonb(NEW) THEN RETURN NEW;END IF;
 e:=gen_random_uuid();INSERT INTO hospitalflow.integration_outbox(id,event_type,aggregate_type,aggregate_id,payload) VALUES(e,TG_TABLE_NAME||'.'||lower(TG_OP),TG_TABLE_NAME,NEW.id::text,jsonb_build_object('reference',NEW.id::text));
 INSERT INTO hospitalflow.outbox_delivery(event_id) VALUES(e);RETURN NEW;END $$;
DO $$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['patients','appointments','admissions','prescriptions','payments','payment_reversals','purchase_orders'] LOOP
 EXECUTE format('CREATE TRIGGER enqueue_integration_event AFTER INSERT OR UPDATE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.enqueue_change()',t);END LOOP;END $$;
ALTER TABLE hospitalflow.integration_outbox ADD CONSTRAINT minimal_outbox_payload CHECK(payload-ARRAY['reference','status','kind']='{}'::jsonb);
CREATE FUNCTION hf_security.can_access_encounter(p_encounter uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ SELECT EXISTS(SELECT 1 FROM hospitalflow.encounters WHERE id=p_encounter AND hf_security.can_access_patient(patient_id)) $$;
DO $$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['patient_contacts','patient_consents','follow_ups'] LOOP
 EXECUTE format('ALTER TABLE hospitalflow.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('ALTER TABLE hospitalflow.%I FORCE ROW LEVEL SECURITY',t);
 EXECUTE format('CREATE POLICY patient_scope ON hospitalflow.%I USING (hf_security.can_access_patient(patient_id)) WITH CHECK(hf_security.can_access_patient(patient_id))',t);END LOOP;END $$;
ALTER TABLE hospitalflow.clinical_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE hospitalflow.clinical_orders FORCE ROW LEVEL SECURITY;
CREATE POLICY encounter_scope ON hospitalflow.clinical_orders USING(hf_security.can_access_encounter(encounter_id)) WITH CHECK(hf_security.can_access_encounter(encounter_id));
CREATE VIEW hf_reporting.inventory WITH(security_invoker=true) AS
 SELECT m.id,m.name,m.batch,m.expiry,m.quantity AS on_hand,m.reorder,m.price,
 COALESCE(r.reserved,0)::bigint reserved,(m.quantity-COALESCE(r.reserved,0))::bigint available,
 EXISTS(SELECT 1 FROM hospitalflow.medicine_batch_holds h WHERE h.medicine_id=m.id AND h.released_at IS NULL) AS held,
 m.quantity<=m.reorder AS low_stock FROM hospitalflow.medicine_batches m LEFT JOIN(SELECT medicine_id,sum(quantity)reserved FROM hospitalflow.stock_reservations WHERE status='Active' GROUP BY medicine_id)r ON r.medicine_id=m.id OFFSET 0;
CREATE VIEW hf_reporting.stock_ledger WITH(security_invoker=true) AS SELECT m.id,m.medicine_id,b.name,b.batch,m.quantity,m.reason,m.at FROM hospitalflow.stock_movements m JOIN hospitalflow.medicine_batches b ON b.id=m.medicine_id OFFSET 0;
CREATE VIEW hf_reporting.bed_status WITH(security_invoker=true) AS SELECT * FROM hospitalflow.bed_occupancy OFFSET 0;
CREATE VIEW hf_reporting.open_invoices WITH(security_invoker=true) AS SELECT * FROM hospitalflow.invoice_balances WHERE balance>0 OFFSET 0;
CREATE VIEW hf_reporting.purchase_order_progress WITH(security_invoker=true) AS
 SELECT p.id,p.number,p.status,s.name supplier,l.id line_id,l.medicine_id,l.quantity ordered,COALESCE(r.received,0)::bigint received,l.quantity-COALESCE(r.received,0) outstanding
 FROM hospitalflow.purchase_orders p JOIN hospitalflow.suppliers s ON s.id=p.supplier_id JOIN hospitalflow.purchase_order_lines l ON l.purchase_order_id=p.id
 LEFT JOIN(SELECT purchase_order_line_id,sum(quantity) received FROM hospitalflow.goods_receipt_lines GROUP BY purchase_order_line_id)r ON r.purchase_order_line_id=l.id;
CREATE MATERIALIZED VIEW hf_reporting.daily_collections AS
 SELECT "day",sum(amount)::numeric(18,2) AS net_collections FROM(
 SELECT(p.at AT TIME ZONE h.timezone)::date AS "day",p.amount FROM hospitalflow.payments p CROSS JOIN hospitalflow.hospital_profile h
 UNION ALL SELECT(r.at AT TIME ZONE h.timezone)::date,-r.amount FROM hospitalflow.payment_reversals r CROSS JOIN hospitalflow.hospital_profile h)s GROUP BY "day";
CREATE UNIQUE INDEX daily_collections_day_idx ON hf_reporting.daily_collections("day");
CREATE VIEW hf_api.inventory WITH(security_invoker=true) AS SELECT * FROM hf_reporting.inventory OFFSET 0;
COMMENT ON VIEW hf_api.inventory IS 'Read-only synonym equivalent for hf_reporting.inventory. PostgreSQL schemas group APIs in place of Oracle packages.';
CREATE VIEW hf_ops.object_inventory AS
 SELECT n.nspname AS schema_name,CASE c.relkind WHEN 'r' THEN 'TABLE' WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'S' THEN 'SEQUENCE' WHEN 'i' THEN 'INDEX' END AS object_type,c.relname AS object_name
 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops') AND c.relkind IN ('r','v','m','S','i')
 UNION ALL SELECT n.nspname,CASE p.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,p.proname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops')
 UNION ALL SELECT n.nspname,'TRIGGER',c.relname||'.'||t.tgname FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN ('hospitalflow','hf_ops');
CREATE TABLE hf_ops.schema_change_events(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,occurred_at timestamptz NOT NULL DEFAULT now(),database_user text NOT NULL,command_tag text NOT NULL,object_identity text NOT NULL);
CREATE FUNCTION hf_ops.capture_ddl() RETURNS event_trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
DECLARE obj record;BEGIN FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
 IF obj.schema_name IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops') THEN INSERT INTO hf_ops.schema_change_events(database_user,command_tag,object_identity) VALUES(session_user,obj.command_tag,obj.object_identity);END IF;END LOOP;END $$;
CREATE FUNCTION hf_ops.capture_drop() RETURNS event_trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
DECLARE obj record;BEGIN FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects() LOOP IF obj.schema_name IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops') THEN INSERT INTO hf_ops.schema_change_events(database_user,command_tag,object_identity) VALUES(session_user,'DROP',obj.object_identity);END IF;END LOOP;END $$;
DO $$ BEGIN IF(SELECT rolsuper FROM pg_roles WHERE rolname=current_user) THEN
 CREATE EVENT TRIGGER hospitalflow_ddl_audit ON ddl_command_end EXECUTE FUNCTION hf_ops.capture_ddl();
 CREATE EVENT TRIGGER hospitalflow_drop_audit ON sql_drop EXECUTE FUNCTION hf_ops.capture_drop();END IF;END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hf_security,hf_api,hf_ops,hospitalflow FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA hf_api FROM PUBLIC;
CREATE VIEW hospitalflow.payment_reversal_receipts AS SELECT 'REV:'||r.id::text id,p.bill_id,-r.amount amount,'Reversal'::text method,r.at FROM hospitalflow.payment_reversals r JOIN hospitalflow.payments p ON p.id=r.payment_id;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.006_integrity_reporting_audit.sql','8FFB19CF4E621D0B74C1CE570C0D72D4545CE1C8ED002D25681271E164250FE3');

-- 007_jobs_and_operations.sql
CREATE TABLE hf_ops.worker_heartbeats(worker text PRIMARY KEY,last_seen_at timestamptz NOT NULL,status text NOT NULL CHECK(status IN ('Started','Succeeded','Failed')));
CREATE PROCEDURE hf_ops.refresh_alerts() LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_ops,pg_temp AS $$
DECLARE v_alerts jsonb;BEGIN PERFORM pg_advisory_xact_lock(74192301);
 SELECT COALESCE(jsonb_agg(to_jsonb(a)),'[]'::jsonb) INTO v_alerts FROM(
 SELECT 'low-stock'::text rule,id reference,'Low stock needs attention'::text title,name||': '||quantity||' units remaining (reorder at '||reorder||').' message,'pharmacy'::text target FROM hospitalflow.medicine_batches WHERE quantity<=reorder
 UNION ALL SELECT 'expiry',id,'Medicine approaching expiry',name||' · '||batch||' · '||expiry,'pharmacy' FROM hospitalflow.medicine_batches WHERE expiry<=hf_api.hospital_today()+30
 UNION ALL SELECT 'cleaning',id,'Bed awaiting turnaround',id||' needs cleaning confirmation before reuse.','beds' FROM hospitalflow.beds WHERE status='Cleaning'
 UNION ALL SELECT 'queue',id,'Queue waiting time','A checked-in appointment has waited over 30 minutes.','appointments' FROM hospitalflow.appointments WHERE status='Checked in' AND checked_in<now()-interval '30 minutes')a;
 UPDATE hospitalflow.notifications n SET resolved_at=now() WHERE resolved_at IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_to_recordset(v_alerts) a(rule text,reference text) WHERE a.rule=n.rule AND a.reference=n.reference);
 INSERT INTO hospitalflow.notifications(id,rule,reference,title,message,target) SELECT gen_random_uuid()::text,rule,reference,title,message,target FROM jsonb_to_recordset(v_alerts) a(rule text,reference text,title text,message text,target text)
 ON CONFLICT(rule,reference) WHERE resolved_at IS NULL DO UPDATE SET message=EXCLUDED.message,title=EXCLUDED.title;
END $$;
CREATE PROCEDURE hf_ops.run_due_jobs(IN p_limit integer DEFAULT 5) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_ops,pg_temp AS $$
DECLARE j hf_ops.job_definitions%ROWTYPE;run uuid;failed boolean;code text;violations bigint;BEGIN
 IF p_limit NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'Job limit must be between 1 and 20' USING ERRCODE='23514';END IF;
 FOR j IN SELECT * FROM hf_ops.job_definitions WHERE enabled AND next_run_at<=clock_timestamp() ORDER BY next_run_at,name LIMIT p_limit FOR UPDATE SKIP LOCKED LOOP
 run:=gen_random_uuid();failed:=false;code:=NULL;
 INSERT INTO hf_ops.job_runs(id,job_name,status) VALUES(run,j.name,'Running');
 UPDATE hf_ops.job_definitions SET last_started_at=clock_timestamp() WHERE name=j.name;
 BEGIN
 CASE j.task
 WHEN 'refresh_alerts' THEN CALL hf_ops.refresh_alerts();
 WHEN 'session_cleanup' THEN DELETE FROM hospitalflow.sessions WHERE expires_at<now();DELETE FROM hospitalflow.auth_attempts WHERE blocked_until<now()-interval '1 day';
 WHEN 'integrity_check' THEN
 INSERT INTO hf_ops.integrity_findings(run_id,check_name,violations)
 SELECT run,'stock-reconciliation',count(*) FROM hospitalflow.medicine_batches m WHERE quantity<>(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_movements WHERE medicine_id=m.id)
 UNION ALL SELECT run,'negative-invoice-balance',count(*) FROM hospitalflow.invoice_balances WHERE balance<0
 UNION ALL SELECT run,'bed-occupancy',count(*) FROM hospitalflow.beds b WHERE(b.status='Occupied') IS DISTINCT FROM EXISTS(SELECT 1 FROM hospitalflow.admissions a WHERE a.bed_id=b.id AND a.status='Admitted')
 UNION ALL SELECT run,'stock-reservations',count(*) FROM hospitalflow.medicine_batches m WHERE quantity<(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_reservations WHERE medicine_id=m.id AND status='Active');
 SELECT sum(f.violations) INTO violations FROM hf_ops.integrity_findings f WHERE f.run_id=run;
 IF violations>0 THEN failed:=true;code:='INTEGRITY_FINDINGS';END IF;
 WHEN 'daily_snapshot' THEN INSERT INTO hf_ops.daily_snapshots(day,ward,staffed_beds,occupied_beds,available_beds)
 SELECT hf_api.hospital_today(),ward,staffed_beds,occupied_beds,available_beds FROM hospitalflow.bed_occupancy
 ON CONFLICT(day,ward) DO UPDATE SET staffed_beds=EXCLUDED.staffed_beds,occupied_beds=EXCLUDED.occupied_beds,available_beds=EXCLUDED.available_beds,captured_at=now();
 WHEN 'refresh_reports' THEN REFRESH MATERIALIZED VIEW hf_reporting.daily_collections;
 WHEN 'recover_outbox_leases' THEN UPDATE hospitalflow.outbox_delivery SET status=CASE WHEN attempts>=5 THEN 'Dead letter' ELSE 'Pending' END,lease_token=NULL,lease_until=NULL,next_attempt_at=now(),last_error_code='LEASE_EXPIRED' WHERE status='Leased' AND lease_until<now();
 WHEN 'backup_monitor' THEN INSERT INTO hf_ops.integrity_findings(run_id,check_name,violations) VALUES(run,'backup-freshness',CASE WHEN EXISTS(SELECT 1 FROM hf_ops.backup_runs WHERE status='Succeeded' AND completed_at>now()-interval '48 hours') THEN 0 ELSE 1 END);
 WHEN 'analyze_tables' THEN ANALYZE hospitalflow.patients;ANALYZE hospitalflow.appointments;ANALYZE hospitalflow.admissions;ANALYZE hospitalflow.medicine_batches;ANALYZE hospitalflow.stock_movements;ANALYZE hospitalflow.bills;ANALYZE hospitalflow.bill_lines;ANALYZE hospitalflow.payments;ANALYZE hospitalflow.activity_log;
 END CASE;
 EXCEPTION WHEN OTHERS THEN failed:=true;code:=SQLSTATE;
 END;
 UPDATE hf_ops.job_runs SET finished_at=clock_timestamp(),status=CASE WHEN failed THEN 'Failed' ELSE 'Succeeded' END,error_code=code WHERE id=run;
 UPDATE hf_ops.job_definitions SET last_finished_at=clock_timestamp(),last_status=CASE WHEN failed THEN 'Failed' ELSE 'Succeeded' END,failures=CASE WHEN failed THEN failures+1 ELSE 0 END,
 next_run_at=clock_timestamp()+make_interval(secs=>CASE WHEN failed THEN least(21600,j.interval_seconds*power(2,least(j.failures+1,8)))::integer ELSE j.interval_seconds END) WHERE name=j.name;
 INSERT INTO hospitalflow.activity_log(id,actor,action,reference,at,outcome,correlation_id,method) VALUES(gen_random_uuid()::text,'Database scheduler','job-run',j.name,clock_timestamp(),CASE WHEN failed THEN 'Failed' ELSE 'Success' END,run::text,'JOB');
 END LOOP;END $$;
CREATE PROCEDURE hf_ops.worker_heartbeat(IN p_worker text,IN p_status text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
BEGIN IF p_worker!~'^[a-z0-9_-]{1,64}$' OR p_status NOT IN ('Started','Succeeded','Failed') THEN RAISE EXCEPTION 'Invalid heartbeat' USING ERRCODE='23514';END IF;
 INSERT INTO hf_ops.worker_heartbeats(worker,last_seen_at,status) VALUES(p_worker,clock_timestamp(),p_status) ON CONFLICT(worker) DO UPDATE SET last_seen_at=EXCLUDED.last_seen_at,status=EXCLUDED.status;END $$;
CREATE PROCEDURE hf_ops.start_backup(INOUT p_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
BEGIN p_id:=gen_random_uuid();INSERT INTO hf_ops.backup_runs(id,status) VALUES(p_id,'Running');END $$;
CREATE PROCEDURE hf_ops.finish_backup(IN p_id uuid,IN p_success boolean,IN p_reference text,IN p_bytes bigint,IN p_sha256 text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
BEGIN IF p_success AND(p_reference IS NULL OR p_reference!~'^[a-zA-Z0-9._-]{1,200}$' OR p_bytes<=0 OR p_sha256!~'^[A-Fa-f0-9]{64}$') THEN RAISE EXCEPTION 'Invalid backup evidence' USING ERRCODE='23514';END IF;
 UPDATE hf_ops.backup_runs SET status=CASE WHEN p_success THEN 'Succeeded' ELSE 'Failed' END,completed_at=clock_timestamp(),file_reference=CASE WHEN p_success THEN p_reference END,bytes=CASE WHEN p_success THEN p_bytes END,sha256=CASE WHEN p_success THEN p_sha256 END,error_code=CASE WHEN NOT p_success THEN 'BACKUP_FAILED' END WHERE id=p_id AND status='Running';
 IF NOT FOUND THEN RAISE EXCEPTION 'Backup run is not active' USING ERRCODE='23514';END IF;END $$;
CREATE VIEW hf_ops.job_health AS SELECT j.name,j.enabled,j.next_run_at,j.last_started_at,j.last_finished_at,j.last_status,j.failures,
 CASE WHEN NOT j.enabled THEN 'Disabled' WHEN j.last_status='Failed' THEN 'Failed' WHEN j.next_run_at<now()-make_interval(secs=>greatest(180,j.interval_seconds)) THEN 'Overdue' ELSE 'Ready' END health FROM hf_ops.job_definitions j;
CREATE VIEW hf_ops.latest_integrity_findings AS SELECT DISTINCT ON(check_name) check_name,violations,checked_at,run_id FROM hf_ops.integrity_findings ORDER BY check_name,checked_at DESC,id;
CREATE VIEW hf_ops.outbox_health AS SELECT status,count(*) event_count,min(next_attempt_at) oldest_due FROM hospitalflow.outbox_delivery GROUP BY status;
CREATE FUNCTION hf_api.claim_outbox(p_limit integer,p_lease_seconds integer) RETURNS TABLE(event_id uuid,event_type text,aggregate_id text,payload jsonb,lease_token uuid) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY[]::text[]);
 IF p_limit NOT BETWEEN 1 AND 100 OR p_lease_seconds NOT BETWEEN 30 AND 900 THEN RAISE EXCEPTION 'Invalid outbox claim limits' USING ERRCODE='23514';END IF;
 RETURN QUERY WITH candidates AS(SELECT d.event_id FROM hospitalflow.outbox_delivery d WHERE d.status='Pending' AND d.next_attempt_at<=now() ORDER BY d.next_attempt_at,d.event_id LIMIT p_limit FOR UPDATE SKIP LOCKED),
 claimed AS(UPDATE hospitalflow.outbox_delivery d SET status='Leased',attempts=attempts+1,lease_token=gen_random_uuid(),lease_until=now()+make_interval(secs=>p_lease_seconds) FROM candidates c WHERE d.event_id=c.event_id RETURNING d.event_id,d.lease_token)
 SELECT e.id,e.event_type,e.aggregate_id,e.payload,c.lease_token FROM claimed c JOIN hospitalflow.integration_outbox e ON e.id=c.event_id;
END $$;
CREATE PROCEDURE hf_api.complete_outbox(IN p_event uuid,IN p_token uuid,IN p_success boolean,IN p_error_code text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY[]::text[]);
 IF NOT p_success AND(p_error_code IS NULL OR p_error_code!~'^[A-Z0-9_]{1,64}$') THEN RAISE EXCEPTION 'A safe error code is required' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.outbox_delivery SET status=CASE WHEN p_success THEN 'Delivered' WHEN attempts>=5 THEN 'Dead letter' ELSE 'Pending' END,delivered_at=CASE WHEN p_success THEN now() END,lease_token=NULL,lease_until=NULL,
 last_error_code=CASE WHEN NOT p_success THEN p_error_code END,next_attempt_at=now()+make_interval(secs=>least(3600,30*power(2,least(attempts,8)))::integer) WHERE event_id=p_event AND lease_token=p_token AND status='Leased' AND lease_until>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'Outbox lease is missing, expired or belongs to another worker' USING ERRCODE='23514';END IF;
 PERFORM hf_security.audit('outbox-completion',p_event::text);END $$;
CREATE FUNCTION hf_ops.prevent_history_change() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Operational evidence cannot be deleted or rewritten' USING ERRCODE='23514';END $$;
CREATE TRIGGER immutable_findings BEFORE UPDATE OR DELETE ON hf_ops.integrity_findings FOR EACH ROW EXECUTE FUNCTION hf_ops.prevent_history_change();
CREATE TRIGGER immutable_ddl_audit BEFORE UPDATE OR DELETE ON hf_ops.schema_change_events FOR EACH ROW EXECUTE FUNCTION hf_ops.prevent_history_change();
CREATE TRIGGER immutable_restore_evidence BEFORE UPDATE OR DELETE ON hf_ops.restore_drills FOR EACH ROW EXECUTE FUNCTION hf_ops.prevent_history_change();
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hf_ops,hf_api FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA hf_ops,hf_api FROM PUBLIC;
GRANT USAGE ON SCHEMA hf_ops TO hospitalflow_job_runner;
GRANT EXECUTE ON PROCEDURE hf_ops.run_due_jobs(integer),hf_ops.worker_heartbeat(text,text),hf_ops.start_backup(uuid),hf_ops.finish_backup(uuid,boolean,text,bigint,text) TO hospitalflow_job_runner;
GRANT SELECT ON hf_ops.job_health,hf_ops.latest_integrity_findings,hf_ops.outbox_health TO hospitalflow_job_runner;
CREATE FUNCTION hf_ops.protect_run_evidence() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE allowed text[];BEGIN
 IF TG_OP='DELETE' OR OLD.status<>'Running' OR NEW.status NOT IN ('Succeeded','Failed','Skipped') THEN RAISE EXCEPTION 'Completed operational evidence is immutable' USING ERRCODE='23514';END IF;
 allowed:=CASE WHEN TG_TABLE_NAME='job_runs' THEN ARRAY['status','finished_at','error_code'] ELSE ARRAY['status','completed_at','file_reference','bytes','sha256','error_code'] END;
 IF(to_jsonb(NEW)-allowed) IS DISTINCT FROM(to_jsonb(OLD)-allowed) THEN RAISE EXCEPTION 'Only final result fields can change' USING ERRCODE='23514';END IF;
 RETURN NEW;END $$;
CREATE TRIGGER immutable_completed_run BEFORE UPDATE OR DELETE ON hf_ops.job_runs FOR EACH ROW EXECUTE FUNCTION hf_ops.protect_run_evidence();
CREATE TRIGGER immutable_completed_backup BEFORE UPDATE OR DELETE ON hf_ops.backup_runs FOR EACH ROW EXECUTE FUNCTION hf_ops.protect_run_evidence();
CREATE TRIGGER audit_job_configuration AFTER INSERT OR UPDATE OR DELETE ON hf_ops.job_definitions FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE PROCEDURE hf_ops.record_restore_drill(IN p_backup uuid,IN p_passed boolean,IN p_evidence text,IN p_seconds integer) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
BEGIN IF length(trim(p_evidence)) NOT BETWEEN 1 AND 300 OR p_seconds<0 OR NOT EXISTS(SELECT 1 FROM hf_ops.backup_runs WHERE id=p_backup AND status='Succeeded') THEN RAISE EXCEPTION 'Completed backup and restore evidence required' USING ERRCODE='23514';END IF;
 INSERT INTO hf_ops.restore_drills(backup_id,outcome,evidence_reference,recovery_seconds) VALUES(p_backup,CASE WHEN p_passed THEN 'Passed' ELSE 'Failed' END,p_evidence,p_seconds);END $$;
REVOKE ALL ON FUNCTION hf_ops.protect_run_evidence() FROM PUBLIC;
REVOKE ALL ON PROCEDURE hf_ops.record_restore_drill(uuid,boolean,text,integer) FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.007_jobs_and_operations.sql','822F902C220DE2B0CAEFA878EA7CAA39E4D0BE245F2AE0CC0C28BFA82AD5B066');

-- 008_command_gateway.sql
CREATE FUNCTION hf_api.execute(p_action text,p_payload jsonb,p_key uuid,p_hash text) RETURNS text LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text;allowed text[];result text;ref text;original hospitalflow.idempotency_keys%ROWTYPE;uid uuid;tmp text;
 n numeric;n2 numeric;d date;from_time timestamptz;item jsonb;u hospitalflow.users%ROWTYPE;batch hospitalflow.medicine_batches%ROWTYPE;po uuid;
BEGIN
 IF jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR p_key IS NULL OR p_hash IS NULL OR p_hash!~'^[A-Fa-f0-9]{64}$' THEN RAISE EXCEPTION 'Object payload, retry key and keyed fingerprint required' USING ERRCODE='23514';END IF;
 allowed:=CASE
 WHEN p_action IN ('patient','patient-update','appointment','appointment-status','book-follow-up') THEN ARRAY['Reception']
 WHEN p_action IN ('admit','transfer','discharge','bed-status','discharge-task','complete-discharge-task') THEN ARRAY['Nurse']
 WHEN p_action IN ('medicine','stock','dispense','purchase-order','receive-purchase-order','hold-batch','release-batch','reserve-prescription','release-reservation','stock-adjustment') THEN ARRAY['Pharmacist']
 WHEN p_action IN ('bill','payment','adjustment','service-charge') THEN ARRAY['Billing']
 WHEN p_action IN ('prescription','cancel-prescription') THEN ARRAY['Doctor'] WHEN p_action IN ('note','clinical-order','complete-clinical-order','follow-up','clinical-order-status') THEN ARRAY['Doctor','Nurse']
 WHEN p_action IN ('patient-contact','patient-consent','revoke-consent') THEN ARRAY['Reception','Doctor','Nurse']
 WHEN p_action='notification-ack' THEN ARRAY['Reception','Doctor','Nurse','Pharmacist','Billing']
 WHEN p_action IN ('doctor','bed','user','user-status','supplier','approve-purchase-order','service','service-price','reverse-payment','provider-absence','cancel-absence','provider-session','grant-patient-access','staff-member','grant-department','ward-department','hospital-profile') THEN ARRAY[]::text[]
 ELSE NULL END;
 IF allowed IS NULL THEN RAISE EXCEPTION 'Unknown database command' USING ERRCODE='23514';END IF;
 actor:=hf_security.require_actor(allowed);PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO original FROM hospitalflow.idempotency_keys WHERE user_id=actor AND key=p_key;
 IF FOUND THEN IF original.action<>p_action OR original.request_hash<>p_hash THEN RAISE EXCEPTION 'Retry key already used for a different request' USING ERRCODE='23514';END IF;RETURN original.reference;END IF;
 CASE p_action
 WHEN 'patient','patient-update' THEN
 result:=CASE WHEN p_action='patient-update' THEN hf_api.required_text(p_payload,'id') END;
 CALL hf_api.save_patient(result,hf_api.required_text(p_payload,'name',100),hf_api.required_text(p_payload,'dob')::date,hf_api.required_text(p_payload,'sex'),hf_api.required_text(p_payload,'phone',20));
 WHEN 'doctor' THEN result:=hf_api.new_id('DR');INSERT INTO hospitalflow.departments(name) VALUES(hf_api.required_text(p_payload,'department',80)) ON CONFLICT DO NOTHING;
 INSERT INTO hospitalflow.doctors(id,name,department,start,"end") VALUES(result,hf_api.required_text(p_payload,'name',100),hf_api.required_text(p_payload,'department',80),hf_api.required_text(p_payload,'start')::time,hf_api.required_text(p_payload,'end')::time);
 WHEN 'bed' THEN result:=hf_api.required_text(p_payload,'id',50);IF EXISTS(SELECT 1 FROM hospitalflow.beds WHERE lower(id)=lower(result)) THEN RAISE EXCEPTION 'Bed identifier exists' USING ERRCODE='23505';END IF;
 INSERT INTO hospitalflow.wards(name) VALUES(hf_api.required_text(p_payload,'ward',100)) ON CONFLICT DO NOTHING;
 INSERT INTO hospitalflow.beds(id,ward,category,status) VALUES(result,hf_api.required_text(p_payload,'ward',100),hf_api.required_text(p_payload,'category',100),'Available');
 WHEN 'appointment' THEN CALL hf_api.book_appointment(result,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'doctorId'),hf_api.required_text(p_payload,'at')::timestamptz,hf_api.required_text(p_payload,'type',100));
 WHEN 'appointment-status' THEN result:=hf_api.required_text(p_payload,'id');CALL hf_api.set_appointment_status(result,hf_api.required_text(p_payload,'status'));
 WHEN 'admit' THEN CALL hf_api.admit_patient(result,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'bedId'),hf_api.required_text(p_payload,'reason'));
 WHEN 'transfer' THEN result:=hf_api.required_text(p_payload,'id');CALL hf_api.transfer_patient(result,hf_api.required_text(p_payload,'bedId'),hf_api.required_text(p_payload,'reason'));
 WHEN 'discharge' THEN result:=hf_api.required_text(p_payload,'id');CALL hf_api.discharge_patient(result,hf_api.required_text(p_payload,'summary',4000));
 WHEN 'bed-status' THEN result:=hf_api.required_text(p_payload,'id');ref:=hf_api.required_text(p_payload,'status');
 IF ref NOT IN ('Available','Cleaning','Maintenance') THEN RAISE EXCEPTION 'Invalid manual bed state' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.beds SET status=ref WHERE id=result AND status<>'Occupied';IF NOT FOUND THEN RAISE EXCEPTION 'Bed missing or occupied' USING ERRCODE='23514';END IF;
 WHEN 'medicine' THEN
 result:=hf_api.new_id('MED');d:=hf_api.required_text(p_payload,'expiry')::date;n:=(p_payload->>'quantity')::numeric;
 IF d<=hf_api.hospital_today() OR jsonb_typeof(p_payload->'quantity') IS DISTINCT FROM 'number' OR n IS NULL OR n<0 OR n>100000 OR n<>trunc(n) THEN RAISE EXCEPTION 'Invalid batch expiry or opening quantity' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.medicine_batches VALUES(result,hf_api.required_text(p_payload,'name'),hf_api.required_text(p_payload,'batch'),d,n::integer,hf_api.positive_number(p_payload,'reorder',true)::integer,hf_api.positive_number(p_payload,'price'));
 IF n>0 THEN INSERT INTO hospitalflow.stock_movements VALUES(hf_api.new_id('MOV'),result,n::integer,'Opening stock',now());END IF;
 WHEN 'stock' THEN CALL hf_api.receive_stock(result,hf_api.required_text(p_payload,'id'),hf_api.positive_number(p_payload,'quantity',true)::integer,hf_api.required_text(p_payload,'reason'));
 WHEN 'prescription' THEN result:=hf_api.new_id('RX');INSERT INTO hospitalflow.prescriptions VALUES(result,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'medicineId'),hf_api.positive_number(p_payload,'quantity',true)::integer,hf_api.required_text(p_payload,'instructions'),'Pending');INSERT INTO hospitalflow.prescription_authors(prescription_id,created_by) VALUES(result,actor);
 WHEN 'dispense' THEN result:=hf_api.required_text(p_payload,'id');CALL hf_api.dispense_prescription(result,tmp);
 WHEN 'bill' THEN CALL hf_api.create_bill(result,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'description'),hf_api.positive_number(p_payload,'amount'));
 WHEN 'payment' THEN CALL hf_api.post_payment(hf_api.required_text(p_payload,'id'),hf_api.positive_number(p_payload,'amount'),hf_api.required_text(p_payload,'method'),result);
 WHEN 'adjustment' THEN CALL hf_api.post_adjustment(hf_api.required_text(p_payload,'id'),hf_api.positive_number(p_payload,'amount'),hf_api.required_text(p_payload,'reason'),result);
 WHEN 'note' THEN result:=hf_api.new_id('NOTE');INSERT INTO hospitalflow.notes VALUES(result,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'text',4000),'Operational note',now());
 WHEN 'user' THEN
 result:=hf_api.new_id('USR');ref:=hf_api.required_text(p_payload,'email',150);tmp:=hf_api.required_text(p_payload,'passwordHash',1000);
 IF ref!~'^[^@ ]+@[^@ ]+$' OR length(tmp)<50 OR tmp!~'^[A-Za-z0-9+/=]+$' THEN RAISE EXCEPTION 'Valid email and application-generated password hash required' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.users(id,name,email,role,password_hash,active) VALUES(result,hf_api.required_text(p_payload,'name',100),ref,hf_api.required_text(p_payload,'role'),tmp,true);
 WHEN 'user-status' THEN result:=hf_api.required_text(p_payload,'id');
 IF jsonb_typeof(p_payload->'active') IS DISTINCT FROM 'boolean' OR result=actor THEN RAISE EXCEPTION 'Invalid account status change or self-disable request' USING ERRCODE='23514';END IF;
 SELECT * INTO STRICT u FROM hospitalflow.users WHERE id=result FOR UPDATE;
 IF NOT(p_payload->>'active')::boolean AND u.role='Administrator' AND(SELECT count(*) FROM hospitalflow.users WHERE role='Administrator' AND active)<=1 THEN RAISE EXCEPTION 'An active administrator must remain' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.users SET active=(p_payload->>'active')::boolean WHERE id=result;IF NOT(p_payload->>'active')::boolean THEN DELETE FROM hospitalflow.sessions WHERE user_id=result;END IF;
 WHEN 'supplier' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.suppliers(id,code,name,contact_email,contact_phone) VALUES(uid,hf_api.required_text(p_payload,'code',50),hf_api.required_text(p_payload,'name',150),p_payload->>'email',p_payload->>'phone');result:=uid::text;
 WHEN 'purchase-order' THEN
 uid:=gen_random_uuid();IF jsonb_typeof(p_payload->'lines') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'lines') NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Purchase order requires 1 to 200 lines' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.purchase_orders(id,supplier_id,number,created_by) VALUES(uid,hf_api.required_text(p_payload,'supplierId')::uuid,hf_api.new_id('PO'),actor);
 FOR item IN SELECT * FROM jsonb_array_elements(p_payload->'lines') LOOP INSERT INTO hospitalflow.purchase_order_lines(purchase_order_id,medicine_id,quantity,unit_cost) VALUES(uid,hf_api.required_text(item,'medicineId'),hf_api.positive_number(item,'quantity',true)::integer,hf_api.positive_number(item,'unitCost'));END LOOP;result:=uid::text;
 WHEN 'approve-purchase-order' THEN result:=hf_api.required_text(p_payload,'id');CALL hf_api.approve_purchase_order(result::uuid);
 WHEN 'receive-purchase-order' THEN CALL hf_api.receive_purchase_order(hf_api.required_text(p_payload,'id')::uuid,hf_api.required_text(p_payload,'reference',200),p_payload->'lines',uid);result:=uid::text;
 WHEN 'hold-batch' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.medicine_batch_holds(id,medicine_id,reason,held_by) VALUES(uid,hf_api.required_text(p_payload,'medicineId'),hf_api.required_text(p_payload,'reason'),actor);result:=uid::text;
 WHEN 'release-batch' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.medicine_batch_holds SET released_by=actor,released_at=now() WHERE id=result::uuid AND released_at IS NULL;IF NOT FOUND THEN RAISE EXCEPTION 'Active hold not found' USING ERRCODE='23514';END IF;
 WHEN 'reserve-prescription' THEN CALL hf_api.reserve_prescription(hf_api.required_text(p_payload,'id'),uid);result:=uid::text;
 WHEN 'release-reservation' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.stock_reservations SET status='Released' WHERE id=result::uuid AND status='Active';IF NOT FOUND THEN RAISE EXCEPTION 'Active reservation missing' USING ERRCODE='23514';END IF;
 WHEN 'stock-adjustment' THEN
 ref:=hf_api.required_text(p_payload,'id');n:=(p_payload->>'quantity')::numeric;
 IF jsonb_typeof(p_payload->'quantity') IS DISTINCT FROM 'number' OR n IS NULL OR n=0 OR abs(n)>100000 OR n<>trunc(n) THEN RAISE EXCEPTION 'Signed whole-number adjustment required' USING ERRCODE='23514';END IF;
 PERFORM 1 FROM hospitalflow.medicine_batches WHERE id=ref FOR UPDATE;UPDATE hospitalflow.medicine_batches SET quantity=quantity+n::integer WHERE id=ref;
 result:=hf_api.new_id('MOV');INSERT INTO hospitalflow.stock_movements VALUES(result,ref,n::integer,hf_api.required_text(p_payload,'reason'),now());
 WHEN 'service' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.service_catalog(id,code,name,department,category) VALUES(uid,hf_api.required_text(p_payload,'code',50),hf_api.required_text(p_payload,'name',150),p_payload->>'department',hf_api.required_text(p_payload,'category'));result:=uid::text;
 WHEN 'service-price' THEN
 uid:=gen_random_uuid();po:=hf_api.required_text(p_payload,'serviceId')::uuid;from_time:=COALESCE((p_payload->>'effectiveFrom')::timestamptz,now());
 IF from_time<now()-interval '1 minute' THEN RAISE EXCEPTION 'Price periods cannot be backdated' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.service_prices SET effective_to=from_time WHERE service_id=po AND effective_from<from_time AND(effective_to IS NULL OR effective_to>from_time);
 INSERT INTO hospitalflow.service_prices(id,service_id,amount,effective_from,created_by) VALUES(uid,po,hf_api.positive_number(p_payload,'amount'),from_time,actor);result:=uid::text;
 WHEN 'service-charge' THEN CALL hf_api.post_service_charge(hf_api.required_text(p_payload,'id'),hf_api.required_text(p_payload,'serviceId')::uuid,hf_api.positive_number(p_payload,'quantity'),result);
 WHEN 'reverse-payment' THEN CALL hf_api.reverse_payment(hf_api.required_text(p_payload,'id'),hf_api.positive_number(p_payload,'amount'),hf_api.required_text(p_payload,'reason'),uid);result:=uid::text;
 WHEN 'provider-absence' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.provider_absences(id,doctor_id,starts_at,ends_at,reason_code,approved_by) VALUES(uid,hf_api.required_text(p_payload,'doctorId'),hf_api.required_text(p_payload,'startsAt')::timestamptz,hf_api.required_text(p_payload,'endsAt')::timestamptz,hf_api.required_text(p_payload,'reasonCode',100),actor);result:=uid::text;
 WHEN 'grant-patient-access' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.patient_access_grants(id,user_id,patient_id,purpose,expires_at,granted_by) VALUES(uid,hf_api.required_text(p_payload,'userId'),hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'purpose',200),hf_api.required_text(p_payload,'expiresAt')::timestamptz,actor);result:=uid::text;
 WHEN 'discharge-task' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.discharge_tasks(id,admission_id,code,required) VALUES(uid,hf_api.required_text(p_payload,'admissionId'),hf_api.required_text(p_payload,'code',100),COALESCE((p_payload->>'required')::boolean,true));result:=uid::text;
 WHEN 'complete-discharge-task' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.discharge_tasks SET completed_by=actor,completed_at=now() WHERE id=result::uuid AND completed_at IS NULL;IF NOT FOUND THEN RAISE EXCEPTION 'Pending discharge task not found' USING ERRCODE='23514';END IF;
 WHEN 'follow-up' THEN uid:=gen_random_uuid();from_time:=hf_api.required_text(p_payload,'dueAt')::timestamptz;IF from_time<=now() THEN RAISE EXCEPTION 'Future follow-up required' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.follow_ups(id,patient_id,admission_id,due_at,doctor_id,instructions,status) VALUES(uid,hf_api.required_text(p_payload,'patientId'),p_payload->>'admissionId',from_time,p_payload->>'doctorId',hf_api.required_text(p_payload,'instructions'),'Pending');result:=uid::text;
 WHEN 'clinical-order' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.clinical_orders(id,encounter_id,service_id,ordered_by,status) VALUES(uid,hf_api.required_text(p_payload,'encounterId')::uuid,hf_api.required_text(p_payload,'serviceId')::uuid,actor,'Requested');result:=uid::text;
 WHEN 'complete-clinical-order' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.clinical_orders SET status='Completed',completed_at=now() WHERE id=result::uuid AND status IN ('Requested','In progress');IF NOT FOUND THEN RAISE EXCEPTION 'Pending clinical order not found' USING ERRCODE='23514';END IF;
 WHEN 'cancel-prescription' THEN result:=hf_api.required_text(p_payload,'id');
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.users WHERE id=actor AND role='Administrator') AND NOT EXISTS(SELECT 1 FROM hospitalflow.prescription_authors WHERE prescription_id=result AND created_by=actor) THEN RAISE EXCEPTION 'Only the author or administrator can cancel a prescription' USING ERRCODE='42501';END IF;
 UPDATE hospitalflow.prescriptions SET status='Cancelled' WHERE id=result AND status='Pending';IF NOT FOUND THEN RAISE EXCEPTION 'Pending prescription not found' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.stock_reservations SET status='Released' WHERE prescription_id=result AND status='Active';
 WHEN 'patient-contact' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.patient_contacts(id,patient_id,name,relationship,phone,is_emergency) VALUES(uid,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'name',100),hf_api.required_text(p_payload,'relationship',100),hf_api.required_text(p_payload,'phone',20),COALESCE((p_payload->>'isEmergency')::boolean,false));result:=uid::text;
 WHEN 'patient-consent' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.patient_consents(id,patient_id,purpose,granted_at,expires_at,evidence_reference,recorded_by) VALUES(uid,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'purpose',200),COALESCE((p_payload->>'grantedAt')::timestamptz,now()),(p_payload->>'expiresAt')::timestamptz,hf_api.required_text(p_payload,'evidenceReference',200),actor);result:=uid::text;
 WHEN 'revoke-consent' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.patient_consents SET revoked_at=now() WHERE id=result::uuid AND revoked_at IS NULL;IF NOT FOUND THEN RAISE EXCEPTION 'Active consent not found' USING ERRCODE='23514';END IF;
 WHEN 'staff-member' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.staff_members(id,user_id,doctor_id,employee_number,department,job_title) VALUES(uid,p_payload->>'userId',p_payload->>'doctorId',hf_api.required_text(p_payload,'employeeNumber',50),hf_api.required_text(p_payload,'department',80),hf_api.required_text(p_payload,'jobTitle',100));result:=uid::text;
 WHEN 'grant-department' THEN result:=hf_api.required_text(p_payload,'userId');INSERT INTO hospitalflow.user_departments(user_id,department) VALUES(result,hf_api.required_text(p_payload,'department',80)) ON CONFLICT DO NOTHING;
 WHEN 'ward-department' THEN result:=hf_api.required_text(p_payload,'ward',100);UPDATE hospitalflow.wards SET department=hf_api.required_text(p_payload,'department',80) WHERE name=result;IF NOT FOUND THEN RAISE EXCEPTION 'Ward not found' USING ERRCODE='23503';END IF;
 WHEN 'hospital-profile' THEN result:='1';UPDATE hospitalflow.hospital_profile SET name=hf_api.required_text(p_payload,'name',150),updated_at=now() WHERE id=1;
 WHEN 'provider-session' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.provider_sessions(id,doctor_id,starts_at,ends_at) VALUES(uid,hf_api.required_text(p_payload,'doctorId'),hf_api.required_text(p_payload,'startsAt')::timestamptz,hf_api.required_text(p_payload,'endsAt')::timestamptz);result:=uid::text;
 WHEN 'cancel-absence' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.provider_absences SET cancelled_at=now() WHERE id=result::uuid AND cancelled_at IS NULL;IF NOT FOUND THEN RAISE EXCEPTION 'Active absence not found' USING ERRCODE='23514';END IF;
 WHEN 'clinical-order-status' THEN result:=hf_api.required_text(p_payload,'id');ref:=hf_api.required_text(p_payload,'status');IF ref NOT IN ('In progress','Cancelled') THEN RAISE EXCEPTION 'Use the completion command to finalize an order' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.clinical_orders SET status=ref WHERE id=result::uuid AND status IN ('Requested','In progress');IF NOT FOUND THEN RAISE EXCEPTION 'Open clinical order not found' USING ERRCODE='23514';END IF;
 WHEN 'book-follow-up' THEN
 uid:=hf_api.required_text(p_payload,'id')::uuid;SELECT patient_id,COALESCE(p_payload->>'doctorId',doctor_id) INTO STRICT ref,tmp FROM hospitalflow.follow_ups WHERE id=uid AND status='Pending' FOR UPDATE;
 CALL hf_api.book_appointment(result,ref,tmp,hf_api.required_text(p_payload,'at')::timestamptz,'Follow-up');UPDATE hospitalflow.follow_ups SET appointment_id=result,status='Booked' WHERE id=uid;
 WHEN 'notification-ack' THEN result:=hf_api.required_text(p_payload,'id');IF EXISTS(SELECT 1 FROM hospitalflow.notifications WHERE id=result AND target='pharmacy') THEN PERFORM hf_security.require_actor(ARRAY['Pharmacist','Doctor']);END IF;
 INSERT INTO hospitalflow.notification_acknowledgements(notification_id,user_id,reason) VALUES(result,actor,hf_api.required_text(p_payload,'reason'));
 END CASE;
 PERFORM hf_security.audit(p_action,result);
 INSERT INTO hospitalflow.idempotency_keys(user_id,key,action,request_hash,reference) VALUES(actor,p_key,p_action,p_hash,result);
 CALL hf_ops.refresh_alerts();RETURN result;
END $$;
REVOKE ALL ON FUNCTION hf_api.execute(text,jsonb,uuid,text) FROM PUBLIC;
COMMENT ON FUNCTION hf_api.execute(text,jsonb,uuid,text) IS 'Trusted-backend command gateway. Validates transaction-local actor, application role, idempotency and domain rules. Supply actor from authenticated session, not client input. Individual CALL procedures are lower-level operator tools.';
CREATE UNIQUE INDEX beds_casefold_id_unique ON hospitalflow.beds(lower(id));
CREATE FUNCTION hospitalflow.validate_absence() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);IF NEW.cancelled_at IS NULL AND EXISTS(SELECT 1 FROM hospitalflow.appointments WHERE doctor_id=NEW.doctor_id AND status IN ('Scheduled','Checked in','In consultation') AND at<NEW.ends_at AND at+interval '30 minutes'>NEW.starts_at) THEN RAISE EXCEPTION 'Cancel or reassign overlapping appointments before approving absence' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER absence_conflict BEFORE INSERT OR UPDATE ON hospitalflow.provider_absences FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_absence();
ALTER TABLE hospitalflow.prescriptions DROP CONSTRAINT prescriptions_status_check;
ALTER TABLE hospitalflow.prescriptions ADD CONSTRAINT prescriptions_status_check CHECK(status IN ('Pending','Dispensed','Cancelled'));
CREATE FUNCTION hospitalflow.validate_prescription_state() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF TG_OP='UPDATE' AND(OLD.status<>'Pending' AND to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD)) THEN RAISE EXCEPTION 'Finalized prescriptions cannot be rewritten' USING ERRCODE='23514';END IF;
 IF TG_OP='UPDATE' AND OLD.status='Pending' AND NEW.status NOT IN ('Pending','Dispensed','Cancelled') THEN RAISE EXCEPTION 'Invalid prescription state' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER prescription_state BEFORE UPDATE ON hospitalflow.prescriptions FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_prescription_state();
CREATE FUNCTION hospitalflow.validate_provider_session() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);
 IF EXISTS(SELECT 1 FROM hospitalflow.provider_sessions WHERE id<>NEW.id AND doctor_id=NEW.doctor_id AND starts_at<NEW.ends_at AND ends_at>NEW.starts_at) THEN RAISE EXCEPTION 'Provider sessions overlap' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER provider_session_overlap BEFORE INSERT OR UPDATE ON hospitalflow.provider_sessions FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_provider_session();
CREATE FUNCTION hospitalflow.complete_follow_up() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF NEW.status='Completed' THEN UPDATE hospitalflow.follow_ups SET status='Completed' WHERE appointment_id=NEW.id AND status='Booked';END IF;RETURN NEW;END $$;
CREATE TRIGGER follow_up_completion AFTER UPDATE OF status ON hospitalflow.appointments FOR EACH ROW EXECUTE FUNCTION hospitalflow.complete_follow_up();
ALTER DEFAULT PRIVILEGES IN SCHEMA hospitalflow,hf_api,hf_security,hf_reporting,hf_ops REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.008_command_gateway.sql','65FE55B4951C90FDE34E5AD4E9B628757F25AC7A5C3061B283907DCD1497ADCB');

-- 009_database_contract.sql
ALTER TABLE hospitalflow.activity_log ADD COLUMN database_user text,ADD COLUMN transaction_id bigint;
ALTER TABLE hospitalflow.activity_log ALTER COLUMN database_user SET DEFAULT session_user,ALTER COLUMN transaction_id SET DEFAULT txid_current();
ALTER TABLE hospitalflow.row_history ADD COLUMN database_user text,ADD COLUMN transaction_id bigint;
ALTER TABLE hospitalflow.row_history ALTER COLUMN database_user SET DEFAULT session_user,ALTER COLUMN transaction_id SET DEFAULT txid_current();
COMMENT ON COLUMN hospitalflow.row_history.database_user IS 'Actual PostgreSQL session login for new events. NULL means the historical event predates this field.';
COMMENT ON COLUMN hospitalflow.activity_log.actor_id IS 'Application identity established by the trusted authenticated backend; database_user separately records the SQL login.';
CREATE OR REPLACE VIEW hf_ops.object_inventory AS
 SELECT n.nspname AS schema_name,CASE c.relkind WHEN 'r' THEN 'TABLE' WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'S' THEN 'SEQUENCE' WHEN 'i' THEN 'INDEX' END AS object_type,c.relname AS object_name
 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops') AND c.relkind IN ('r','v','m','S','i')
 UNION ALL SELECT n.nspname,CASE p.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,p.proname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops')
 UNION ALL SELECT n.nspname,'TRIGGER',c.relname||'.'||t.tgname FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN ('hospitalflow','hf_ops')
 UNION ALL SELECT n.nspname,'POLICY',c.relname||'.'||p.polname FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid=p.polrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hospitalflow'
 UNION ALL SELECT n.nspname,'TYPE',t.typname FROM pg_catalog.pg_type t JOIN pg_catalog.pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='hospitalflow' AND t.typtype IN ('d','e')
 UNION ALL SELECT 'hf_ops','EVENT TRIGGER',evtname FROM pg_catalog.pg_event_trigger WHERE evtname IN ('hospitalflow_ddl_audit','hospitalflow_drop_audit');
CREATE FUNCTION hf_ops.validate_database() RETURNS TABLE(check_name text,severity text,violations bigint,definition text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_ops,pg_temp AS $$
 SELECT 'stock-reconciliation','Error',count(*),'Batch quantity equals its movement ledger' FROM hospitalflow.medicine_batches m WHERE quantity<>(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_movements WHERE medicine_id=m.id)
 UNION ALL SELECT 'negative-invoice-balance','Error',count(*),'Net charges cannot be less than retained payments' FROM hospitalflow.invoice_balances WHERE balance<0
 UNION ALL SELECT 'bed-occupancy','Error',count(*),'Occupied status agrees with the active admission' FROM hospitalflow.beds b WHERE(b.status='Occupied') IS DISTINCT FROM EXISTS(SELECT 1 FROM hospitalflow.admissions a WHERE a.bed_id=b.id AND a.status='Admitted')
 UNION ALL SELECT 'assignment-history','Error',count(*),'Each active admission has the matching open assignment' FROM hospitalflow.admissions a WHERE a.status='Admitted' AND NOT EXISTS(SELECT 1 FROM hospitalflow.bed_assignments b WHERE b.admission_id=a.id AND b.bed_id=a.bed_id AND b.to_time IS NULL)
 UNION ALL SELECT 'reservation-capacity','Error',count(*),'Active reservations do not exceed physical stock' FROM hospitalflow.medicine_batches m WHERE quantity<(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_reservations WHERE medicine_id=m.id AND status='Active')
 UNION ALL SELECT 'payment-reversal-limit','Error',count(*),'Cumulative reversals do not exceed the original payment' FROM hospitalflow.payments p WHERE amount<(SELECT COALESCE(sum(amount),0) FROM hospitalflow.payment_reversals WHERE payment_id=p.id)
 UNION ALL SELECT 'invalid-constraints','Error',count(*),'All installed constraints are validated' FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname IN ('hospitalflow','hf_ops') AND NOT c.convalidated
 UNION ALL SELECT 'invalid-indexes','Error',count(*),'All installed indexes are valid and ready' FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('hospitalflow','hf_ops','hf_reporting') AND(NOT i.indisvalid OR NOT i.indisready)
 UNION ALL SELECT 'disabled-triggers','Error',count(*),'User-defined integrity/audit triggers remain enabled' FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('hospitalflow','hf_ops') AND NOT t.tgisinternal AND t.tgenabled='D'
 UNION ALL SELECT 'tables-without-primary-key','Error',count(*),'Every operational table has a primary key' FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('hospitalflow','hf_ops') AND c.relkind='r' AND NOT EXISTS(SELECT 1 FROM pg_constraint k WHERE k.conrelid=c.oid AND k.contype='p')
 UNION ALL SELECT 'public-routine-execution','Error',count(*),'Application/operations routines are not executable by PUBLIC' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner)))a WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_ops') AND a.grantee=0 AND a.privilege_type='EXECUTE'
 UNION ALL SELECT 'runtime-superuser-or-bypass','Error',count(*),'The application login is neither superuser nor BYPASSRLS' FROM pg_roles WHERE rolname='hospitalflow_app' AND(rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb)
 UNION ALL SELECT 'runtime-owned-objects','Error',count(*),'The runtime login does not own schema objects' FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_roles r ON r.oid=c.relowner WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops') AND r.rolname='hospitalflow_app'
 UNION ALL SELECT 'maintenance-worker-freshness','Warning',CASE WHEN EXISTS(SELECT 1 FROM hf_ops.worker_heartbeats WHERE worker='maintenance' AND last_seen_at>now()-interval '3 minutes' AND status<>'Failed') THEN 0 ELSE 1 END::bigint,'External scheduler heartbeat should be recent'
 UNION ALL SELECT 'backup-freshness','Warning',CASE WHEN EXISTS(SELECT 1 FROM hf_ops.backup_runs WHERE status='Succeeded' AND completed_at>now()-interval '48 hours') THEN 0 ELSE 1 END::bigint,'A successful recorded backup should be newer than 48 hours'
 UNION ALL SELECT 'restore-drill-evidence','Warning',CASE WHEN EXISTS(SELECT 1 FROM hf_ops.restore_drills WHERE outcome='Passed' AND performed_at>now()-interval '90 days') THEN 0 ELSE 1 END::bigint,'Production recovery requires a periodically evidenced restore drill'
$$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hospitalflow,hf_api,hf_security,hf_ops FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA hf_api,hf_ops FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hf_ops.validate_database() TO hospitalflow_job_runner;
COMMENT ON SCHEMA hf_api IS 'Schema-grouped operational functions and procedures: PostgreSQL package equivalent.';
COMMENT ON SCHEMA hf_reporting IS 'Read-only reporting aliases and refreshable materialized reports.';
COMMENT ON SCHEMA hf_security IS 'Trusted-backend actor validation and scoped access policies. The service must derive actor IDs from authenticated sessions.';
COMMENT ON SCHEMA hf_ops IS 'Durable maintenance schedules, job evidence, backup metadata, DDL history and readiness checks. Requires an external scheduler when pg_cron is unavailable.';
COMMENT ON TABLE hospitalflow.integration_outbox IS 'Immutable integration events containing identifiers only. No external messages are sent by database maintenance.';
COMMENT ON TABLE hospitalflow.outbox_delivery IS 'Leased delivery state with retry/backoff and dead-letter status; adapters require a separately authorized integration worker.';
COMMENT ON TABLE hospitalflow.admission_events IS 'Preserves admission/transfer/discharge reasons and actor identity; clinical text stays out of generic audit payloads.';
COMMENT ON TABLE hospitalflow.prescription_dispensations IS 'Auditable linkage between prescription, stock movement, patient invoice and dispenser.';
COMMENT ON TABLE hospitalflow.payment_reversals IS 'Append-only local accounting reversals. Does not execute an external payment-provider refund.';
COMMENT ON VIEW hf_ops.object_inventory IS 'Installed PostgreSQL object inventory; packages/synonyms are represented by grouped schemas and read-only view aliases.';

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.009_database_contract.sql','8F67E312E4690D492E63C7517294FEBBD8AA420561AB0432EEAF63453FDD50F8');

-- 010_accounts_and_roles.sql
-- Three application roles; existing job responsibilities become explicit grants.
INSERT INTO hospitalflow.roles(name) VALUES('User'),('Admin'),('Developer') ON CONFLICT DO NOTHING;
CREATE TABLE hospitalflow.user_permissions(
 user_id text NOT NULL REFERENCES hospitalflow.users(id),
 permission text NOT NULL CHECK(permission IN ('Reception','Doctor','Nurse','Pharmacist','Billing')),
 PRIMARY KEY(user_id,permission));
INSERT INTO hospitalflow.user_permissions SELECT id,role FROM hospitalflow.users WHERE role IN ('Reception','Doctor','Nurse','Pharmacist','Billing');
UPDATE hospitalflow.users SET role=CASE WHEN role='Administrator' THEN 'Admin' ELSE 'User' END WHERE role NOT IN ('User','Admin','Developer');
DELETE FROM hospitalflow.roles WHERE name NOT IN ('User','Admin','Developer');
ALTER TABLE hospitalflow.users ADD COLUMN email_confirmed boolean NOT NULL DEFAULT true;
CREATE TABLE hospitalflow.account_tokens(
 token_hash text PRIMARY KEY CHECK(length(token_hash)=64),user_id text NOT NULL REFERENCES hospitalflow.users(id),
 purpose text NOT NULL CHECK(purpose IN ('verify','reset')),expires_at timestamptz NOT NULL,consumed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX account_tokens_user ON hospitalflow.account_tokens(user_id,purpose);
CREATE TABLE hospitalflow.account_mail(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id text NOT NULL REFERENCES hospitalflow.users(id),
 encrypted_message text NOT NULL,status text NOT NULL DEFAULT 'Pending' CHECK(status IN ('Pending','Sent','Failed')),
 attempts integer NOT NULL DEFAULT 0,next_attempt_at timestamptz NOT NULL DEFAULT now(),
 created_at timestamptz NOT NULL DEFAULT now(),sent_at timestamptz,error_code text);
CREATE INDEX account_mail_due ON hospitalflow.account_mail(next_attempt_at) WHERE status='Pending';
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.user_permissions FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE FUNCTION hf_security.protect_account() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(74192301);
 IF NEW.active AND NOT NEW.email_confirmed THEN RAISE EXCEPTION 'Verify email before account approval' USING ERRCODE='23514';END IF;
 IF TG_OP='UPDATE' AND OLD.active AND OLD.role IN ('Admin','Developer') AND (NOT NEW.active OR NEW.role='User') AND
 NOT EXISTS(SELECT 1 FROM hospitalflow.users WHERE id<>OLD.id AND active AND role IN ('Admin','Developer')) THEN
 RAISE EXCEPTION 'An active full-access account must remain' USING ERRCODE='23514';END IF;
 RETURN NEW;END $$;
CREATE TRIGGER protect_account BEFORE INSERT OR UPDATE ON hospitalflow.users FOR EACH ROW EXECUTE FUNCTION hf_security.protect_account();
CREATE OR REPLACE FUNCTION hf_security.require_actor(p_roles text[]) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE u hospitalflow.users%ROWTYPE;BEGIN
 SELECT * INTO u FROM hospitalflow.users WHERE id=nullif(current_setting('hospitalflow.actor_id',true),'') AND active AND email_confirmed;
 IF NOT FOUND OR (u.role NOT IN ('Admin','Developer') AND NOT EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id AND p.permission=ANY(p_roles))) THEN
 RAISE EXCEPTION 'Active authorized application identity required' USING ERRCODE='42501';END IF;RETURN u.id;END $$;
-- Update the two existing routines containing an administrator-specific branch.
DO $$ DECLARE definition text;signature text;BEGIN
 FOREACH signature IN ARRAY ARRAY['hf_security.can_access_patient(text)','hf_api.execute(text,jsonb,uuid,text)'] LOOP
 SELECT pg_get_functiondef(signature::regprocedure) INTO definition;
 definition:=replace(definition, 'u.role=''Administrator''','u.role IN (''Admin'',''Developer'')');
 definition:=replace(definition, 'role=''Administrator''','role IN (''Admin'',''Developer'')');
 EXECUTE definition;
 END LOOP;
END $$;
REVOKE ALL ON hospitalflow.user_permissions,hospitalflow.account_tokens,hospitalflow.account_mail FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hf_security.protect_account() FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.010_accounts_and_roles.sql','9E54FFFB9884A5A9037A1FF8DB5AADF3E2E09D71BD2772B6C0BEA96C5E1BB3B1');

-- 011_patient_portal.sql
CREATE TABLE hospitalflow.patient_accounts(
 user_id text PRIMARY KEY REFERENCES hospitalflow.users(id),patient_id text NOT NULL UNIQUE REFERENCES hospitalflow.patients(id),
 must_change_password boolean NOT NULL DEFAULT true,temporary_expires_at timestamptz NOT NULL,
 invited_at timestamptz NOT NULL DEFAULT now(),activated_at timestamptz,
 CHECK((must_change_password AND activated_at IS NULL) OR (NOT must_change_password AND activated_at IS NOT NULL)));
CREATE TABLE hospitalflow.patient_login_challenges(
 token_hash text PRIMARY KEY CHECK(length(token_hash)=64),user_id text NOT NULL REFERENCES hospitalflow.patient_accounts(user_id),
 expires_at timestamptz NOT NULL,attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),consumed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX patient_challenge_user ON hospitalflow.patient_login_challenges(user_id);
CREATE TABLE hospitalflow.patient_sms(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id text NOT NULL REFERENCES hospitalflow.patient_accounts(user_id),
 encrypted_message text NOT NULL,status text NOT NULL DEFAULT 'Pending' CHECK(status IN ('Pending','Local pickup','Failed')),
 created_at timestamptz NOT NULL DEFAULT now(),completed_at timestamptz);
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.patient_accounts FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE FUNCTION hf_security.guard_patient_account() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN
 IF TG_TABLE_NAME='users' THEN
  IF EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=NEW.id) AND NEW.role<>'User' THEN RAISE EXCEPTION 'Patient accounts cannot become staff accounts' USING ERRCODE='23514';END IF;
 ELSIF TG_TABLE_NAME='user_permissions' THEN
  IF EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=NEW.user_id) THEN RAISE EXCEPTION 'Patient accounts cannot receive staff permissions' USING ERRCODE='23514';END IF;
 ELSE
  IF NOT EXISTS(SELECT 1 FROM hospitalflow.users u WHERE u.id=NEW.user_id AND u.role='User' AND NOT EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id)) THEN RAISE EXCEPTION 'Patient identity requires a dedicated limited User account' USING ERRCODE='23514';END IF;
 END IF;
 RETURN NEW;END $$;
CREATE TRIGGER patient_role_guard BEFORE UPDATE ON hospitalflow.users FOR EACH ROW EXECUTE FUNCTION hf_security.guard_patient_account();
CREATE TRIGGER patient_grant_guard BEFORE INSERT OR UPDATE ON hospitalflow.user_permissions FOR EACH ROW EXECUTE FUNCTION hf_security.guard_patient_account();
CREATE TRIGGER patient_link_guard BEFORE INSERT OR UPDATE ON hospitalflow.patient_accounts FOR EACH ROW EXECUTE FUNCTION hf_security.guard_patient_account();
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.save_patient(text,text,date,text,text)'::regprocedure) INTO definition;
 EXECUTE replace(definition,'ARRAY[''Reception'']','ARRAY[''Reception'',''Doctor'']');
 SELECT pg_get_functiondef('hf_api.execute(text,jsonb,uuid,text)'::regprocedure) INTO definition;
 EXECUTE replace(definition,'WHEN p_action IN (''patient'',''patient-update'',''appointment'',''appointment-status'',''book-follow-up'') THEN ARRAY[''Reception'']',
 'WHEN p_action IN (''patient'',''patient-update'') THEN ARRAY[''Reception'',''Doctor''] WHEN p_action IN (''appointment'',''appointment-status'',''book-follow-up'') THEN ARRAY[''Reception'']');
END $$;
REVOKE ALL ON hospitalflow.patient_accounts,hospitalflow.patient_login_challenges,hospitalflow.patient_sms FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hf_security.guard_patient_account() FROM PUBLIC;
CREATE TABLE hospitalflow.user_preferences(user_id text PRIMARY KEY REFERENCES hospitalflow.users(id),theme text NOT NULL CHECK(theme IN ('Default','Dark')),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.user_preferences FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
REVOKE ALL ON hospitalflow.user_preferences FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.011_patient_portal.sql','1CD28579F242D97D8B1C6F78E5EE2E42F84DC5ED4E3D3210CDB17F4FA1E38698');

-- 012_people_roles_and_registration.sql
INSERT INTO hospitalflow.roles(name) VALUES('Doctor'),('Nurse'),('Volunteer') ON CONFLICT DO NOTHING;
CREATE SEQUENCE hospitalflow.person_number START 1000;
CREATE FUNCTION hf_api.person_id(p_prefix text) RETURNS text LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE serial text;BEGIN IF p_prefix NOT IN ('P','D','N','V','A','DEV','U') THEN RAISE EXCEPTION 'Unknown registration type' USING ERRCODE='23514';END IF;
 serial:=nextval('hospitalflow.person_number')::text;RETURN p_prefix||'-'||lpad(serial,greatest(6,length(serial)),'0');END $$;
ALTER TABLE hospitalflow.patients ADD COLUMN registration_id text UNIQUE,ADD COLUMN email text,ADD COLUMN address text,ADD COLUMN emergency_contact text;
UPDATE hospitalflow.patients SET registration_id=hf_api.person_id('P');
UPDATE hospitalflow.patients p SET email=u.email FROM hospitalflow.patient_accounts a JOIN hospitalflow.users u ON u.id=a.user_id WHERE p.id=a.patient_id;
ALTER TABLE hospitalflow.patients ALTER COLUMN registration_id SET NOT NULL;
ALTER TABLE hospitalflow.patients ADD CONSTRAINT patient_email_format CHECK(email IS NULL OR(length(email)<=150 AND email=lower(trim(email)) AND email~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'));
CREATE UNIQUE INDEX patient_email_unique ON hospitalflow.patients(lower(email)) WHERE email IS NOT NULL;
ALTER TABLE hospitalflow.patients ADD CONSTRAINT patient_contact_lengths CHECK((address IS NULL OR length(address)<=1000) AND(emergency_contact IS NULL OR length(emergency_contact)<=200));
ALTER TABLE hospitalflow.doctors ADD COLUMN registration_id text UNIQUE;
UPDATE hospitalflow.doctors SET registration_id=hf_api.person_id('D');
ALTER TABLE hospitalflow.doctors ALTER COLUMN registration_id SET NOT NULL;
UPDATE hospitalflow.users u SET role=CASE WHEN EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id AND permission='Doctor') THEN 'Doctor' ELSE 'Nurse' END
 WHERE role='User' AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts a WHERE a.user_id=u.id) AND EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id AND permission IN ('Doctor','Nurse'));
ALTER TABLE hospitalflow.users ADD COLUMN registration_id text UNIQUE;
UPDATE hospitalflow.users SET registration_id=hf_api.person_id(CASE role WHEN 'Admin' THEN 'A' WHEN 'Developer' THEN 'DEV' WHEN 'Doctor' THEN 'D' WHEN 'Nurse' THEN 'N' WHEN 'Volunteer' THEN 'V' ELSE 'U' END);
UPDATE hospitalflow.users u SET registration_id=p.registration_id FROM hospitalflow.patient_accounts a JOIN hospitalflow.patients p ON p.id=a.patient_id WHERE u.id=a.user_id;
ALTER TABLE hospitalflow.users ALTER COLUMN registration_id SET NOT NULL;
CREATE TABLE hospitalflow.person_profiles(
 user_id text PRIMARY KEY REFERENCES hospitalflow.users(id),doctor_id text UNIQUE REFERENCES hospitalflow.doctors(id),
 mobile text CHECK(mobile IS NULL OR mobile~'^\+[0-9]{7,15}$'),dob date CHECK(dob>=date '1900-01-01'),
 sex text CHECK(sex IN ('Male','Female','Other','Prefer not to say')),address text CHECK(length(address)<=1000),
 department text REFERENCES hospitalflow.departments(name),job_title text CHECK(length(job_title)<=100),
 occupation text CHECK(occupation IN ('Guard','Washerman','Housekeeping','Other')),created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
INSERT INTO hospitalflow.person_profiles(user_id) SELECT id FROM hospitalflow.users WHERE NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts a WHERE a.user_id=users.id);
CREATE FUNCTION hf_security.registration_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE prefix text;expected text;BEGIN
 IF TG_TABLE_NAME='patients' THEN prefix:='P';
 ELSIF TG_TABLE_NAME='doctors' THEN prefix:='D';
 ELSE prefix:=CASE NEW.role WHEN 'Admin' THEN 'A' WHEN 'Developer' THEN 'DEV' WHEN 'Doctor' THEN 'D' WHEN 'Nurse' THEN 'N' WHEN 'Volunteer' THEN 'V' ELSE 'U' END;
  IF TG_OP='UPDATE' AND OLD.role<>NEW.role THEN NEW.registration_id:=hf_api.person_id(prefix);END IF;
  SELECT p.registration_id INTO expected FROM hospitalflow.patient_accounts a JOIN hospitalflow.patients p ON p.id=a.patient_id WHERE a.user_id=NEW.id;
  IF expected IS NOT NULL THEN IF NEW.registration_id IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Patient and account registration IDs must match' USING ERRCODE='23514';END IF;prefix:='P';END IF;
 END IF;
 IF NEW.registration_id IS NULL THEN NEW.registration_id:=hf_api.person_id(prefix);END IF;
 IF TG_OP='UPDATE' AND TG_TABLE_NAME IN ('patients','doctors') AND OLD.registration_id<>NEW.registration_id THEN RAISE EXCEPTION 'Registration ID is immutable' USING ERRCODE='23514';END IF;
 IF NEW.registration_id!~('^'||prefix||'-[0-9]+$') THEN RAISE EXCEPTION 'Invalid registration prefix' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER registration_identity BEFORE INSERT OR UPDATE ON hospitalflow.patients FOR EACH ROW EXECUTE FUNCTION hf_security.registration_identity();
CREATE TRIGGER registration_identity BEFORE INSERT OR UPDATE ON hospitalflow.doctors FOR EACH ROW EXECUTE FUNCTION hf_security.registration_identity();
CREATE TRIGGER registration_identity BEFORE INSERT OR UPDATE ON hospitalflow.users FOR EACH ROW EXECUTE FUNCTION hf_security.registration_identity();
CREATE FUNCTION hospitalflow.sync_patient_registration() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN UPDATE hospitalflow.users SET registration_id=(SELECT registration_id FROM hospitalflow.patients WHERE id=NEW.patient_id) WHERE id=NEW.user_id;RETURN NEW;END $$;
CREATE TRIGGER sync_registration AFTER INSERT ON hospitalflow.patient_accounts FOR EACH ROW EXECUTE FUNCTION hospitalflow.sync_patient_registration();
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.person_profiles FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE FUNCTION hf_security.validate_person_profile() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF NEW.dob>current_date THEN RAISE EXCEPTION 'Date of birth cannot be in the future' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER validate_profile BEFORE INSERT OR UPDATE ON hospitalflow.person_profiles FOR EACH ROW EXECUTE FUNCTION hf_security.validate_person_profile();
CREATE OR REPLACE FUNCTION hf_security.require_actor(p_roles text[]) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE u hospitalflow.users%ROWTYPE;BEGIN
 SELECT * INTO u FROM hospitalflow.users WHERE id=nullif(current_setting('hospitalflow.actor_id',true),'') AND active AND email_confirmed;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id) OR u.role='Volunteer' OR
 (u.role NOT IN ('Admin','Developer') AND NOT(u.role=ANY(p_roles)) AND NOT EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id AND p.permission=ANY(p_roles))) THEN
 RAISE EXCEPTION 'Active authorized staff identity required' USING ERRCODE='42501';END IF;RETURN u.id;END $$;
CREATE OR REPLACE FUNCTION hf_security.protect_account() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);
 IF NEW.active AND NOT NEW.email_confirmed THEN RAISE EXCEPTION 'Verify email before account approval' USING ERRCODE='23514';END IF;
 IF TG_OP='UPDATE' AND OLD.active AND OLD.role IN ('Admin','Developer') AND (NOT NEW.active OR NEW.role NOT IN ('Admin','Developer')) AND NOT EXISTS(SELECT 1 FROM hospitalflow.users WHERE id<>OLD.id AND active AND role IN ('Admin','Developer')) THEN RAISE EXCEPTION 'An active full-access account must remain' USING ERRCODE='23514';END IF;
 RETURN NEW;END $$;
-- Name/contact updates cannot silently move a linked login to another email.
CREATE FUNCTION hf_security.patient_email_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF EXISTS(SELECT 1 FROM hospitalflow.patient_accounts a JOIN hospitalflow.users u ON u.id=a.user_id WHERE a.patient_id=NEW.id AND u.email IS DISTINCT FROM NEW.email) THEN RAISE EXCEPTION 'Linked patient email requires identity-reviewed account change' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER linked_email BEFORE UPDATE OF email ON hospitalflow.patients FOR EACH ROW EXECUTE FUNCTION hf_security.patient_email_guard();
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.save_patient(text,text,date,text,text)'::regprocedure) INTO definition;
 definition:=replace(definition,'INSERT INTO hospitalflow.patients VALUES(', 'INSERT INTO hospitalflow.patients(id,name,dob,sex,phone,created) VALUES(');EXECUTE definition;
 SELECT pg_get_functiondef('hf_api.execute(text,jsonb,uuid,text)'::regprocedure) INTO definition;
 definition:=replace(definition,' WHEN ''doctor'' THEN',' UPDATE hospitalflow.patients SET email=COALESCE(p_payload->>''email'',email),address=COALESCE(p_payload->>''address'',address),emergency_contact=COALESCE(p_payload->>''emergencyContact'',emergency_contact) WHERE id=result; WHEN ''doctor'' THEN');
 EXECUTE definition;
END $$;
REVOKE EXECUTE ON FUNCTION hf_api.person_id(text),hf_security.registration_identity(),hf_security.validate_person_profile(),hf_security.patient_email_guard(),hospitalflow.sync_patient_registration() FROM PUBLIC;
REVOKE ALL ON hospitalflow.person_profiles FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.012_people_roles_and_registration.sql','FA08BE18E18A8A15C7FA62BD2B5AC47C39E7B176104150943E46812ED233B9FE');

-- 013_role_workspaces.sql
CREATE TABLE hospitalflow.email_changes(
 token_hash text PRIMARY KEY,user_id text NOT NULL REFERENCES hospitalflow.users(id),
 email text NOT NULL,password_fingerprint text NOT NULL CHECK(length(password_fingerprint)=64),expires_at timestamptz NOT NULL,consumed_at timestamptz,created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX email_changes_user ON hospitalflow.email_changes(user_id,created_at);
CREATE TABLE hospitalflow.work_tasks(
 id text PRIMARY KEY,assigned_to text NOT NULL REFERENCES hospitalflow.users(id),created_by text NOT NULL REFERENCES hospitalflow.users(id),
 title text NOT NULL CHECK(length(title) BETWEEN 2 AND 150),location text NOT NULL CHECK(length(location) BETWEEN 1 AND 150),
 due_at timestamptz NOT NULL,status text NOT NULL DEFAULT 'Assigned' CHECK(status IN ('Assigned','In progress','Completed')),
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX work_tasks_assignee ON hospitalflow.work_tasks(assigned_to,due_at);
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.work_tasks FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
REVOKE ALL ON hospitalflow.email_changes,hospitalflow.work_tasks FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.013_role_workspaces.sql','9AFD8640C0C031930236C14FE53C5A9F19400FAFFEE7A2C84626F5F54BA1E911');

-- 014_mobile_validation.sql
-- Existing Indian E.164 values retain their exact subscriber number.
ALTER TABLE hospitalflow.person_profiles DROP CONSTRAINT person_profiles_mobile_check;
UPDATE hospitalflow.patients SET phone=substring(phone FROM 4) WHERE phone~'^\+91[0-9]{10}$';
UPDATE hospitalflow.person_profiles SET mobile=substring(mobile FROM 4) WHERE mobile~'^\+91[0-9]{10}$';
UPDATE hospitalflow.patient_contacts SET phone=substring(phone FROM 4) WHERE phone~'^\+91[0-9]{10}$';
UPDATE hospitalflow.suppliers SET contact_phone=substring(contact_phone FROM 4) WHERE contact_phone~'^\+91[0-9]{10}$';
ALTER TABLE hospitalflow.patients ADD CONSTRAINT patient_mobile_ten_digits CHECK(phone~'^[0-9]{10}$');
ALTER TABLE hospitalflow.person_profiles ADD CONSTRAINT profile_mobile_ten_digits CHECK(mobile IS NULL OR mobile~'^[0-9]{10}$');
ALTER TABLE hospitalflow.patient_contacts ADD CONSTRAINT contact_mobile_ten_digits CHECK(phone~'^[0-9]{10}$');
ALTER TABLE hospitalflow.suppliers ADD CONSTRAINT supplier_mobile_ten_digits CHECK(contact_phone IS NULL OR contact_phone~'^[0-9]{10}$');

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.014_mobile_validation.sql','B24A68B98DEC0C76AF57D007745C9D479130183E271DDCEADCE09D12D382B839');

-- 015_hospital_network.sql
CREATE TABLE hospitalflow.hospitals(id text PRIMARY KEY,name text NOT NULL CHECK(length(name) BETWEEN 2 AND 150),address text NOT NULL,city text NOT NULL,state text NOT NULL,postal_code text NOT NULL,active boolean NOT NULL DEFAULT true,accepting_referrals boolean NOT NULL DEFAULT true,is_demo boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT now());
INSERT INTO hospitalflow.hospitals(id,name,address,city,state,postal_code) SELECT 'H-0001',name,'Address not configured','Not configured','Not configured','Not configured' FROM hospitalflow.hospital_profile;
CREATE FUNCTION hf_security.current_hospital() RETURNS text LANGUAGE sql STABLE AS $$ SELECT COALESCE(NULLIF(current_setting('hospitalflow.hospital_id',true),''),'H-0001') $$;
CREATE TABLE hospitalflow.hospital_memberships(user_id text NOT NULL REFERENCES hospitalflow.users(id),hospital_id text NOT NULL REFERENCES hospitalflow.hospitals(id),active boolean NOT NULL DEFAULT true,created_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(user_id,hospital_id));
CREATE TABLE hospitalflow.network_operators(user_id text PRIMARY KEY REFERENCES hospitalflow.users(id));
INSERT INTO hospitalflow.hospital_memberships SELECT id,'H-0001',true,now() FROM hospitalflow.users;
INSERT INTO hospitalflow.network_operators SELECT id FROM hospitalflow.users WHERE active AND role IN ('Admin','Developer') ORDER BY created_at,id LIMIT 1;
ALTER TABLE hospitalflow.user_preferences ADD COLUMN hospital_id text REFERENCES hospitalflow.hospitals(id);
CREATE TABLE hospitalflow.patient_hospitals(patient_id text NOT NULL REFERENCES hospitalflow.patients(id),hospital_id text NOT NULL REFERENCES hospitalflow.hospitals(id),registered_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(patient_id,hospital_id));
INSERT INTO hospitalflow.patient_hospitals SELECT id,'H-0001',created FROM hospitalflow.patients;
CREATE FUNCTION hf_security.auto_hospital_member() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$ BEGIN
 IF TG_TABLE_NAME='users' THEN
 INSERT INTO hospitalflow.hospital_memberships(user_id,hospital_id) VALUES(NEW.id,hf_security.current_hospital());
 IF NEW.role IN ('Admin','Developer') AND NOT EXISTS(SELECT 1 FROM hospitalflow.network_operators) THEN INSERT INTO hospitalflow.network_operators VALUES(NEW.id);END IF;
 ELSE INSERT INTO hospitalflow.patient_hospitals(patient_id,hospital_id) VALUES(NEW.id,NEW.hospital_id);END IF;RETURN NEW;END $$;
CREATE TRIGGER auto_hospital AFTER INSERT ON hospitalflow.users FOR EACH ROW EXECUTE FUNCTION hf_security.auto_hospital_member();
CREATE FUNCTION hf_security.own_patient(p_patient text) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT p_patient IS NOT NULL AND p_patient=NULLIF(current_setting('hospitalflow.patient_id',true),'') $$;
CREATE FUNCTION hf_security.enrolled_patient(p_patient text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$ SELECT EXISTS(SELECT 1 FROM hospitalflow.patient_hospitals WHERE patient_id=p_patient AND hospital_id=hf_security.current_hospital()) $$;
CREATE FUNCTION hf_security.own_related(p_kind text,p_id text) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$ BEGIN
 IF nullif(current_setting('hospitalflow.patient_id',true),'') IS NULL THEN RETURN false;END IF;
 IF p_kind='bill' THEN RETURN EXISTS(SELECT 1 FROM hospitalflow.bills WHERE id=p_id AND hf_security.own_patient(patient_id));
 ELSIF p_kind='payment' THEN RETURN EXISTS(SELECT 1 FROM hospitalflow.payments p JOIN hospitalflow.bills b ON b.id=p.bill_id WHERE p.id=p_id AND hf_security.own_patient(b.patient_id));
 ELSIF p_kind='doctor' THEN RETURN EXISTS(SELECT 1 FROM hospitalflow.appointments WHERE doctor_id=p_id AND hf_security.own_patient(patient_id));
 ELSIF p_kind='medicine' THEN RETURN EXISTS(SELECT 1 FROM hospitalflow.prescriptions WHERE medicine_id=p_id AND hf_security.own_patient(patient_id));END IF;RETURN false;END $$;
-- Every operational row has a hospital fence. Global authentication and shared taxonomy stay separate.
DO $$ DECLARE t text;scope text;already boolean;BEGIN
 FOREACH t IN ARRAY ARRAY['patients','doctors','appointments','beds','admissions','bed_assignments','medicine_batches','prescriptions','stock_movements','bills','bill_lines','payments','notes','staff_members','user_departments','patient_access_grants','patient_contacts','patient_consents','provider_absences','provider_sessions','encounters','service_catalog','service_prices','invoice_line_context','payment_reversals','clinical_orders','discharge_tasks','follow_ups','suppliers','purchase_orders','purchase_order_lines','goods_receipts','goods_receipt_lines','medicine_batch_holds','stock_reservations','prescription_dispensations','notification_acknowledgements','prescription_authors','admission_events','notifications','activity_log','row_history','idempotency_keys','work_tasks','integration_outbox','outbox_delivery'] LOOP
 EXECUTE format('ALTER TABLE hospitalflow.%I ADD COLUMN hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id)',t);
 EXECUTE format('CREATE INDEX ON hospitalflow.%I(hospital_id)',t);
 SELECT relrowsecurity INTO already FROM pg_class WHERE oid=('hospitalflow.'||t)::regclass;
 scope:='hospital_id=hf_security.current_hospital()';
 IF t='patients' THEN scope:='CASE WHEN nullif(current_setting(''hospitalflow.patient_id'',true),'''') IS NOT NULL THEN hf_security.own_patient(id) ELSE hospital_id=hf_security.current_hospital() OR hf_security.enrolled_patient(id) END';
 ELSIF t IN ('appointments','admissions','prescriptions','bills') THEN scope:='CASE WHEN nullif(current_setting(''hospitalflow.patient_id'',true),'''') IS NOT NULL THEN hf_security.own_patient(patient_id) ELSE hospital_id=hf_security.current_hospital() END';
 ELSIF t IN ('bill_lines','payments') THEN scope:='CASE WHEN nullif(current_setting(''hospitalflow.patient_id'',true),'''') IS NOT NULL THEN hf_security.own_related(''bill'',bill_id) ELSE hospital_id=hf_security.current_hospital() END';
 ELSIF t='payment_reversals' THEN scope:='CASE WHEN nullif(current_setting(''hospitalflow.patient_id'',true),'''') IS NOT NULL THEN hf_security.own_related(''payment'',payment_id) ELSE hospital_id=hf_security.current_hospital() END';
 ELSIF t='doctors' THEN scope:='CASE WHEN nullif(current_setting(''hospitalflow.patient_id'',true),'''') IS NOT NULL THEN hf_security.own_related(''doctor'',id) ELSE hospital_id=hf_security.current_hospital() END';
 ELSIF t='medicine_batches' THEN scope:='CASE WHEN nullif(current_setting(''hospitalflow.patient_id'',true),'''') IS NOT NULL THEN hf_security.own_related(''medicine'',id) ELSE hospital_id=hf_security.current_hospital() END';
 ELSIF t='activity_log' THEN scope:=scope||' AND (nullif(current_setting(''hospitalflow.patient_id'',true),'''') IS NULL OR actor_id=nullif(current_setting(''hospitalflow.actor_id'',true),''''))';
 ELSE scope:=scope||' AND nullif(current_setting(''hospitalflow.patient_id'',true),'''') IS NULL';END IF;
 EXECUTE format('ALTER TABLE hospitalflow.%I ENABLE ROW LEVEL SECURITY',t);
 IF already THEN EXECUTE format('CREATE POLICY hospital_fence ON hospitalflow.%I AS RESTRICTIVE USING (%s) WITH CHECK(hospital_id=hf_security.current_hospital())',t,scope);
 ELSE EXECUTE format('CREATE POLICY hospital_fence ON hospitalflow.%I USING (%s) WITH CHECK(%s)',t,scope,CASE WHEN t='patients' THEN scope ELSE 'hospital_id=hf_security.current_hospital()' END);END IF;
 END LOOP;
END $$;
CREATE TRIGGER auto_hospital AFTER INSERT ON hospitalflow.patients FOR EACH ROW EXECUTE FUNCTION hf_security.auto_hospital_member();
CREATE FUNCTION hf_security.guard_hospital_row() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$
DECLARE doc jsonb;f record;parent_hospital text;ref text;BEGIN
 doc:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF TG_OP='UPDATE' AND NEW.hospital_id<>OLD.hospital_id THEN RAISE EXCEPTION 'Hospital ownership is immutable' USING ERRCODE='23514';END IF;
 IF doc->>'hospital_id'<>hf_security.current_hospital() AND NOT(pg_has_role(session_user,'hospitalflow_job_runner','member') AND nullif(current_setting('hospitalflow.actor_id',true),'') IS NULL) AND NOT(TG_TABLE_NAME='patients' AND (hf_security.enrolled_patient(doc->>'id') OR hf_security.own_patient(doc->>'id'))) THEN RAISE EXCEPTION 'Record belongs to another hospital' USING ERRCODE='42501';END IF;
 IF TG_OP<>'DELETE' THEN
 ref:=COALESCE(doc->>'assigned_to',doc->>'user_id');
 IF ref IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships WHERE user_id=ref AND hospital_id=doc->>'hospital_id' AND active) AND NOT EXISTS(SELECT 1 FROM hospitalflow.network_operators WHERE user_id=ref) AND NOT EXISTS(SELECT 1 FROM hospitalflow.users WHERE id=ref AND role='Developer') THEN RAISE EXCEPTION 'Person is not assigned to this hospital' USING ERRCODE='42501';END IF;
 FOR f IN SELECT n.nspname,c.relname,a.attname target_col,src.attname source_col FROM pg_constraint fk JOIN pg_class c ON c.oid=fk.confrelid JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=fk.confkey[1] JOIN pg_attribute src ON src.attrelid=fk.conrelid AND src.attnum=fk.conkey[1] WHERE fk.contype='f' AND fk.conrelid=TG_RELID AND array_length(fk.conkey,1)=1 AND n.nspname='hospitalflow' AND EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=c.oid AND attname='hospital_id') LOOP
 ref:=doc->>f.source_col;IF ref IS NULL THEN CONTINUE;END IF;
 IF f.relname='patients' THEN IF NOT hf_security.enrolled_patient(ref) AND NOT hf_security.own_patient(ref) THEN RAISE EXCEPTION 'Patient is not registered at this hospital' USING ERRCODE='42501';END IF;
 ELSE EXECUTE format('SELECT hospital_id FROM %I.%I WHERE %I::text=$1',f.nspname,f.relname,f.target_col) INTO parent_hospital USING ref;
 IF parent_hospital IS NOT NULL AND parent_hospital<>doc->>'hospital_id' THEN RAISE EXCEPTION 'Cross-hospital reference is not allowed' USING ERRCODE='42501';END IF;END IF;
 END LOOP;END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;END $$;
DO $$ DECLARE t record;BEGIN FOR t IN SELECT table_name FROM information_schema.columns WHERE table_schema='hospitalflow' AND column_name='hospital_id' AND table_name NOT IN ('hospital_memberships','patient_hospitals','user_preferences') LOOP
 EXECUTE format('CREATE TRIGGER z_hospital_guard BEFORE INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hf_security.guard_hospital_row()',t.table_name);END LOOP;
 FOR t IN SELECT schemaname,viewname FROM pg_views WHERE schemaname IN ('hospitalflow','hf_reporting','hf_api') LOOP EXECUTE format('ALTER VIEW %I.%I SET(security_invoker=true)',t.schemaname,t.viewname);END LOOP;
END $$;
-- Secure native mutations even where a SECURITY DEFINER helper bypasses SELECT RLS.
DO $$ DECLARE d text;BEGIN SELECT pg_get_functiondef('hf_security.require_actor(text[])'::regprocedure) INTO d;
 d:=replace(d,'IF NOT FOUND OR','IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships m WHERE m.user_id=u.id AND m.hospital_id=hf_security.current_hospital() AND m.active) AND u.role<>''Developer'' AND NOT EXISTS(SELECT 1 FROM hospitalflow.network_operators o WHERE o.user_id=u.id) OR');EXECUTE d;END $$;
CREATE TABLE hospitalflow.referrals(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),source_hospital_id text NOT NULL REFERENCES hospitalflow.hospitals(id),target_hospital_id text NOT NULL REFERENCES hospitalflow.hospitals(id),target_doctor_id text REFERENCES hospitalflow.doctors(id),referred_by text NOT NULL REFERENCES hospitalflow.users(id),reason text NOT NULL CHECK(length(trim(reason)) BETWEEN 5 AND 2000),status text NOT NULL DEFAULT 'Pending' CHECK(status IN ('Pending','Accepted','Declined','Cancelled')),created_at timestamptz NOT NULL DEFAULT now(),resolved_at timestamptz,resolved_by text REFERENCES hospitalflow.users(id),resolution_note text,CHECK(source_hospital_id<>target_hospital_id));
CREATE UNIQUE INDEX referral_pending_unique ON hospitalflow.referrals(patient_id,source_hospital_id,target_hospital_id) WHERE status='Pending';
CREATE INDEX referral_source ON hospitalflow.referrals(source_hospital_id,created_at);
CREATE INDEX referral_target ON hospitalflow.referrals(target_hospital_id,created_at);
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.referrals FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.hospital_memberships FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.patient_hospitals FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.hospitals FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
ALTER TABLE hospitalflow.referrals ENABLE ROW LEVEL SECURITY;
CREATE POLICY referral_scope ON hospitalflow.referrals USING(CASE WHEN nullif(current_setting('hospitalflow.patient_id',true),'') IS NOT NULL THEN hf_security.own_patient(patient_id) ELSE source_hospital_id=hf_security.current_hospital() OR target_hospital_id=hf_security.current_hospital() END) WITH CHECK(source_hospital_id=hf_security.current_hospital() OR target_hospital_id=hf_security.current_hospital());
CREATE FUNCTION hf_security.directory_providers() RETURNS TABLE(id text,hospital_id text,registration_id text,name text,department text,shift_start time,shift_end time) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ SELECT d.id,d.hospital_id,d.registration_id,d.name,d.department,d.start,d."end" FROM hospitalflow.doctors d WHERE d.active $$;
-- These twenty fictional directory entries are explicitly labelled demonstration data.
INSERT INTO hospitalflow.departments(name) VALUES('General Medicine'),('Cardiology'),('Orthopaedics'),('Paediatrics') ON CONFLICT DO NOTHING;
DO $$ DECLARE i integer;cities text[]:=ARRAY['Bengaluru','Mumbai','New Delhi','Chennai','Hyderabad','Pune','Kolkata','Ahmedabad','Jaipur','Lucknow','Kochi','Chandigarh','Bhopal','Indore','Nagpur','Coimbatore','Patna','Bhubaneswar','Visakhapatnam','Mysuru'];states text[]:=ARRAY['Karnataka','Maharashtra','Delhi','Tamil Nadu','Telangana','Maharashtra','West Bengal','Gujarat','Rajasthan','Uttar Pradesh','Kerala','Chandigarh','Madhya Pradesh','Madhya Pradesh','Maharashtra','Tamil Nadu','Bihar','Odisha','Andhra Pradesh','Karnataka'];codes text[]:=ARRAY['560001','400001','110001','600001','500001','411001','700001','380001','302001','226001','682001','160001','462001','452001','440001','641001','800001','751001','530001','570001'];hid text;previous text:=hf_security.current_hospital();BEGIN
 FOR i IN 1..20 LOOP hid:='H-'||lpad((i+1)::text,4,'0');
 INSERT INTO hospitalflow.hospitals(id,name,address,city,state,postal_code,is_demo) VALUES(hid,'Demo '||cities[i]||' Care Hospital',i||' Example Health Avenue, Demonstration District',cities[i],states[i],codes[i],true);
 PERFORM set_config('hospitalflow.hospital_id',hid,true);
 INSERT INTO hospitalflow.doctors(id,name,department,start,"end",hospital_id) VALUES('NET-DR-'||i||'A','Demo Dr. Asha '||i,'General Medicine','09:00','17:00',hid),('NET-DR-'||i||'B','Demo Dr. Vikram '||i,CASE i%3 WHEN 0 THEN 'Paediatrics' WHEN 1 THEN 'Cardiology' ELSE 'Orthopaedics' END,'10:00','18:00',hid);
 END LOOP;PERFORM set_config('hospitalflow.hospital_id',previous,true);END $$;
REVOKE ALL ON hospitalflow.hospitals,hospitalflow.hospital_memberships,hospitalflow.network_operators,hospitalflow.patient_hospitals,hospitalflow.referrals FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA hf_security FROM PUBLIC;
CREATE FUNCTION hf_security.referral_patient_identity() RETURNS TABLE(id text,name text,registration_id text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$
 SELECT p.id,p.name,p.registration_id FROM hospitalflow.patients p WHERE EXISTS(SELECT 1 FROM hospitalflow.referrals r WHERE r.patient_id=p.id AND (CASE WHEN nullif(current_setting('hospitalflow.patient_id',true),'') IS NOT NULL THEN hf_security.own_patient(r.patient_id) ELSE r.source_hospital_id=hf_security.current_hospital() OR r.target_hospital_id=hf_security.current_hospital() END)) $$;
REVOKE EXECUTE ON FUNCTION hf_security.referral_patient_identity() FROM PUBLIC;
-- Alert generation must attach each alert to the source hospital, including background refreshes.
CREATE OR REPLACE PROCEDURE hf_ops.refresh_alerts() LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_ops,hf_security,pg_temp AS $$
DECLARE h record;v_alerts jsonb;previous text:=hf_security.current_hospital();BEGIN PERFORM pg_advisory_xact_lock(74192301);
 FOR h IN SELECT id FROM hospitalflow.hospitals LOOP
 PERFORM set_config('hospitalflow.hospital_id',h.id,true);
 SELECT COALESCE(jsonb_agg(to_jsonb(a)),'[]'::jsonb) INTO v_alerts FROM(
 SELECT 'low-stock'::text rule,id reference,'Low stock needs attention'::text title,name||': '||quantity||' units remaining (reorder at '||reorder||').' message,'pharmacy'::text target FROM hospitalflow.medicine_batches WHERE hospital_id=h.id AND quantity<=reorder
 UNION ALL SELECT 'expiry',id,'Medicine approaching expiry',name||' · '||batch||' · '||expiry,'pharmacy' FROM hospitalflow.medicine_batches WHERE hospital_id=h.id AND expiry<=hf_api.hospital_today()+30
 UNION ALL SELECT 'cleaning',id,'Bed awaiting turnaround',id||' needs cleaning confirmation before reuse.','beds' FROM hospitalflow.beds WHERE hospital_id=h.id AND status='Cleaning'
 UNION ALL SELECT 'queue',id,'Queue waiting time','A checked-in appointment has waited over 30 minutes.','appointments' FROM hospitalflow.appointments WHERE hospital_id=h.id AND status='Checked in' AND checked_in<now()-interval '30 minutes')a;
 UPDATE hospitalflow.notifications n SET resolved_at=now() WHERE hospital_id=h.id AND resolved_at IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_to_recordset(v_alerts) a(rule text,reference text) WHERE a.rule=n.rule AND a.reference=n.reference);
 INSERT INTO hospitalflow.notifications(id,rule,reference,title,message,target) SELECT gen_random_uuid()::text,rule,reference,title,message,target FROM jsonb_to_recordset(v_alerts) a(rule text,reference text,title text,message text,target text) ON CONFLICT(rule,reference) WHERE resolved_at IS NULL DO UPDATE SET message=EXCLUDED.message,title=EXCLUDED.title;
 END LOOP;PERFORM set_config('hospitalflow.hospital_id',previous,true);END $$;
ALTER TABLE hospitalflow.medicine_batches DROP CONSTRAINT medicine_batches_name_batch_key,ADD UNIQUE(hospital_id,name,batch);
ALTER TABLE hospitalflow.suppliers DROP CONSTRAINT suppliers_code_key,ADD UNIQUE(hospital_id,code);
ALTER TABLE hospitalflow.service_catalog DROP CONSTRAINT service_catalog_code_key,ADD UNIQUE(hospital_id,code);
ALTER TABLE hospitalflow.staff_members DROP CONSTRAINT staff_members_employee_number_key,ADD UNIQUE(hospital_id,employee_number);
ALTER TABLE hospitalflow.prescriptions ADD COLUMN created_at timestamptz;
UPDATE hospitalflow.prescriptions p SET created_at=a.created_at FROM hospitalflow.prescription_authors a WHERE a.prescription_id=p.id;
ALTER TABLE hospitalflow.prescriptions ALTER COLUMN created_at SET DEFAULT now();
CREATE OR REPLACE FUNCTION hf_security.can_access_patient(p_patient text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM hospitalflow.users u WHERE u.id=nullif(current_setting('hospitalflow.actor_id',true),'') AND u.active AND
 (EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships m WHERE m.user_id=u.id AND m.hospital_id=hf_security.current_hospital() AND m.active) OR u.role='Developer' OR EXISTS(SELECT 1 FROM hospitalflow.network_operators o WHERE o.user_id=u.id)) AND
 (u.role IN ('Admin','Developer') OR EXISTS(SELECT 1 FROM hospitalflow.patient_access_grants g WHERE g.user_id=u.id AND g.hospital_id=hf_security.current_hospital() AND g.patient_id=p_patient AND g.expires_at>now()) OR
 EXISTS(SELECT 1 FROM hospitalflow.admissions a JOIN hospitalflow.beds b ON b.id=a.bed_id JOIN hospitalflow.wards w ON w.name=b.ward JOIN hospitalflow.user_departments d ON d.department=w.department AND d.hospital_id=hf_security.current_hospital() WHERE a.patient_id=p_patient AND a.hospital_id=hf_security.current_hospital() AND a.status='Admitted' AND d.user_id=u.id))) $$;
REVOKE EXECUTE ON FUNCTION hf_security.can_access_patient(text) FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.015_hospital_network.sql','806FD0ABE1E5D2511F6C753E1580BCE217B9B1ED4EF4B880E77907FA8371C495');

-- 016_booking_and_attendance.sql
-- Booking fees are unset until a hospital administrator configures them.
CREATE TABLE hospitalflow.booking_settings(hospital_id text PRIMARY KEY REFERENCES hospitalflow.hospitals(id),fee numeric(12,2) NOT NULL CHECK(fee>=200 AND fee<=750),updated_at timestamptz NOT NULL DEFAULT now());
INSERT INTO hospitalflow.booking_settings(hospital_id,fee) SELECT id,200 FROM hospitalflow.hospitals;
CREATE TABLE hospitalflow.appointment_bookings(
 id uuid PRIMARY KEY, hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),
 patient_id text NOT NULL REFERENCES hospitalflow.patients(id),doctor_id text NOT NULL REFERENCES hospitalflow.doctors(id),
 at timestamptz NOT NULL,visit_type text NOT NULL CHECK(visit_type IN ('Consultation','Follow-up','Review')),
 amount numeric(12,2) NOT NULL CHECK(amount>0),method text NOT NULL CHECK(method IN ('UPI','Netbanking','Card','QR','Cash')),
 state text NOT NULL DEFAULT 'Pending' CHECK(state IN ('Pending','Paid','Expired','Cancelled','Refund pending','Refunded')),
 payment_mode text NOT NULL CHECK(payment_mode IN ('Test','Cash','Disabled')),
 appointment_id text UNIQUE REFERENCES hospitalflow.appointments(id),created_by text NOT NULL REFERENCES hospitalflow.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),expires_at timestamptz NOT NULL DEFAULT now()+interval '10 minutes',paid_at timestamptz,refunded_at timestamptz);
CREATE INDEX booking_slot ON hospitalflow.appointment_bookings(hospital_id,doctor_id,at) WHERE state='Pending';
CREATE TABLE hospitalflow.booking_events(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,booking_id uuid NOT NULL REFERENCES hospitalflow.appointment_bookings(id),event text NOT NULL,actor_id text NOT NULL REFERENCES hospitalflow.users(id),at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.staff_attendance(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),user_id text NOT NULL REFERENCES hospitalflow.users(id),day date NOT NULL,status text NOT NULL CHECK(status IN ('Present','Absent')),check_in timestamptz,check_out timestamptz,marked_by text NOT NULL REFERENCES hospitalflow.users(id),UNIQUE(hospital_id,user_id,day),CHECK(check_out IS NULL OR check_out>=check_in));
CREATE TABLE hospitalflow.staff_leaves(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),user_id text NOT NULL REFERENCES hospitalflow.users(id),starts_on date NOT NULL,ends_on date NOT NULL,reason text NOT NULL CHECK(length(reason) BETWEEN 5 AND 500),status text NOT NULL DEFAULT 'Pending' CHECK(status IN ('Pending','Approved','Rejected','Cancelled')),created_at timestamptz NOT NULL DEFAULT now(),resolved_by text REFERENCES hospitalflow.users(id),CHECK(ends_on>=starts_on AND ends_on-starts_on<=90));
DO $$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['booking_settings','appointment_bookings','staff_attendance','staff_leaves'] LOOP
 EXECUTE format('ALTER TABLE hospitalflow.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('CREATE POLICY hospital_fence ON hospitalflow.%I USING(hospital_id=hf_security.current_hospital()) WITH CHECK(hospital_id=hf_security.current_hospital())',t);
 EXECUTE format('CREATE TRIGGER z_hospital_guard BEFORE INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hf_security.guard_hospital_row()',t);
 IF t<>'booking_settings' THEN EXECUTE format('CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history()',t);END IF;
 END LOOP;END $$;
-- No direct table writes for runtime: mutations go through the authorised command below.
REVOKE ALL ON hospitalflow.booking_settings,hospitalflow.appointment_bookings,hospitalflow.booking_events,hospitalflow.staff_attendance,hospitalflow.staff_leaves FROM PUBLIC;
CREATE FUNCTION hf_api.doctor_unavailable(p_doctor text,p_at timestamptz) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM hospitalflow.provider_absences WHERE doctor_id=p_doctor AND hospital_id=hf_security.current_hospital() AND cancelled_at IS NULL AND starts_at<p_at+interval '10 minutes' AND ends_at>p_at)
 OR EXISTS(SELECT 1 FROM (SELECT user_id,doctor_id FROM hospitalflow.person_profiles UNION SELECT user_id,doctor_id FROM hospitalflow.staff_members WHERE active AND hospital_id=hf_security.current_hospital()) p JOIN hospitalflow.staff_leaves l ON l.user_id=p.user_id WHERE p.doctor_id=p_doctor AND l.hospital_id=hf_security.current_hospital() AND l.status='Approved' AND (p_at AT TIME ZONE 'Asia/Kolkata')::date BETWEEN l.starts_on AND l.ends_on)
 OR EXISTS(SELECT 1 FROM (SELECT user_id,doctor_id FROM hospitalflow.person_profiles UNION SELECT user_id,doctor_id FROM hospitalflow.staff_members WHERE active AND hospital_id=hf_security.current_hospital()) p JOIN hospitalflow.staff_attendance a ON a.user_id=p.user_id WHERE p.doctor_id=p_doctor AND a.hospital_id=hf_security.current_hospital() AND a.day=(p_at AT TIME ZONE 'Asia/Kolkata')::date AND a.status='Absent') $$;
CREATE OR REPLACE FUNCTION hospitalflow.validate_appointment_overlap() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ BEGIN
 PERFORM pg_advisory_xact_lock(74192301);
 IF NEW.status NOT IN ('Cancelled','No show') AND EXISTS(SELECT 1 FROM hospitalflow.appointments a WHERE a.id<>NEW.id AND a.status NOT IN ('Cancelled','No show') AND (a.doctor_id=NEW.doctor_id OR a.patient_id=NEW.patient_id) AND a.at<NEW.at+interval '10 minutes' AND a.at+interval '10 minutes'>NEW.at) THEN RAISE EXCEPTION 'Appointment overlaps an existing visit' USING ERRCODE='23505';END IF;
 IF (TG_OP='INSERT' OR NEW.at IS DISTINCT FROM OLD.at OR NEW.doctor_id IS DISTINCT FROM OLD.doctor_id) AND EXISTS(SELECT 1 FROM hospitalflow.appointment_bookings b WHERE b.hospital_id=NEW.hospital_id AND b.state='Pending' AND b.expires_at>now() AND b.id::text IS DISTINCT FROM nullif(current_setting('hospitalflow.booking_id',true),'') AND (b.doctor_id=NEW.doctor_id OR b.patient_id=NEW.patient_id) AND b.at<NEW.at+interval '10 minutes' AND b.at+interval '10 minutes'>NEW.at) THEN RAISE EXCEPTION 'This slot is held for payment' USING ERRCODE='23505';END IF;
 RETURN NEW;END $$;
CREATE OR REPLACE FUNCTION hospitalflow.validate_appointment_schedule() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE d hospitalflow.doctors%ROWTYPE;local_at timestamp;BEGIN
 IF TG_OP='UPDATE' THEN
 IF NEW.status IS DISTINCT FROM OLD.status AND NOT((OLD.status='Scheduled' AND NEW.status IN ('Checked in','Cancelled','No show')) OR(OLD.status='Checked in' AND NEW.status IN ('In consultation','Cancelled')) OR(OLD.status='In consultation' AND NEW.status='Completed')) THEN RAISE EXCEPTION 'Invalid appointment status transition' USING ERRCODE='23514';END IF;
 IF OLD.status<>'Scheduled' AND(NEW.patient_id IS DISTINCT FROM OLD.patient_id OR NEW.doctor_id IS DISTINCT FROM OLD.doctor_id OR NEW.at IS DISTINCT FROM OLD.at) THEN RAISE EXCEPTION 'An active visit cannot be rescheduled' USING ERRCODE='23514';END IF;
 -- Existing visits retain their history even when staff subsequently take leave.
 IF NEW.at=OLD.at AND NEW.doctor_id=OLD.doctor_id AND NEW.patient_id=OLD.patient_id THEN RETURN NEW;END IF;
 END IF;
 IF NEW.status IN ('Cancelled','No show','Completed') THEN RETURN NEW;END IF;
 SELECT * INTO STRICT d FROM hospitalflow.doctors WHERE id=NEW.doctor_id AND hospital_id=hf_security.current_hospital() AND active;
 local_at:=NEW.at AT TIME ZONE 'Asia/Kolkata';
 IF (hf_security.actor_id()<>'migration' AND NEW.at<now()+interval '2 hours') OR local_at::time<d.start OR local_at::time+interval '10 minutes'>d."end" OR extract(minute FROM local_at)::integer%10<>0 OR extract(second FROM local_at)<>0 OR hf_api.doctor_unavailable(d.id,NEW.at) OR(EXISTS(SELECT 1 FROM hospitalflow.provider_sessions ps WHERE ps.doctor_id=d.id AND (ps.starts_at AT TIME ZONE 'Asia/Kolkata')::date=local_at::date) AND NOT EXISTS(SELECT 1 FROM hospitalflow.provider_sessions ps WHERE ps.doctor_id=d.id AND ps.starts_at<=NEW.at AND ps.ends_at>=NEW.at+interval '10 minutes')) THEN RAISE EXCEPTION 'Choose an available 10-minute slot at least two hours ahead within the doctor shift' USING ERRCODE='23514';END IF;
 RETURN NEW;END $$;
CREATE OR REPLACE FUNCTION hospitalflow.validate_absence() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ BEGIN PERFORM pg_advisory_xact_lock(74192301);RETURN NEW;END $$;
CREATE FUNCTION hf_api.booking_actor() RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ DECLARE actor text:=hf_security.actor_id();BEGIN
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.users u WHERE u.id=actor AND u.active AND u.email_confirmed AND (EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships WHERE user_id=actor AND hospital_id=hf_security.current_hospital() AND active) OR EXISTS(SELECT 1 FROM hospitalflow.network_operators WHERE user_id=actor) OR u.role='Developer')) THEN RAISE EXCEPTION 'Active hospital identity required' USING ERRCODE='42501';END IF;RETURN actor;END $$;
REVOKE ALL ON FUNCTION hf_api.booking_actor() FROM PUBLIC;
-- Availability exposes only free times, never other patients' identities.
CREATE FUNCTION hf_api.booking_slots(p_doctor text,p_day date,p_exclude text DEFAULT '') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE result jsonb;BEGIN
 PERFORM hf_api.booking_actor();
 IF p_day<(now() AT TIME ZONE 'Asia/Kolkata')::date OR p_day>(now() AT TIME ZONE 'Asia/Kolkata')::date+90 THEN RAISE EXCEPTION 'Choose a date within the next 90 days' USING ERRCODE='23514';END IF;
 SELECT COALESCE(jsonb_agg(s.at ORDER BY s.at),'[]') INTO result FROM hospitalflow.doctors d CROSS JOIN LATERAL generate_series((p_day+d.start) AT TIME ZONE 'Asia/Kolkata',((p_day+d."end") AT TIME ZONE 'Asia/Kolkata')-interval '10 minutes',interval '10 minutes') s(at)
 WHERE d.id=p_doctor AND d.hospital_id=hf_security.current_hospital() AND d.active AND extract(minute FROM s.at AT TIME ZONE 'Asia/Kolkata')::int%10=0 AND s.at>=now()+interval '2 hours' AND NOT hf_api.doctor_unavailable(d.id,s.at)
 AND NOT EXISTS(SELECT 1 FROM hospitalflow.appointments a WHERE a.hospital_id=d.hospital_id AND a.id<>p_exclude AND a.doctor_id=d.id AND a.status NOT IN ('Cancelled','No show') AND a.at<s.at+interval '10 minutes' AND a.at+interval '10 minutes'>s.at)
 AND NOT EXISTS(SELECT 1 FROM hospitalflow.appointment_bookings b WHERE b.hospital_id=d.hospital_id AND b.doctor_id=d.id AND b.state='Pending' AND b.expires_at>now() AND b.at=s.at)
 AND(NOT EXISTS(SELECT 1 FROM hospitalflow.provider_sessions ps WHERE ps.doctor_id=d.id AND (ps.starts_at AT TIME ZONE 'Asia/Kolkata')::date=p_day) OR EXISTS(SELECT 1 FROM hospitalflow.provider_sessions ps WHERE ps.doctor_id=d.id AND ps.starts_at<=s.at AND ps.ends_at>=s.at+interval '10 minutes'));
 RETURN result;END $$;
CREATE FUNCTION hf_api.booking_state() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text;pid text;staff boolean;admin boolean;BEGIN
 actor:=hf_api.booking_actor();
 SELECT patient_id INTO pid FROM hospitalflow.patient_accounts WHERE user_id=actor;
 staff:=pid IS NULL;SELECT role IN ('Admin','Developer') INTO admin FROM hospitalflow.users WHERE id=actor;
 RETURN jsonb_build_object('fee',COALESCE((SELECT fee FROM hospitalflow.booking_settings WHERE hospital_id=hf_security.current_hospital()),200),'serverTime',now(),
 'doctors',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'name',name,'department',department,'start',start::text,'end',"end"::text,'registrationId',registration_id) ORDER BY name),'[]') FROM hospitalflow.doctors WHERE hospital_id=hf_security.current_hospital() AND active),
 'bookings',(SELECT COALESCE(jsonb_agg(to_jsonb(b) || jsonb_build_object('state',CASE WHEN state='Pending' AND expires_at<=now() THEN 'Expired' ELSE state END)),'[]') FROM hospitalflow.appointment_bookings b WHERE hospital_id=hf_security.current_hospital() AND (patient_id=pid OR (staff AND (admin OR EXISTS(SELECT 1 FROM hospitalflow.user_permissions WHERE user_id=actor AND permission IN ('Doctor','Reception','Billing','Nurse')) OR EXISTS(SELECT 1 FROM hospitalflow.users WHERE id=actor AND role IN ('Doctor','Nurse')))))),
 'unavailable',(SELECT COALESCE(jsonb_agg(id),'[]') FROM hospitalflow.appointments WHERE hospital_id=hf_security.current_hospital() AND (patient_id=pid OR(staff AND (admin OR EXISTS(SELECT 1 FROM hospitalflow.user_permissions WHERE user_id=actor AND permission IN ('Doctor','Reception','Nurse'))))) AND status='Scheduled' AND hf_api.doctor_unavailable(doctor_id,at)),
 'attendance',(SELECT COALESCE(jsonb_agg(to_jsonb(a) || jsonb_build_object('name',u.name,'registrationId',u.registration_id) ORDER BY a.day DESC),'[]') FROM hospitalflow.staff_attendance a JOIN hospitalflow.users u ON u.id=a.user_id WHERE staff AND a.hospital_id=hf_security.current_hospital() AND (admin OR a.user_id=actor)),
 'leaves',(SELECT COALESCE(jsonb_agg(to_jsonb(l) || jsonb_build_object('name',u.name,'registrationId',u.registration_id) ORDER BY l.created_at DESC),'[]') FROM hospitalflow.staff_leaves l JOIN hospitalflow.users u ON u.id=l.user_id WHERE staff AND l.hospital_id=hf_security.current_hospital() AND (admin OR l.user_id=actor)),
 'staff',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'registrationId',u.registration_id)),'[]') FROM hospitalflow.users u WHERE staff AND admin AND u.active AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id) AND EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships WHERE user_id=u.id AND hospital_id=hf_security.current_hospital() AND active)));
END $$;
CREATE FUNCTION hf_api.booking_command(p_action text,p jsonb,p_test boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text;pid text;admin boolean;staff boolean;allowed boolean;b hospitalflow.appointment_bookings%ROWTYPE;a hospitalflow.appointments%ROWTYPE;v_booking_id uuid;at_time timestamptz;doc text;method text;fee numeric;aid text;target text;v_day date;leave_row hospitalflow.staff_leaves%ROWTYPE;BEGIN
 actor:=hf_api.booking_actor();
 SELECT patient_id INTO pid FROM hospitalflow.patient_accounts WHERE user_id=actor;
 SELECT role IN ('Admin','Developer') INTO admin FROM hospitalflow.users WHERE users.id=actor;
 staff:=pid IS NULL;
 allowed:=admin OR EXISTS(SELECT 1 FROM hospitalflow.user_permissions WHERE user_id=actor AND permission IN ('Doctor','Reception')) OR EXISTS(SELECT 1 FROM hospitalflow.users WHERE users.id=actor AND role='Doctor');
 PERFORM pg_advisory_xact_lock(74192301);
 IF p_action='fee' THEN
 IF NOT admin OR NOT staff THEN RAISE EXCEPTION 'Administration required' USING ERRCODE='42501';END IF;
 INSERT INTO hospitalflow.booking_settings(hospital_id,fee) VALUES(hf_security.current_hospital(),(p->>'fee')::numeric) ON CONFLICT(hospital_id) DO UPDATE SET fee=EXCLUDED.fee,updated_at=now();
 ELSIF p_action='reserve' THEN
 IF pid IS NULL AND NOT allowed THEN RAISE EXCEPTION 'Booking is restricted to patients and booking staff' USING ERRCODE='42501';END IF;
 IF pid IS NULL THEN pid:=p->>'patientId';END IF;
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.patient_hospitals WHERE patient_id=pid AND hospital_id=hf_security.current_hospital()) THEN RAISE EXCEPTION 'Patient is not registered here' USING ERRCODE='42501';END IF;
 v_booking_id:=(p->>'id')::uuid;doc:=p->>'doctorId';at_time:=(p->>'at')::timestamptz;method:=p->>'method';
 SELECT * INTO b FROM hospitalflow.appointment_bookings WHERE appointment_bookings.id=v_booking_id;
 IF FOUND THEN
 IF b.created_by<>actor OR b.hospital_id<>hf_security.current_hospital() OR b.patient_id<>pid OR b.doctor_id<>doc OR b.at<>at_time OR b.method<>method OR b.visit_type<>p->>'type' THEN RAISE EXCEPTION 'Retry details differ' USING ERRCODE='23514';END IF;
 RETURN jsonb_build_object('reference',v_booking_id,'state',b.state);END IF;
 IF staff AND method NOT IN ('Cash','QR') OR NOT staff AND method NOT IN ('UPI','Netbanking','Card','QR') THEN RAISE EXCEPTION 'Choose an allowed payment method' USING ERRCODE='23514';END IF;
 SELECT booking_settings.fee INTO fee FROM hospitalflow.booking_settings WHERE hospital_id=hf_security.current_hospital();
 fee:=COALESCE(fee,200);
 IF method<>'Cash' AND NOT p_test THEN RAISE EXCEPTION 'Online payment provider is not configured; no money has been collected' USING ERRCODE='23514';END IF;
 IF NOT hf_api.booking_slots(doc,(at_time AT TIME ZONE 'Asia/Kolkata')::date) @> jsonb_build_array(to_jsonb(at_time)) THEN RAISE EXCEPTION 'Slot is no longer available; choose another time' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.appointments WHERE hospital_id=hf_security.current_hospital() AND patient_id=pid AND status NOT IN ('Cancelled','No show') AND at<at_time+interval '10 minutes' AND at+interval '10 minutes'>at_time) OR EXISTS(SELECT 1 FROM hospitalflow.appointment_bookings WHERE hospital_id=hf_security.current_hospital() AND patient_id=pid AND state='Pending' AND expires_at>now() AND at=at_time) THEN RAISE EXCEPTION 'Patient already has a booking at this time' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.appointment_bookings(id,patient_id,doctor_id,at,visit_type,amount,method,payment_mode,created_by,expires_at) VALUES(v_booking_id,pid,doc,at_time,p->>'type',fee,method,CASE WHEN method='Cash' THEN 'Cash' ELSE 'Test' END,actor,least(now()+interval '10 minutes',at_time-interval '2 hours'));
 INSERT INTO hospitalflow.booking_events(booking_id,event,actor_id) VALUES(v_booking_id,'Slot held; payment pending',actor);
 ELSIF p_action='pay' THEN
 v_booking_id:=(p->>'id')::uuid;SELECT * INTO b FROM hospitalflow.appointment_bookings WHERE appointment_bookings.id=v_booking_id AND hospital_id=hf_security.current_hospital() AND (patient_id=pid OR(staff AND allowed)) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Booking unavailable' USING ERRCODE='42501';END IF;
 IF b.state='Paid' THEN RETURN jsonb_build_object('reference',b.appointment_id,'state','Paid');END IF;
 IF b.state<>'Pending' OR b.expires_at<=now() THEN RAISE EXCEPTION 'Payment hold expired; choose a new slot' USING ERRCODE='23514';END IF;
 IF b.payment_mode='Test' AND NOT p_test OR b.payment_mode='Cash' AND NOT(staff AND allowed) THEN RAISE EXCEPTION 'Payment confirmation is unavailable' USING ERRCODE='42501';END IF;
 IF COALESCE((p->>'confirmed')::boolean,false)=false THEN RAISE EXCEPTION 'Confirm payment before booking' USING ERRCODE='23514';END IF;
 PERFORM set_config('hospitalflow.booking_id',v_booking_id::text,true);aid:=hf_api.new_id('APT');
 INSERT INTO hospitalflow.appointments(id,patient_id,doctor_id,at,type,status) VALUES(aid,b.patient_id,b.doctor_id,b.at,b.visit_type,'Scheduled');
 UPDATE hospitalflow.appointment_bookings SET state='Paid',paid_at=now(),appointment_id=aid WHERE appointment_bookings.id=v_booking_id;
 INSERT INTO hospitalflow.booking_events(booking_id,event,actor_id) VALUES(v_booking_id,CASE WHEN b.payment_mode='Test' THEN 'Test payment confirmed (no real charge)' ELSE 'Cash receipt confirmed by staff' END,actor);
 ELSIF p_action IN ('cancel','reschedule') THEN
 aid:=p->>'appointmentId';SELECT * INTO a FROM hospitalflow.appointments WHERE appointments.id=aid AND hospital_id=hf_security.current_hospital() AND (patient_id=pid OR(staff AND allowed)) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Appointment unavailable' USING ERRCODE='42501';END IF;
 IF p_action='cancel' AND a.status='Cancelled' THEN RETURN jsonb_build_object('reference',aid);END IF;
 IF a.status<>'Scheduled' OR a.at<=now() THEN RAISE EXCEPTION 'Only a future scheduled appointment can be changed' USING ERRCODE='23514';END IF;
 SELECT * INTO b FROM hospitalflow.appointment_bookings WHERE appointment_id=aid FOR UPDATE;v_booking_id:=b.id;
 IF p_action='reschedule' THEN
 at_time:=(p->>'at')::timestamptz;doc:=p->>'doctorId';
 IF NOT hf_api.booking_slots(doc,(at_time AT TIME ZONE 'Asia/Kolkata')::date,aid) @> jsonb_build_array(to_jsonb(at_time)) THEN RAISE EXCEPTION 'Slot is no longer available' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.appointments SET at=at_time,doctor_id=doc WHERE appointments.id=aid;
 UPDATE hospitalflow.appointment_bookings SET at=at_time,doctor_id=doc WHERE appointment_id=aid;
 ELSE
 UPDATE hospitalflow.appointments SET status='Cancelled' WHERE appointments.id=aid;
 UPDATE hospitalflow.appointment_bookings SET state=CASE WHEN state='Paid' THEN CASE WHEN payment_mode='Test' THEN 'Refunded' ELSE 'Refund pending' END ELSE 'Cancelled' END,refunded_at=CASE WHEN state='Paid' AND payment_mode='Test' THEN now() ELSE NULL END WHERE appointment_id=aid AND state NOT IN ('Refunded','Refund pending');
 END IF;
 IF v_booking_id IS NOT NULL THEN INSERT INTO hospitalflow.booking_events(booking_id,event,actor_id) VALUES(v_booking_id,CASE WHEN p_action='reschedule' THEN 'Appointment rescheduled; original payment retained' WHEN b.payment_mode='Test' THEN 'Test refund to original test source; no real money moved' ELSE 'Refund requested to original source' END,actor);END IF;
 ELSIF p_action IN ('attendance','checkout','leave','resolve-leave','cash-refund') THEN
 IF NOT staff THEN RAISE EXCEPTION 'Patients cannot access attendance and leave' USING ERRCODE='42501';END IF;
 target:=COALESCE(NULLIF(p->>'userId',''),actor);
 IF target<>actor AND NOT admin THEN RAISE EXCEPTION 'Administration required' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.users u WHERE u.id=target AND active AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id) AND (EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships WHERE user_id=u.id AND hospital_id=hf_security.current_hospital() AND active) OR EXISTS(SELECT 1 FROM hospitalflow.network_operators WHERE user_id=u.id))) THEN RAISE EXCEPTION 'Staff member unavailable' USING ERRCODE='42501';END IF;
 IF p_action='attendance' THEN
 v_day:=COALESCE((p->>'day')::date,(now() AT TIME ZONE 'Asia/Kolkata')::date);
 IF NOT admin AND (v_day<>(now() AT TIME ZONE 'Asia/Kolkata')::date OR p->>'status'<>'Present') THEN RAISE EXCEPTION 'Staff may check in only for today; administration marks absence' USING ERRCODE='42501';END IF;
 IF v_day>(now() AT TIME ZONE 'Asia/Kolkata')::date THEN RAISE EXCEPTION 'Cannot mark future attendance' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.staff_attendance(user_id,day,status,check_in,marked_by) VALUES(target,v_day,p->>'status',CASE WHEN p->>'status'='Present' THEN now() ELSE NULL END,actor) ON CONFLICT(hospital_id,user_id,day) DO UPDATE SET status=EXCLUDED.status,marked_by=actor,check_in=CASE WHEN EXCLUDED.status='Present' THEN COALESCE(staff_attendance.check_in,now()) ELSE NULL END,check_out=CASE WHEN EXCLUDED.status='Absent' THEN NULL ELSE staff_attendance.check_out END;
 ELSIF p_action='checkout' THEN
 UPDATE hospitalflow.staff_attendance SET check_out=COALESCE(check_out,now()) WHERE hospital_id=hf_security.current_hospital() AND user_id=actor AND staff_attendance.day=(now() AT TIME ZONE 'Asia/Kolkata')::date AND status='Present';IF NOT FOUND THEN RAISE EXCEPTION 'Check in first' USING ERRCODE='23514';END IF;
 ELSIF p_action='leave' THEN
 IF (p->>'startsOn')::date<(now() AT TIME ZONE 'Asia/Kolkata')::date OR EXISTS(SELECT 1 FROM hospitalflow.staff_leaves WHERE hospital_id=hf_security.current_hospital() AND user_id=target AND status IN ('Pending','Approved') AND starts_on<=(p->>'endsOn')::date AND ends_on>=(p->>'startsOn')::date) THEN RAISE EXCEPTION 'Choose future dates without overlapping leave' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.staff_leaves(user_id,starts_on,ends_on,reason) VALUES(target,(p->>'startsOn')::date,(p->>'endsOn')::date,p->>'reason');
 ELSIF p_action='resolve-leave' THEN
 SELECT * INTO leave_row FROM hospitalflow.staff_leaves WHERE staff_leaves.id=(p->>'id')::uuid AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 IF NOT FOUND OR (NOT admin AND(leave_row.user_id<>actor OR p->>'status'<>'Cancelled')) OR p->>'status' NOT IN ('Approved','Rejected','Cancelled') OR leave_row.status NOT IN ('Pending','Approved') OR (leave_row.status='Approved' AND p->>'status'<>'Cancelled') THEN RAISE EXCEPTION 'Leave action is unavailable' USING ERRCODE='42501';END IF;
 IF p->>'status'='Approved' AND leave_row.user_id=actor THEN RAISE EXCEPTION 'Another administrator must approve your leave' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.staff_leaves SET status=p->>'status',resolved_by=actor WHERE staff_leaves.id=leave_row.id;
 ELSE
 IF NOT admin THEN RAISE EXCEPTION 'Administration required' USING ERRCODE='42501';END IF;
 v_booking_id:=(p->>'id')::uuid;UPDATE hospitalflow.appointment_bookings SET state='Refunded',refunded_at=now() WHERE appointment_bookings.id=v_booking_id AND hospital_id=hf_security.current_hospital() AND payment_mode='Cash' AND state='Refund pending';IF NOT FOUND THEN RAISE EXCEPTION 'Cash refund is unavailable' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.booking_events(booking_id,event,actor_id) VALUES(v_booking_id,'Cash refund returned and confirmed by administration',actor);
 END IF;
 ELSE RAISE EXCEPTION 'Unknown booking operation' USING ERRCODE='23514';END IF;
 PERFORM hf_security.audit('booking-'||p_action,COALESCE(aid,v_booking_id::text,target,'settings'));
 RETURN jsonb_build_object('reference',COALESCE(aid,v_booking_id::text),'state',CASE WHEN p_action='reserve' THEN 'Pending' WHEN p_action='pay' THEN 'Paid' ELSE 'Saved' END);
END $$;
REVOKE ALL ON FUNCTION hf_api.booking_state(),hf_api.booking_slots(text,date,text),hf_api.booking_command(text,jsonb,boolean),hf_api.doctor_unavailable(text,timestamptz) FROM PUBLIC;
-- All cancellation paths, including the existing staff status command, preserve refund tracking.
CREATE FUNCTION hospitalflow.booking_cancel_refund() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ DECLARE b record;BEGIN
 IF NEW.status='Cancelled' AND OLD.status<>'Cancelled' THEN
 FOR b IN UPDATE hospitalflow.appointment_bookings SET state=CASE WHEN payment_mode='Test' THEN 'Refunded' ELSE 'Refund pending' END,refunded_at=CASE WHEN payment_mode='Test' THEN now() ELSE NULL END WHERE appointment_id=NEW.id AND state='Paid' RETURNING id,payment_mode LOOP
 INSERT INTO hospitalflow.booking_events(booking_id,event,actor_id) VALUES(b.id,CASE WHEN b.payment_mode='Test' THEN 'Test refund to original test source (no real money moved)' ELSE 'Refund requested to original cash source' END,hf_security.actor_id());
 END LOOP;END IF;RETURN NEW;END $$;
CREATE TRIGGER booking_cancel_refund AFTER UPDATE ON hospitalflow.appointments FOR EACH ROW EXECUTE FUNCTION hospitalflow.booking_cancel_refund();
REVOKE ALL ON FUNCTION hospitalflow.booking_cancel_refund() FROM PUBLIC;
ALTER TABLE hospitalflow.booking_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY booking_event_fence ON hospitalflow.booking_events USING(EXISTS(SELECT 1 FROM hospitalflow.appointment_bookings b WHERE b.id=booking_id AND b.hospital_id=hf_security.current_hospital()));

DROP POLICY hospital_fence ON hospitalflow.appointment_bookings;
CREATE POLICY hospital_fence ON hospitalflow.appointment_bookings USING(CASE WHEN nullif(current_setting('hospitalflow.patient_id',true),'') IS NOT NULL THEN hf_security.own_patient(patient_id) ELSE hospital_id=hf_security.current_hospital() END) WITH CHECK(hospital_id=hf_security.current_hospital());
CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.booking_events FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes();

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.016_booking_and_attendance.sql','23AA8F4062F7E5C3F206D2055E2E0B4115819A57B40443287180C1D513F1AEBF');

-- 017_department_booking.sql
-- Doctors book within their registered hospital department. Referrals remain a separate workflow.
CREATE FUNCTION hf_api.can_book_provider(p_doctor text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM hospitalflow.users u JOIN hospitalflow.doctors d ON d.id=p_doctor AND d.active AND d.hospital_id=hf_security.current_hospital()
 LEFT JOIN hospitalflow.person_profiles p ON p.user_id=u.id LEFT JOIN hospitalflow.doctors own ON own.id=p.doctor_id
 LEFT JOIN hospitalflow.staff_members s ON s.user_id=u.id AND s.active AND s.hospital_id=hf_security.current_hospital() LEFT JOIN hospitalflow.doctors sd ON sd.id=s.doctor_id
 WHERE u.id=hf_security.actor_id() AND u.active AND (u.role IN ('Admin','Developer') OR
 (u.role<>'Doctor' AND NOT EXISTS(SELECT 1 FROM hospitalflow.user_permissions WHERE user_id=u.id AND permission='Doctor')) OR
 (d.department=COALESCE(own.department,p.department,sd.department,s.department) AND COALESCE(own.hospital_id,s.hospital_id,hf_security.current_hospital())=hf_security.current_hospital()))) $$;
REVOKE ALL ON FUNCTION hf_api.can_book_provider(text) FROM PUBLIC;
CREATE FUNCTION hospitalflow.guard_booking_department() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$ BEGIN
 IF TG_OP='INSERT' OR NEW.doctor_id IS DISTINCT FROM OLD.doctor_id OR NEW.at IS DISTINCT FROM OLD.at OR NEW.patient_id IS DISTINCT FROM OLD.patient_id THEN
 IF hf_security.actor_id() IS NOT NULL AND hf_security.actor_id()<>'migration' AND NOT hf_api.can_book_provider(NEW.doctor_id) THEN RAISE EXCEPTION 'Doctors can book only within their own registered hospital department; use a referral for another department or hospital' USING ERRCODE='42501';END IF;
 END IF;RETURN NEW;END $$;
CREATE TRIGGER booking_department BEFORE INSERT OR UPDATE ON hospitalflow.appointments FOR EACH ROW EXECUTE FUNCTION hospitalflow.guard_booking_department();
CREATE TRIGGER booking_department BEFORE INSERT OR UPDATE ON hospitalflow.appointment_bookings FOR EACH ROW EXECUTE FUNCTION hospitalflow.guard_booking_department();
REVOKE ALL ON FUNCTION hospitalflow.guard_booking_department() FROM PUBLIC;
-- Apply the same restriction to previews, reservations and rescheduling before payment is taken.
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.booking_slots(text,date,text)'::regprocedure) INTO definition;
 definition:=replace(definition,'AND d.active AND extract','AND d.active AND hf_api.can_book_provider(d.id) AND extract');EXECUTE definition;
 SELECT pg_get_functiondef('hf_api.booking_state()'::regprocedure) INTO definition;
 definition:=replace(definition,'AND active),','AND active AND hf_api.can_book_provider(id)),');EXECUTE definition;
END $$;
CREATE FUNCTION hf_api.select_booking_hospital(p_hospital text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text;pid text;BEGIN
 actor:=hf_api.booking_actor();SELECT patient_id INTO pid FROM hospitalflow.patient_accounts WHERE user_id=actor;
 IF pid IS NULL THEN RAISE EXCEPTION 'Only patients may register themselves at a network hospital' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(74192301);
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.hospitals WHERE id=p_hospital AND active) OR EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships WHERE user_id=actor AND hospital_id=p_hospital AND NOT active) THEN RAISE EXCEPTION 'Hospital access is unavailable; contact administration' USING ERRCODE='42501';END IF;
 INSERT INTO hospitalflow.patient_hospitals(patient_id,hospital_id) VALUES(pid,p_hospital) ON CONFLICT DO NOTHING;
 INSERT INTO hospitalflow.hospital_memberships(user_id,hospital_id) VALUES(actor,p_hospital) ON CONFLICT DO NOTHING;
 PERFORM hf_security.audit('patient-booking-hospital-registration',p_hospital);
END $$;
REVOKE ALL ON FUNCTION hf_api.select_booking_hospital(text) FROM PUBLIC;
-- A same-hospital referral must identify a receiving doctor.
ALTER TABLE hospitalflow.referrals DROP CONSTRAINT referrals_check;
ALTER TABLE hospitalflow.referrals ADD CONSTRAINT referral_destination CHECK(source_hospital_id<>target_hospital_id OR target_doctor_id IS NOT NULL);
DROP INDEX hospitalflow.referral_pending_unique;
CREATE UNIQUE INDEX referral_pending_unique ON hospitalflow.referrals(patient_id,source_hospital_id,target_hospital_id,COALESCE(target_doctor_id,'')) WHERE status='Pending';
-- Patients also exclude their own overlapping visits/holds across the network.
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.booking_slots(text,date,text)'::regprocedure) INTO definition;
 definition:=replace(definition,'AND(NOT EXISTS(SELECT 1 FROM hospitalflow.provider_sessions',
 'AND NOT EXISTS(SELECT 1 FROM hospitalflow.appointments mine JOIN hospitalflow.patient_accounts pa ON pa.patient_id=mine.patient_id WHERE pa.user_id=hf_security.actor_id() AND mine.id<>p_exclude AND mine.status NOT IN (''Cancelled'',''No show'') AND mine.at<s.at+interval ''10 minutes'' AND mine.at+interval ''10 minutes''>s.at)
 AND NOT EXISTS(SELECT 1 FROM hospitalflow.appointment_bookings mine JOIN hospitalflow.patient_accounts pa ON pa.patient_id=mine.patient_id WHERE pa.user_id=hf_security.actor_id() AND mine.state=''Pending'' AND mine.expires_at>now() AND mine.at<s.at+interval ''10 minutes'' AND mine.at+interval ''10 minutes''>s.at)
 AND(NOT EXISTS(SELECT 1 FROM hospitalflow.provider_sessions');EXECUTE definition;
END $$;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.017_department_booking.sql','5BC47192EAEC1CA0C323C7530C447F4350F2F7613C073398DC1DA83EE6EBA86C');

-- 018_attendance_approval.sql
ALTER TABLE hospitalflow.staff_attendance ADD COLUMN approval_status text NOT NULL DEFAULT 'Approved' CHECK(approval_status IN ('Pending','Approved','Rejected')),
 ADD COLUMN reviewed_by text REFERENCES hospitalflow.users(id),ADD COLUMN reviewed_at timestamptz,ADD COLUMN review_note text NOT NULL DEFAULT '' CHECK(length(review_note)<=500),ADD COLUMN submitted_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE hospitalflow.staff_attendance ALTER COLUMN approval_status SET DEFAULT 'Pending';
CREATE INDEX attendance_pending_review ON hospitalflow.staff_attendance(hospital_id,submitted_at) WHERE approval_status='Pending';
CREATE FUNCTION hf_api.can_review_attendance() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM hospitalflow.users u JOIN hospitalflow.hospital_memberships m ON m.user_id=u.id AND m.hospital_id=hf_security.current_hospital() AND m.active WHERE u.id=hf_security.actor_id() AND u.active AND u.email_confirmed AND u.role IN ('Admin','Developer') AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id)) $$;
ALTER FUNCTION hf_api.booking_command(text,jsonb,boolean) RENAME TO booking_command_base;
CREATE FUNCTION hf_api.booking_command(p_action text,p jsonb,p_test boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text;attendance hospitalflow.staff_attendance%ROWTYPE;outcome text;note text;BEGIN
 IF p_action NOT IN ('attendance','checkout','review-attendance') THEN RETURN hf_api.booking_command_base(p_action,p,p_test);END IF;
 actor:=hf_api.booking_actor();
 IF EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor) THEN RAISE EXCEPTION 'Patients cannot access attendance' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships WHERE user_id=actor AND hospital_id=hf_security.current_hospital() AND active) THEN RAISE EXCEPTION 'Attendance requires an active membership at this hospital' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(74192301);
 IF p_action='review-attendance' THEN
 IF NOT hf_api.can_review_attendance() THEN RAISE EXCEPTION 'Only an administrator assigned to this hospital can review attendance' USING ERRCODE='42501';END IF;
 outcome:=p->>'status';note:=COALESCE(p->>'note','');
 IF outcome IS NULL OR outcome NOT IN ('Approved','Rejected') OR length(note)>500 OR(outcome='Rejected' AND length(trim(note))<5) THEN RAISE EXCEPTION 'Choose an approval outcome; rejection requires a reason of at least five characters' USING ERRCODE='23514';END IF;
 SELECT * INTO attendance FROM hospitalflow.staff_attendance WHERE id=(p->>'id')::uuid AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 IF NOT FOUND OR attendance.user_id=actor THEN RAISE EXCEPTION 'Attendance is unavailable or belongs to you; another hospital administrator must review it' USING ERRCODE='42501';END IF;
 IF attendance.approval_status<>'Pending' THEN RAISE EXCEPTION 'This attendance request has already been reviewed' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.staff_attendance SET approval_status=outcome,reviewed_by=actor,reviewed_at=now(),review_note=trim(note) WHERE id=attendance.id;
 ELSE
 IF COALESCE(NULLIF(p->>'userId',''),actor)<>actor THEN RAISE EXCEPTION 'Staff can submit only their own attendance' USING ERRCODE='42501';END IF;
 IF p ? 'day' AND(p->>'day')::date<>(now() AT TIME ZONE 'Asia/Kolkata')::date THEN RAISE EXCEPTION 'You may submit attendance only for today' USING ERRCODE='23514';END IF;
 SELECT * INTO attendance FROM hospitalflow.staff_attendance WHERE hospital_id=hf_security.current_hospital() AND user_id=actor AND day=(now() AT TIME ZONE 'Asia/Kolkata')::date FOR UPDATE;
 IF p_action='checkout' THEN
 IF attendance.id IS NULL OR attendance.status<>'Present' OR attendance.approval_status='Rejected' THEN RAISE EXCEPTION 'Submit a present check-in before checking out' USING ERRCODE='23514';END IF;
 IF attendance.check_out IS NOT NULL THEN RETURN jsonb_build_object('reference',attendance.id,'state',attendance.approval_status);END IF;
 UPDATE hospitalflow.staff_attendance SET check_out=now(),approval_status='Pending',reviewed_by=NULL,reviewed_at=NULL,review_note='',submitted_at=now() WHERE id=attendance.id;
 ELSE
 IF p->>'status' IS NULL OR p->>'status' NOT IN ('Present','Absent') THEN RAISE EXCEPTION 'Choose Present or Absent' USING ERRCODE='23514';END IF;
 IF attendance.id IS NOT NULL AND attendance.approval_status<>'Rejected' THEN
 IF attendance.status=p->>'status' THEN
 IF attendance.approval_status='Approved' AND attendance.reviewed_by IS NULL THEN
 UPDATE hospitalflow.staff_attendance SET approval_status='Pending',submitted_at=now() WHERE id=attendance.id;
 PERFORM hf_security.audit('attendance-submitted-for-review',attendance.id::text);
 RETURN jsonb_build_object('reference',attendance.id,'state','Pending');END IF;
 RETURN jsonb_build_object('reference',attendance.id,'state',attendance.approval_status);END IF;
 RAISE EXCEPTION 'Attendance was already submitted; contact your hospital administrator' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.staff_attendance(user_id,day,status,check_in,marked_by) VALUES(actor,(now() AT TIME ZONE 'Asia/Kolkata')::date,p->>'status',CASE WHEN p->>'status'='Present' THEN now() ELSE NULL END,actor)
 ON CONFLICT(hospital_id,user_id,day) DO UPDATE SET status=EXCLUDED.status,check_in=EXCLUDED.check_in,check_out=NULL,marked_by=actor,approval_status='Pending',reviewed_by=NULL,reviewed_at=NULL,review_note='',submitted_at=now() RETURNING * INTO attendance;
 END IF;END IF;
 PERFORM hf_security.audit(CASE WHEN p_action='review-attendance' THEN 'attendance-'||lower(outcome) ELSE 'attendance-'||p_action END,attendance.id::text);
 RETURN jsonb_build_object('reference',attendance.id,'state',CASE WHEN p_action='review-attendance' THEN outcome ELSE 'Pending' END);
END $$;
-- Do not expose the older attendance implementation as an alternate API.
REVOKE ALL ON FUNCTION hf_api.booking_command_base(text,jsonb,boolean) FROM PUBLIC;
ALTER FUNCTION hf_api.booking_state() RENAME TO booking_state_base;
CREATE FUNCTION hf_api.booking_state() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE result jsonb;actor text;reviewer boolean;BEGIN
 result:=hf_api.booking_state_base();actor:=hf_api.booking_actor();reviewer:=hf_api.can_review_attendance();
 RETURN result || jsonb_build_object('canReviewAttendance',reviewer,'attendance',(SELECT COALESCE(jsonb_agg(to_jsonb(a)||jsonb_build_object('name',u.name,'registrationId',u.registration_id,'reviewerName',r.name) ORDER BY a.day DESC,a.submitted_at DESC),'[]') FROM hospitalflow.staff_attendance a JOIN hospitalflow.users u ON u.id=a.user_id LEFT JOIN hospitalflow.users r ON r.id=a.reviewed_by WHERE a.hospital_id=hf_security.current_hospital() AND (reviewer OR a.user_id=actor) AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor)));
END $$;
DO $$ DECLARE definition text;BEGIN SELECT pg_get_functiondef('hf_api.doctor_unavailable(text,timestamptz)'::regprocedure) INTO definition;
 definition:=replace(definition,'a.status=''Absent''','a.status=''Absent'' AND a.approval_status=''Approved''');EXECUTE definition;END $$;
REVOKE ALL ON FUNCTION hf_api.booking_command(text,jsonb,boolean),hf_api.booking_state(),hf_api.booking_state_base(),hf_api.can_review_attendance() FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.018_attendance_approval.sql','371DFAA12E20CF072B838EF43A740489FA524BBDD259CA666F60C341336ABBBC');

-- 019_attendance_hours_and_admin_review.sql
-- Administrators may review their own attendance, within their assigned hospital.
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.booking_command(text,jsonb,boolean)'::regprocedure) INTO definition;
 definition:=replace(definition,'IF NOT FOUND OR attendance.user_id=actor THEN RAISE EXCEPTION ''Attendance is unavailable or belongs to you; another hospital administrator must review it''', 'IF NOT FOUND THEN RAISE EXCEPTION ''Attendance is unavailable in this hospital''');EXECUTE definition;
END $$;
-- Final duration is derived from the recorded timestamps, restricted to this IST calendar day.
-- Unfinished check-ins have no final duration; their live elapsed duration is returned separately.
ALTER TABLE hospitalflow.staff_attendance ADD COLUMN total_seconds bigint GENERATED ALWAYS AS (
 CASE WHEN status='Absent' THEN 0 WHEN check_in IS NULL OR check_out IS NULL THEN NULL
 ELSE greatest(0,extract(epoch FROM(least(check_out,(day+1)::timestamp AT TIME ZONE 'Asia/Kolkata')-greatest(check_in,day::timestamp AT TIME ZONE 'Asia/Kolkata')))::bigint) END) STORED;
CREATE OR REPLACE FUNCTION hf_api.booking_state() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE result jsonb;actor text;reviewer boolean;BEGIN
 result:=hf_api.booking_state_base();actor:=hf_api.booking_actor();reviewer:=hf_api.can_review_attendance();
 RETURN result || jsonb_build_object('canReviewAttendance',reviewer,'attendance',(SELECT COALESCE(jsonb_agg(to_jsonb(a)||jsonb_build_object('name',u.name,'registrationId',u.registration_id,'reviewerName',r.name,
 'totalHours',round(a.total_seconds/3600.0,2),
 'elapsedSeconds',CASE WHEN a.status='Present' AND a.check_in IS NOT NULL AND a.check_out IS NULL THEN greatest(0,extract(epoch FROM(least(now(),(a.day+1)::timestamp AT TIME ZONE 'Asia/Kolkata')-greatest(a.check_in,a.day::timestamp AT TIME ZONE 'Asia/Kolkata')))::bigint) ELSE a.total_seconds END)
 ORDER BY a.day DESC,a.submitted_at DESC),'[]') FROM hospitalflow.staff_attendance a JOIN hospitalflow.users u ON u.id=a.user_id LEFT JOIN hospitalflow.users r ON r.id=a.reviewed_by WHERE a.hospital_id=hf_security.current_hospital() AND (reviewer OR a.user_id=actor) AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor)));
END $$;
COMMENT ON COLUMN hospitalflow.staff_attendance.total_seconds IS 'Completed attendance duration in seconds within the recorded IST date; absent=0, no checkout=NULL. Approval remains separate from elapsed time.';
CREATE FUNCTION hf_api.manage_staff_attendance(p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text;target text;attendance_day date;presence text;started timestamptz;finished timestamptz;reason text;record_id uuid;BEGIN
 actor:=hf_api.booking_actor();IF NOT hf_api.can_review_attendance() THEN RAISE EXCEPTION 'Only an administrator assigned to this hospital can manage attendance' USING ERRCODE='42501';END IF;
 target:=p->>'userId';attendance_day:=(p->>'day')::date;presence:=p->>'status';reason:=trim(COALESCE(p->>'reason',''));
 IF attendance_day IS NULL OR attendance_day>(now() AT TIME ZONE 'Asia/Kolkata')::date OR attendance_day<date '1900-01-01' OR presence IS NULL OR presence NOT IN ('Present','Absent') OR length(reason) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'Choose a valid attendance date, status and reason of 5–500 characters' USING ERRCODE='23514';END IF;
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.users u JOIN hospitalflow.hospital_memberships m ON m.user_id=u.id AND m.hospital_id=hf_security.current_hospital() AND m.active WHERE u.id=target AND u.active AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id)) THEN RAISE EXCEPTION 'Choose an employee assigned to this hospital' USING ERRCODE='42501';END IF;
 IF presence='Present' THEN
 started:=NULLIF(p->>'checkIn','')::timestamptz;finished:=NULLIF(p->>'checkOut','')::timestamptz;
 IF started IS NULL OR (started AT TIME ZONE 'Asia/Kolkata')::date<>attendance_day OR started>now() OR(finished IS NOT NULL AND(finished<started OR finished>now() OR (finished AT TIME ZONE 'Asia/Kolkata')::date<>attendance_day)) THEN RAISE EXCEPTION 'Enter valid check-in/out times on the selected IST date, without future times' USING ERRCODE='23514';END IF;
 END IF;
 PERFORM pg_advisory_xact_lock(74192301);
 INSERT INTO hospitalflow.staff_attendance(user_id,day,status,check_in,check_out,marked_by,approval_status,reviewed_by,reviewed_at,review_note)
 VALUES(target,attendance_day,presence,started,finished,actor,'Approved',actor,now(),reason)
 ON CONFLICT(hospital_id,user_id,day) DO UPDATE SET status=EXCLUDED.status,check_in=EXCLUDED.check_in,check_out=EXCLUDED.check_out,marked_by=actor,approval_status='Approved',reviewed_by=actor,reviewed_at=now(),review_note=reason,submitted_at=now() RETURNING id INTO record_id;
 PERFORM hf_security.audit('attendance-admin-managed',record_id::text);
 RETURN jsonb_build_object('reference',record_id,'state','Approved');
END $$;
REVOKE ALL ON FUNCTION hf_api.manage_staff_attendance(jsonb) FROM PUBLIC;
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.booking_command(text,jsonb,boolean)'::regprocedure) INTO definition;
 definition:=replace(definition,' IF p_action NOT IN', ' IF p_action=''manage-attendance'' THEN RETURN hf_api.manage_staff_attendance(p);END IF;
 IF p_action NOT IN');EXECUTE definition;
END $$;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.019_attendance_hours_and_admin_review.sql','8CD54AD49453C6296BBCB0D248D1A314F1B3324940780AC4CA9820447381D315');

-- 020_hospital_leave_calendar.sql
-- Shared staff availability exposes approved dates and identities, never private leave reasons.
CREATE FUNCTION hf_api.hospital_leave_calendar() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text;today date:=(now() AT TIME ZONE 'Asia/Kolkata')::date;BEGIN
 actor:=hf_api.booking_actor();
 IF EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor) THEN RAISE EXCEPTION 'The hospital staff leave calendar is unavailable to patient accounts' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('hospitalId',hf_security.current_hospital(),'hospitalName',(SELECT name FROM hospitalflow.hospitals WHERE id=hf_security.current_hospital()),'asOf',today,
 'leaves',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',l.id,'name',u.name,'registrationId',u.registration_id,'role',u.role,'department',COALESCE(p.department,s.department,''),'startsOn',l.starts_on,'endsOn',l.ends_on,'daysRemaining',CASE WHEN l.starts_on<=today THEN l.ends_on-today+1 ELSE NULL END,'availability',CASE WHEN l.starts_on<=today THEN 'On leave' ELSE 'Upcoming' END) ORDER BY CASE WHEN l.starts_on<=today THEN 0 ELSE 1 END,l.starts_on,u.name),'[]')
 FROM hospitalflow.staff_leaves l JOIN hospitalflow.users u ON u.id=l.user_id
 JOIN hospitalflow.hospital_memberships m ON m.user_id=u.id AND m.hospital_id=l.hospital_id AND m.active
 LEFT JOIN hospitalflow.person_profiles p ON p.user_id=u.id LEFT JOIN hospitalflow.staff_members s ON s.user_id=u.id AND s.hospital_id=l.hospital_id AND s.active
 WHERE l.hospital_id=hf_security.current_hospital() AND l.status='Approved' AND l.ends_on>=today AND u.active AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id)));
END $$;
REVOKE ALL ON FUNCTION hf_api.hospital_leave_calendar() FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.020_hospital_leave_calendar.sql','702EEF923A81892D67D100B7CADBB1743BC57E1C4EEBE775EB5A003AA8AB1744');

-- 021_admin_doctor_separation.sql
INSERT INTO hospitalflow.roles(name) VALUES('Admin'),('Doctor'),('Developer') ON CONFLICT DO NOTHING;
-- Preserve legacy clinician identities while making Doctor an explicit role.
UPDATE hospitalflow.users u SET role='Doctor' WHERE role='User' AND EXISTS(SELECT 1 FROM hospitalflow.user_permissions WHERE user_id=u.id AND permission='Doctor') AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id);
DELETE FROM hospitalflow.user_permissions p USING hospitalflow.users u WHERE p.user_id=u.id AND p.permission='Doctor' AND u.role<>'Developer';
CREATE FUNCTION hf_security.separate_doctor_permission() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ BEGIN
 IF NEW.permission='Doctor' AND NOT EXISTS(SELECT 1 FROM hospitalflow.users WHERE id=NEW.user_id AND role IN ('Doctor','Developer')) THEN RAISE EXCEPTION 'Assign the separate Doctor role instead of adding Doctor privileges to another role' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER separate_doctor_permission BEFORE INSERT OR UPDATE ON hospitalflow.user_permissions FOR EACH ROW EXECUTE FUNCTION hf_security.separate_doctor_permission();
-- Administrative access never substitutes for a clinical author identity.
CREATE FUNCTION hf_security.guard_clinical_author() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$
DECLARE role_name text;BEGIN
 SELECT role INTO role_name FROM hospitalflow.users WHERE id=hf_security.actor_id();
 IF role_name='Admin' THEN
 IF TG_TABLE_NAME='prescriptions' AND TG_OP='UPDATE' THEN
 IF NEW.status<>'Cancelled' AND NEW.patient_id=OLD.patient_id AND NEW.medicine_id=OLD.medicine_id AND NEW.quantity=OLD.quantity AND NEW.instructions=OLD.instructions THEN RETURN NEW;END IF;
 ELSIF TG_TABLE_NAME='follow_ups' AND TG_OP='UPDATE' AND (to_jsonb(NEW)-ARRAY['status','appointment_id','doctor_id'])=(to_jsonb(OLD)-ARRAY['status','appointment_id','doctor_id']) THEN RETURN NEW;
 END IF;
 RAISE EXCEPTION 'Clinical authoring requires Doctor or the appropriate clinical staff role; Admin manages hospital operations' USING ERRCODE='42501';END IF;
 RETURN NEW;END $$;
CREATE TRIGGER clinical_author BEFORE INSERT OR UPDATE ON hospitalflow.prescriptions FOR EACH ROW EXECUTE FUNCTION hf_security.guard_clinical_author();
CREATE TRIGGER clinical_author BEFORE INSERT OR UPDATE ON hospitalflow.notes FOR EACH ROW EXECUTE FUNCTION hf_security.guard_clinical_author();
CREATE TRIGGER clinical_author BEFORE INSERT OR UPDATE ON hospitalflow.clinical_orders FOR EACH ROW EXECUTE FUNCTION hf_security.guard_clinical_author();
CREATE TRIGGER clinical_author BEFORE INSERT OR UPDATE ON hospitalflow.follow_ups FOR EACH ROW EXECUTE FUNCTION hf_security.guard_clinical_author();
-- Guard the command boundary as well as native table/procedure writes.
DO $$ DECLARE definition text;BEGIN SELECT pg_get_functiondef('hf_api.execute(text,jsonb,uuid,text)'::regprocedure) INTO definition;
 definition:=replace(definition,'BEGIN', 'BEGIN
 IF p_action IN (''prescription'',''cancel-prescription'',''note'',''clinical-order'',''clinical-order-status'',''complete-clinical-order'',''follow-up'') AND EXISTS(SELECT 1 FROM hospitalflow.users WHERE id=hf_security.actor_id() AND role=''Admin'') THEN RAISE EXCEPTION ''Admin cannot author clinical records; use a separate Doctor account'' USING ERRCODE=''42501'';END IF;');
 EXECUTE definition;END $$;
REVOKE ALL ON FUNCTION hf_security.separate_doctor_permission(),hf_security.guard_clinical_author() FROM PUBLIC;
-- Admin may complete operational discharge, retaining the reason in admission_events.
-- Clinical discharge notes remain authored by clinical staff rather than the administrator.
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.discharge_patient(text,text)'::regprocedure) INTO definition;
 definition:=replace(definition,'INSERT INTO hospitalflow.notes VALUES(hf_api.new_id(''NOTE''),a.patient_id,p_summary,''Discharge summary'',now());',
 'IF NOT EXISTS(SELECT 1 FROM hospitalflow.users WHERE id=hf_security.actor_id() AND role=''Admin'') THEN INSERT INTO hospitalflow.notes VALUES(hf_api.new_id(''NOTE''),a.patient_id,p_summary,''Discharge summary'',now());END IF;');EXECUTE definition;
END $$;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.021_admin_doctor_separation.sql','4F42A5E6BA2F2F8468F2117D69282C54A3B42AF46CD99F9CA0474E0901DCD71A');

-- 022_medication_administration.sql
-- Append-only evidence of medication actually provided; pharmacy dispensing is separate.
CREATE TABLE hospitalflow.medication_administrations(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),
 prescription_id text NOT NULL REFERENCES hospitalflow.prescriptions(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),
 quantity integer NOT NULL CHECK(quantity>0),provided_by text NOT NULL REFERENCES hospitalflow.users(id),provided_at timestamptz NOT NULL DEFAULT now(),
 note text NOT NULL CHECK(length(note) BETWEEN 1 AND 1000),retry_key uuid NOT NULL,UNIQUE(provided_by,retry_key));
CREATE INDEX medication_administration_prescription ON hospitalflow.medication_administrations(hospital_id,prescription_id,provided_at);
ALTER TABLE hospitalflow.medication_administrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE hospitalflow.medication_administrations FORCE ROW LEVEL SECURITY;
CREATE POLICY medication_read ON hospitalflow.medication_administrations FOR SELECT USING(hospital_id=hf_security.current_hospital() AND (hf_security.can_access_patient(patient_id) OR EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=hf_security.actor_id() AND patient_id=medication_administrations.patient_id)));
CREATE POLICY medication_insert ON hospitalflow.medication_administrations FOR INSERT WITH CHECK(hospital_id=hf_security.current_hospital() AND provided_by=hf_security.actor_id() AND hf_security.can_access_patient(patient_id));
CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.medication_administrations FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes();
CREATE TRIGGER z_hospital_guard BEFORE INSERT OR UPDATE OR DELETE ON hospitalflow.medication_administrations FOR EACH ROW EXECUTE FUNCTION hf_security.guard_hospital_row();
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.medication_administrations FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE FUNCTION hf_api.medication_care() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$
DECLARE actor text;role_name text;pid text;BEGIN
 actor:=hf_api.booking_actor();SELECT role INTO role_name FROM hospitalflow.users WHERE id=actor;SELECT patient_id INTO pid FROM hospitalflow.patient_accounts WHERE user_id=actor;
 IF pid IS NULL AND role_name NOT IN ('Doctor','Nurse','Admin','Developer') THEN RAISE EXCEPTION 'Clinical care access is required' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('prescriptions',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'patientId',p.patient_id,'patientName',pt.name,'patientCode',pt.registration_id,'medicine',m.name,'quantity',p.quantity,'instructions',p.instructions,'status',p.status,'provided',COALESCE((SELECT sum(a.quantity) FROM hospitalflow.medication_administrations a WHERE a.prescription_id=p.id),0)) ORDER BY p.created_at DESC),'[]') FROM hospitalflow.prescriptions p JOIN hospitalflow.patients pt ON pt.id=p.patient_id JOIN hospitalflow.medicine_batches m ON m.id=p.medicine_id WHERE p.hospital_id=hf_security.current_hospital() AND (CASE WHEN pid IS NOT NULL THEN p.patient_id=pid ELSE hf_security.can_access_patient(p.patient_id) END)),
 'administrations',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',a.id,'prescriptionId',a.prescription_id,'patientId',a.patient_id,'quantity',a.quantity,'providedAt',a.provided_at,'providedBy',u.name,'staffId',u.registration_id,'note',a.note) ORDER BY a.provided_at DESC),'[]') FROM hospitalflow.medication_administrations a JOIN hospitalflow.users u ON u.id=a.provided_by WHERE a.hospital_id=hf_security.current_hospital() AND (CASE WHEN pid IS NOT NULL THEN a.patient_id=pid ELSE hf_security.can_access_patient(a.patient_id) END)));
END $$;
CREATE FUNCTION hf_api.provide_medication(p_prescription text,p_quantity integer,p_note text,p_key uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$
DECLARE actor text;rx hospitalflow.prescriptions%ROWTYPE;existing hospitalflow.medication_administrations%ROWTYPE;result uuid;BEGIN
 actor:=hf_api.booking_actor();
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.users WHERE id=actor AND role IN ('Nurse','Developer')) OR EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor) THEN RAISE EXCEPTION 'Only nursing staff may record medication provided' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO existing FROM hospitalflow.medication_administrations WHERE provided_by=actor AND retry_key=p_key;
 IF FOUND THEN IF existing.prescription_id<>p_prescription OR existing.quantity<>p_quantity OR existing.note<>btrim(p_note) OR existing.hospital_id<>hf_security.current_hospital() THEN RAISE EXCEPTION 'Retry key was already used for a different record' USING ERRCODE='23514';END IF;RETURN existing.id;END IF;
 SELECT * INTO rx FROM hospitalflow.prescriptions WHERE id=p_prescription AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 IF NOT FOUND OR NOT hf_security.can_access_patient(rx.patient_id) THEN RAISE EXCEPTION 'Prescription is outside your care access' USING ERRCODE='42501';END IF;
 IF rx.status<>'Dispensed' THEN RAISE EXCEPTION 'Pharmacy must dispense this prescription before administration is recorded' USING ERRCODE='23514';END IF;
 IF p_quantity IS NULL OR p_quantity<1 OR p_note IS NULL OR length(btrim(p_note)) NOT BETWEEN 1 AND 1000 OR p_key IS NULL THEN RAISE EXCEPTION 'Enter a positive quantity and administration note (up to 1000 characters)' USING ERRCODE='23514';END IF;
 IF p_quantity+COALESCE((SELECT sum(quantity) FROM hospitalflow.medication_administrations WHERE prescription_id=rx.id),0)>rx.quantity THEN RAISE EXCEPTION 'Provided quantity exceeds the prescribed quantity remaining' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.medication_administrations(prescription_id,patient_id,quantity,provided_by,note,retry_key) VALUES(rx.id,rx.patient_id,p_quantity,actor,btrim(p_note),p_key) RETURNING id INTO result;
 RETURN result;
END $$;
REVOKE ALL ON hospitalflow.medication_administrations FROM PUBLIC;
REVOKE ALL ON FUNCTION hf_api.medication_care(),hf_api.provide_medication(text,integer,text,uuid) FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.022_medication_administration.sql','C2B00BCF754752384472ED41F757D5A67222C082CE87D2E96D0C840A12577054');

-- 023_staff_first_login.sql
-- New staff registrations require DOB verification and a replacement password before sessions.
-- Existing accounts keep their credentials and activation status.
CREATE TABLE hospitalflow.staff_onboarding(
 user_id text PRIMARY KEY REFERENCES hospitalflow.users(id),must_change_password boolean NOT NULL DEFAULT true,
 expires_at timestamptz NOT NULL DEFAULT now()+interval '24 hours',activated_at timestamptz,
 CHECK(must_change_password OR activated_at IS NOT NULL));
REVOKE ALL ON hospitalflow.staff_onboarding FROM PUBLIC;
ALTER TABLE hospitalflow.patient_login_challenges DROP CONSTRAINT patient_login_challenges_user_id_fkey;
ALTER TABLE hospitalflow.patient_login_challenges ADD CONSTRAINT first_login_challenge_user_fkey FOREIGN KEY(user_id) REFERENCES hospitalflow.users(id);

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.023_staff_first_login.sql','4184C690DD0AA5D020C2BE44D25814C108D86BB04AC83CC8CD6A087A1B4BD3D3');

-- 024_visit_prescriptions.sql
CREATE TABLE hospitalflow.prescription_visits(
 prescription_id text PRIMARY KEY REFERENCES hospitalflow.prescriptions(id),appointment_id text NOT NULL REFERENCES hospitalflow.appointments(id),
 hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id));
CREATE INDEX prescription_visit_lookup ON hospitalflow.prescription_visits(hospital_id,appointment_id);
ALTER TABLE hospitalflow.prescription_visits ENABLE ROW LEVEL SECURITY;
CREATE POLICY visit_prescription_scope ON hospitalflow.prescription_visits USING(hospital_id=hf_security.current_hospital());
CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.prescription_visits FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes();
CREATE TRIGGER z_hospital_guard BEFORE INSERT OR UPDATE OR DELETE ON hospitalflow.prescription_visits FOR EACH ROW EXECUTE FUNCTION hf_security.guard_hospital_row();
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.prescription_visits FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE FUNCTION hf_security.is_visit_doctor(p_doctor text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM hospitalflow.users u WHERE u.id=hf_security.actor_id() AND u.active AND (u.role='Developer' OR(u.role='Doctor' AND (EXISTS(SELECT 1 FROM hospitalflow.person_profiles p WHERE p.user_id=u.id AND p.doctor_id=p_doctor) OR EXISTS(SELECT 1 FROM hospitalflow.staff_members s WHERE s.user_id=u.id AND s.doctor_id=p_doctor AND s.hospital_id=hf_security.current_hospital() AND s.active))))) $$;
CREATE FUNCTION hf_security.guard_doctor_visit() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$ BEGIN
 IF NEW.status IS DISTINCT FROM OLD.status AND EXISTS(SELECT 1 FROM hospitalflow.users WHERE id=hf_security.actor_id() AND role='Doctor') THEN
 IF NOT hf_security.is_visit_doctor(OLD.doctor_id) THEN RAISE EXCEPTION 'Only the assigned doctor can manage this consultation' USING ERRCODE='42501';END IF;
 IF NEW.status='In consultation' THEN INSERT INTO hospitalflow.patient_access_grants(user_id,patient_id,purpose,expires_at,granted_by) VALUES(hf_security.actor_id(),NEW.patient_id,'Assigned appointment consultation',now()+interval '30 days',hf_security.actor_id());END IF;
 END IF;RETURN NEW;END $$;
CREATE TRIGGER doctor_visit BEFORE UPDATE ON hospitalflow.appointments FOR EACH ROW EXECUTE FUNCTION hf_security.guard_doctor_visit();
-- Reception still manages the queue; assigned Doctors can advance their own visits.
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.set_appointment_status(text,text)'::regprocedure) INTO definition;
 definition:=replace(definition,'require_actor(ARRAY[''Reception''])','require_actor(ARRAY[''Reception'',''Doctor''])');EXECUTE definition;
 SELECT pg_get_functiondef('hf_api.execute(text,jsonb,uuid,text)'::regprocedure) INTO definition;
 definition:=replace(definition,'allowed:=CASE','allowed:=CASE WHEN p_action=''appointment-status'' THEN ARRAY[''Reception'',''Doctor'']');EXECUTE definition;
END $$;
CREATE FUNCTION hf_api.prescribe_visit(p_appointment text,p_payload jsonb,p_key uuid,p_hash text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text;a hospitalflow.appointments%ROWTYPE;rx text;BEGIN
 actor:=hf_api.booking_actor();PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO a FROM hospitalflow.appointments WHERE id=p_appointment AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 IF NOT FOUND OR NOT hf_security.is_visit_doctor(a.doctor_id) THEN RAISE EXCEPTION 'Only the assigned doctor can prescribe for this visit' USING ERRCODE='42501';END IF;
 IF a.status NOT IN ('In consultation','Completed') THEN RAISE EXCEPTION 'Start the consultation before prescribing' USING ERRCODE='23514';END IF;
 IF p_payload ? 'patientId' AND p_payload->>'patientId' IS DISTINCT FROM a.patient_id THEN RAISE EXCEPTION 'Prescription patient must match the selected appointment' USING ERRCODE='23514';END IF;
 rx:=hf_api.execute('prescription',p_payload||jsonb_build_object('patientId',a.patient_id),p_key,p_hash);
 INSERT INTO hospitalflow.prescription_visits(prescription_id,appointment_id) VALUES(rx,a.id) ON CONFLICT(prescription_id) DO NOTHING;
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.prescription_visits WHERE prescription_id=rx AND appointment_id=a.id) THEN RAISE EXCEPTION 'Prescription already belongs to a different visit' USING ERRCODE='23514';END IF;
 RETURN rx;
END $$;
REVOKE ALL ON hospitalflow.prescription_visits FROM PUBLIC;
REVOKE ALL ON FUNCTION hf_security.is_visit_doctor(text),hf_security.guard_doctor_visit(),hf_api.prescribe_visit(text,jsonb,uuid,text) FROM PUBLIC;
CREATE OR REPLACE FUNCTION hf_api.medication_care() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$
DECLARE actor text;role_name text;pid text;BEGIN
 actor:=hf_api.booking_actor();SELECT role INTO role_name FROM hospitalflow.users WHERE id=actor;SELECT patient_id INTO pid FROM hospitalflow.patient_accounts WHERE user_id=actor;
 IF pid IS NULL AND role_name NOT IN ('Doctor','Nurse','Admin','Developer') AND NOT EXISTS(SELECT 1 FROM hospitalflow.user_permissions WHERE user_id=actor AND permission='Pharmacist') THEN RAISE EXCEPTION 'Clinical care access is required' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('visits',(SELECT COALESCE(jsonb_agg(a.id),'[]') FROM hospitalflow.appointments a WHERE a.hospital_id=hf_security.current_hospital() AND hf_security.is_visit_doctor(a.doctor_id)),'prescriptions',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'patientId',p.patient_id,'patientName',pt.name,'patientCode',pt.registration_id,'medicine',m.name,'quantity',p.quantity,'instructions',p.instructions,'status',p.status,'createdAt',p.created_at,'appointmentId',(SELECT appointment_id FROM hospitalflow.prescription_visits WHERE prescription_id=p.id),'visitAt',(SELECT a.at FROM hospitalflow.prescription_visits v JOIN hospitalflow.appointments a ON a.id=v.appointment_id WHERE v.prescription_id=p.id),'prescriber',(SELECT u.name FROM hospitalflow.prescription_authors pa JOIN hospitalflow.users u ON u.id=pa.created_by WHERE pa.prescription_id=p.id),'billId',(SELECT bill_id FROM hospitalflow.prescription_dispensations WHERE prescription_id=p.id),'dispensedAt',(SELECT at FROM hospitalflow.prescription_dispensations WHERE prescription_id=p.id),'provided',COALESCE((SELECT sum(a.quantity) FROM hospitalflow.medication_administrations a WHERE a.prescription_id=p.id),0)) ORDER BY p.created_at DESC),'[]') FROM hospitalflow.prescriptions p JOIN hospitalflow.patients pt ON pt.id=p.patient_id JOIN hospitalflow.medicine_batches m ON m.id=p.medicine_id WHERE p.hospital_id=hf_security.current_hospital() AND (CASE WHEN pid IS NOT NULL THEN p.patient_id=pid ELSE hf_security.can_access_patient(p.patient_id) OR EXISTS(SELECT 1 FROM hospitalflow.user_permissions WHERE user_id=actor AND permission='Pharmacist') END)),
 'administrations',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',a.id,'prescriptionId',a.prescription_id,'patientId',a.patient_id,'quantity',a.quantity,'providedAt',a.provided_at,'providedBy',u.name,'staffId',u.registration_id,'note',a.note) ORDER BY a.provided_at DESC),'[]') FROM hospitalflow.medication_administrations a JOIN hospitalflow.users u ON u.id=a.provided_by WHERE a.hospital_id=hf_security.current_hospital() AND (CASE WHEN pid IS NOT NULL THEN a.patient_id=pid ELSE hf_security.can_access_patient(a.patient_id) END)));
END $$;
REVOKE ALL ON FUNCTION hf_api.medication_care() FROM PUBLIC;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.024_visit_prescriptions.sql','5394717203ABE5C6F9F1ADEB4C5461B1F26252022F871127C22E8CA020C8716D');

-- 025_complete_care_flow.sql
-- Clinical coordination is append-only where it records an event, observation or completed dose.
CREATE TABLE hospitalflow.care_plans(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),doctor_id text NOT NULL REFERENCES hospitalflow.users(id),nurse_id text REFERENCES hospitalflow.users(id),appointment_id text REFERENCES hospitalflow.appointments(id),admission_id text UNIQUE REFERENCES hospitalflow.admissions(id),requested_ward text REFERENCES hospitalflow.wards(name),planned_days integer NOT NULL CHECK(planned_days BETWEEN 1 AND 365),nursing_days integer CHECK(nursing_days BETWEEN 1 AND 365),nursing_notes text,diagnosis text NOT NULL CHECK(length(diagnosis) BETWEEN 1 AND 2000),instructions text NOT NULL CHECK(length(instructions) BETWEEN 1 AND 4000),status text NOT NULL DEFAULT 'Requested' CHECK(status IN ('Requested','Accepted','Admitted','Discharged')),created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.care_observations(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),admission_id text NOT NULL REFERENCES hospitalflow.admissions(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),recorded_by text NOT NULL REFERENCES hospitalflow.users(id),at timestamptz NOT NULL DEFAULT now(),health_status text NOT NULL CHECK(length(health_status) BETWEEN 1 AND 1000),vitals jsonb NOT NULL DEFAULT '{}',progress text NOT NULL CHECK(length(progress) BETWEEN 1 AND 2000),notes text NOT NULL CHECK(length(notes) BETWEEN 1 AND 4000));
CREATE TABLE hospitalflow.medication_doses(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),prescription_id text NOT NULL REFERENCES hospitalflow.prescriptions(id),admission_id text REFERENCES hospitalflow.admissions(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),dose text NOT NULL CHECK(length(dose) BETWEEN 1 AND 200),quantity integer NOT NULL CHECK(quantity>0),scheduled_at timestamptz NOT NULL,created_by text NOT NULL REFERENCES hospitalflow.users(id),status text NOT NULL DEFAULT 'Scheduled' CHECK(status IN ('Scheduled','Given','Not given')),actual_at timestamptz,recorded_by text REFERENCES hospitalflow.users(id),recorded_at timestamptz,remarks text,administration_id uuid REFERENCES hospitalflow.medication_administrations(id),CHECK((status='Scheduled' AND recorded_at IS NULL AND actual_at IS NULL) OR(status='Given' AND actual_at IS NOT NULL AND recorded_at IS NOT NULL AND administration_id IS NOT NULL) OR(status='Not given' AND actual_at IS NULL AND recorded_at IS NOT NULL AND administration_id IS NULL)));
CREATE TABLE hospitalflow.pharmacy_requests(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),prescription_id text NOT NULL REFERENCES hospitalflow.prescriptions(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),requested_by text NOT NULL REFERENCES hospitalflow.users(id),at timestamptz NOT NULL DEFAULT now(),comments text NOT NULL CHECK(length(comments) BETWEEN 1 AND 1000));
CREATE TABLE hospitalflow.care_discharge_reviews(admission_id text PRIMARY KEY REFERENCES hospitalflow.admissions(id),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),nurse_id text NOT NULL REFERENCES hospitalflow.users(id),final_condition text NOT NULL,nurse_remarks text NOT NULL,prepared_at timestamptz NOT NULL DEFAULT now(),doctor_id text REFERENCES hospitalflow.users(id),approved_at timestamptz,diagnosis text,treatment text,discharge_medications text,follow_up text,doctor_remarks text,completed_by text REFERENCES hospitalflow.users(id),completed_at timestamptz);
CREATE TABLE hospitalflow.care_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),activity text NOT NULL,actor_id text REFERENCES hospitalflow.users(id),actor_name text NOT NULL,at timestamptz NOT NULL DEFAULT now(),comments text NOT NULL,reference text NOT NULL,details jsonb NOT NULL DEFAULT '{}');
CREATE INDEX care_events_patient ON hospitalflow.care_events(hospital_id,patient_id,at);
CREATE INDEX medication_doses_due ON hospitalflow.medication_doses(hospital_id,scheduled_at,status);
CREATE TABLE hospitalflow.care_rates(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),ward text NOT NULL REFERENCES hospitalflow.wards(name),effective_from date NOT NULL,bed_daily numeric(12,2) NOT NULL CHECK(bed_daily>=0),ward_daily numeric(12,2) NOT NULL CHECK(ward_daily>=0),icu_daily numeric(12,2) NOT NULL CHECK(icu_daily>=0),nursing_daily numeric(12,2) NOT NULL CHECK(nursing_daily>=0),configured_by text NOT NULL REFERENCES hospitalflow.users(id),created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(hospital_id,ward,effective_from));
CREATE TABLE hospitalflow.care_invoices(admission_id text PRIMARY KEY REFERENCES hospitalflow.admissions(id),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),bill_id text NOT NULL UNIQUE REFERENCES hospitalflow.bills(id));
CREATE TABLE hospitalflow.care_charge_entries(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),admission_id text NOT NULL REFERENCES hospitalflow.admissions(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),charge_day date NOT NULL,category text NOT NULL CHECK(category IN ('Bed','Ward','ICU','Nursing')),amount numeric(12,2) NOT NULL CHECK(amount>=0),rate_id uuid NOT NULL REFERENCES hospitalflow.care_rates(id),bed_id text NOT NULL REFERENCES hospitalflow.beds(id),line_id text UNIQUE REFERENCES hospitalflow.bill_lines(id),created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(admission_id,charge_day,category));
CREATE TABLE hospitalflow.care_command_keys(actor_id text NOT NULL REFERENCES hospitalflow.users(id),key uuid NOT NULL,action text NOT NULL,request_hash text NOT NULL,reference text NOT NULL,PRIMARY KEY(actor_id,key));
CREATE FUNCTION hf_security.care_role(p_roles text[]) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ SELECT EXISTS(SELECT 1 FROM hospitalflow.users u WHERE u.id=hf_security.actor_id() AND u.active AND (EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships m WHERE m.user_id=u.id AND m.hospital_id=hf_security.current_hospital() AND m.active) OR u.role='Developer' OR EXISTS(SELECT 1 FROM hospitalflow.network_operators o WHERE o.user_id=u.id)) AND (u.role='Developer' OR u.role=ANY(p_roles) OR(u.role='User' AND EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id AND p.permission=ANY(p_roles))))) $$;
CREATE FUNCTION hf_security.can_read_care(p_patient text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ SELECT EXISTS(SELECT 1 FROM hospitalflow.users u WHERE u.id=hf_security.actor_id() AND u.active AND (EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships m WHERE m.user_id=u.id AND m.hospital_id=hf_security.current_hospital() AND m.active) OR u.role='Developer' OR EXISTS(SELECT 1 FROM hospitalflow.network_operators o WHERE o.user_id=u.id)) AND (hf_security.own_patient(p_patient) OR hf_security.can_access_patient(p_patient) OR (hf_security.care_role(ARRAY['Doctor','Nurse']) AND EXISTS(SELECT 1 FROM hospitalflow.care_plans p WHERE p.patient_id=p_patient AND p.hospital_id=hf_security.current_hospital() AND (p.doctor_id=u.id OR p.nurse_id=u.id OR(p.nurse_id IS NULL AND hf_security.care_role(ARRAY['Nurse']))))))) $$;
CREATE FUNCTION hf_api.care_event(p_patient text,p_activity text,p_comments text,p_ref text,p_details jsonb DEFAULT '{}') RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ BEGIN INSERT INTO hospitalflow.care_events(patient_id,activity,actor_id,actor_name,comments,reference,details) SELECT p_patient,p_activity,u.id,COALESCE(u.name,'System'),p_comments,p_ref,p_details FROM (SELECT 1)x LEFT JOIN hospitalflow.users u ON u.id=hf_security.actor_id();END $$;
DO $$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['care_plans','care_observations','medication_doses','pharmacy_requests','care_discharge_reviews','care_events','care_rates','care_invoices','care_charge_entries'] LOOP
 EXECUTE format('ALTER TABLE hospitalflow.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('CREATE POLICY hospital_scope ON hospitalflow.%I USING(hospital_id=hf_security.current_hospital()) WITH CHECK(hospital_id=hf_security.current_hospital())',t);
 IF t<>'care_events' THEN EXECUTE format('CREATE TRIGGER z_hospital_guard BEFORE INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hf_security.guard_hospital_row()',t);END IF;
 IF t<>'care_events' THEN EXECUTE format('CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history()',t);END IF;
 END LOOP;
 FOREACH t IN ARRAY ARRAY['care_observations','pharmacy_requests','care_events','care_rates','care_invoices','care_charge_entries','care_command_keys'] LOOP EXECUTE format('CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes()',t);END LOOP;END $$;
-- Source event triggers also cover existing consultation, pharmacy and nursing entry points.
CREATE FUNCTION hf_security.capture_care_activity() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$ DECLARE pid text;label text;comment text;ref text;original_hospital text;BEGIN
 ref:=NEW.id::text;
 IF TG_TABLE_NAME='patients' THEN pid:=NEW.id;label:='Patient registered';comment:=NEW.name||' · '||NEW.registration_id;
 ELSIF TG_TABLE_NAME='appointments' THEN pid:=NEW.patient_id;label:=CASE WHEN TG_OP='INSERT' THEN 'Appointment booked' ELSE 'Consultation / appointment update' END;comment:=NEW.status||' · '||NEW.type;
 ELSIF TG_TABLE_NAME='admission_events' THEN SELECT patient_id INTO pid FROM hospitalflow.admissions WHERE id=NEW.admission_id;label:=NEW.kind||' details';comment:=NEW.reason;
 ELSIF TG_TABLE_NAME='notes' THEN pid:=NEW.patient_id;label:='Treatment / nursing note';comment:=NEW.text;
 ELSIF TG_TABLE_NAME='prescriptions' THEN pid:=NEW.patient_id;label:=CASE WHEN TG_OP='INSERT' THEN 'Prescription created' ELSE 'Prescription status updated' END;comment:=NEW.status||' · '||NEW.instructions;
 ELSIF TG_TABLE_NAME='prescription_dispensations' THEN SELECT patient_id INTO pid FROM hospitalflow.prescriptions WHERE id=NEW.prescription_id;label:='Medicine issued';comment:='Prescription '||NEW.prescription_id||' · invoice '||NEW.bill_id;
 ELSIF TG_TABLE_NAME='referrals' THEN original_hospital:=hf_security.current_hospital();PERFORM set_config('hospitalflow.hospital_id',NEW.source_hospital_id,true);pid:=NEW.patient_id;label:='Specialist referral';comment:=NEW.reason||' · '||NEW.status;
 ELSIF TG_TABLE_NAME='admissions' THEN pid:=NEW.patient_id;label:=CASE WHEN TG_OP='INSERT' THEN 'Ward / bed assignment' WHEN NEW.status='Discharged' THEN 'Discharged' ELSE 'Bed assignment updated' END;comment:=NEW.reason||' · bed '||NEW.bed_id;
 ELSE pid:=NEW.patient_id;label:='Medicine administered';comment:=NEW.quantity||' units · '||NEW.note;END IF;
 PERFORM hf_api.care_event(pid,label,comment,ref,to_jsonb(NEW));IF original_hospital IS NOT NULL THEN PERFORM set_config('hospitalflow.hospital_id',original_hospital,true);END IF;RETURN NEW;END $$;
CREATE TRIGGER care_activity AFTER INSERT ON hospitalflow.patients FOR EACH ROW EXECUTE FUNCTION hf_security.capture_care_activity();
CREATE TRIGGER care_activity AFTER INSERT OR UPDATE OF status ON hospitalflow.appointments FOR EACH ROW EXECUTE FUNCTION hf_security.capture_care_activity();
CREATE TRIGGER care_activity AFTER INSERT OR UPDATE ON hospitalflow.referrals FOR EACH ROW EXECUTE FUNCTION hf_security.capture_care_activity();
CREATE TRIGGER care_activity AFTER INSERT ON hospitalflow.notes FOR EACH ROW EXECUTE FUNCTION hf_security.capture_care_activity();
CREATE TRIGGER care_activity AFTER INSERT OR UPDATE OF status ON hospitalflow.prescriptions FOR EACH ROW EXECUTE FUNCTION hf_security.capture_care_activity();
CREATE TRIGGER care_activity AFTER INSERT ON hospitalflow.admission_events FOR EACH ROW EXECUTE FUNCTION hf_security.capture_care_activity();
CREATE TRIGGER care_activity AFTER INSERT ON hospitalflow.prescription_dispensations FOR EACH ROW EXECUTE FUNCTION hf_security.capture_care_activity();
CREATE TRIGGER care_activity AFTER INSERT OR UPDATE ON hospitalflow.admissions FOR EACH ROW EXECUTE FUNCTION hf_security.capture_care_activity();
CREATE TRIGGER care_activity AFTER INSERT ON hospitalflow.medication_administrations FOR EACH ROW EXECUTE FUNCTION hf_security.capture_care_activity();
-- Keep source timestamps and known authors when importing earlier history.
INSERT INTO hospitalflow.care_events(hospital_id,patient_id,activity,actor_id,actor_name,at,comments,reference)
 SELECT a.hospital_id,a.patient_id,'Appointment booked',u.id,COALESCE(u.name,'Earlier booking record'),COALESCE(b.created_at,h.occurred_at,a.at),a.status||' · '||a.type||CASE WHEN b.created_at IS NULL AND h.occurred_at IS NULL THEN ' (booking timestamp unavailable; displayed timestamp is visit time)' ELSE '' END,a.id FROM hospitalflow.appointments a LEFT JOIN hospitalflow.appointment_bookings b ON b.appointment_id=a.id LEFT JOIN LATERAL(SELECT actor_id,occurred_at FROM hospitalflow.row_history WHERE table_name='appointments' AND record_id=a.id AND operation='INSERT' ORDER BY occurred_at,id LIMIT 1)h ON true LEFT JOIN hospitalflow.users u ON u.id=COALESCE(b.created_by,h.actor_id);
INSERT INTO hospitalflow.care_events(hospital_id,patient_id,activity,actor_id,actor_name,at,comments,reference)
 SELECT p.hospital_id,p.patient_id,'Prescription created',pa.created_by,COALESCE(u.name,'Earlier clinical record'),p.created_at,p.instructions,p.id FROM hospitalflow.prescriptions p LEFT JOIN hospitalflow.prescription_authors pa ON pa.prescription_id=p.id LEFT JOIN hospitalflow.users u ON u.id=pa.created_by;
INSERT INTO hospitalflow.care_events(hospital_id,patient_id,activity,actor_id,actor_name,at,comments,reference)
 SELECT a.hospital_id,a.patient_id,'Medicine administered',a.provided_by,u.name,a.provided_at,a.quantity||' units · '||a.note,a.id::text FROM hospitalflow.medication_administrations a JOIN hospitalflow.users u ON u.id=a.provided_by;
INSERT INTO hospitalflow.care_events(hospital_id,patient_id,activity,actor_id,actor_name,at,comments,reference)
 SELECT e.hospital_id,a.patient_id,e.kind,e.actor_id,u.name,e.at,e.reason,e.admission_id FROM hospitalflow.admission_events e JOIN hospitalflow.admissions a ON a.id=e.admission_id JOIN hospitalflow.users u ON u.id=e.actor_id;
INSERT INTO hospitalflow.care_events(hospital_id,patient_id,activity,actor_name,at,comments,reference)
 SELECT n.hospital_id,n.patient_id,'Treatment / nursing note',COALESCE(u.name,'Earlier clinical record (author unavailable)'),n.at,n.text,n.id FROM hospitalflow.notes n LEFT JOIN LATERAL(SELECT actor_id FROM hospitalflow.row_history WHERE table_name='notes' AND record_id=n.id AND operation='INSERT' ORDER BY occurred_at,id LIMIT 1)h ON true LEFT JOIN hospitalflow.users u ON u.id=h.actor_id;
INSERT INTO hospitalflow.care_events(hospital_id,patient_id,activity,actor_id,actor_name,at,comments,reference)
 SELECT d.hospital_id,p.patient_id,'Medicine issued',d.dispensed_by,u.name,d.at,'Prescription '||d.prescription_id||' · invoice '||d.bill_id,d.id::text FROM hospitalflow.prescription_dispensations d JOIN hospitalflow.prescriptions p ON p.id=d.prescription_id JOIN hospitalflow.users u ON u.id=d.dispensed_by;
INSERT INTO hospitalflow.care_events(hospital_id,patient_id,activity,actor_id,actor_name,at,comments,reference)
 SELECT p.hospital_id,p.id,'Patient registered',u.id,COALESCE(u.name,'Earlier registration record'),COALESCE(h.occurred_at,p.created),p.name||' · '||p.registration_id,p.id FROM hospitalflow.patients p LEFT JOIN LATERAL(SELECT actor_id,occurred_at FROM hospitalflow.row_history WHERE table_name='patients' AND record_id=p.id AND operation='INSERT' ORDER BY occurred_at,id LIMIT 1)h ON true LEFT JOIN hospitalflow.users u ON u.id=h.actor_id;
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.care_events FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE TRIGGER z_hospital_guard BEFORE INSERT OR UPDATE OR DELETE ON hospitalflow.care_events FOR EACH ROW EXECUTE FUNCTION hf_security.guard_hospital_row();
CREATE UNIQUE INDEX care_patient_open_plan ON hospitalflow.care_plans(hospital_id,patient_id) WHERE status<>'Discharged';
CREATE FUNCTION hf_api.accrue_stay_charges(p_admission text,p_strict boolean DEFAULT false) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE a hospitalflow.admissions%ROWTYPE;r hospitalflow.care_rates%ROWTYPE;assignment record;day date;last_day date;invoice text;line text;kind text;amount numeric;original_actor text:=hf_security.actor_id();BEGIN
 IF nullif(hf_security.actor_id(),'') IS NOT NULL AND NOT hf_security.care_role(ARRAY['Admin','Billing','Doctor','Nurse']) THEN RAISE EXCEPTION 'Care billing staff required' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(74192301);SELECT * INTO STRICT a FROM hospitalflow.admissions WHERE id=p_admission AND hospital_id=hf_security.current_hospital();
 IF nullif(original_actor,'') IS NOT NULL AND NOT hf_security.can_read_care(a.patient_id) AND NOT hf_security.care_role(ARRAY['Admin','Billing']) THEN RAISE EXCEPTION 'Patient care access required for charge calculation' USING ERRCODE='42501';END IF;
 PERFORM set_config('hospitalflow.actor_id','',true);
 SELECT bill_id INTO invoice FROM hospitalflow.care_invoices WHERE admission_id=a.id;
 last_day:=(COALESCE(a.discharged,now()) AT TIME ZONE 'Asia/Kolkata')::date;
 FOR day IN SELECT generate_series((a.at AT TIME ZONE 'Asia/Kolkata')::date,last_day,'1 day')::date LOOP
 SELECT ba.bed_id,b.ward,b.category INTO assignment FROM hospitalflow.bed_assignments ba JOIN hospitalflow.beds b ON b.id=ba.bed_id WHERE ba.admission_id=a.id AND ba.from_time<((day+1)::timestamp AT TIME ZONE 'Asia/Kolkata') AND COALESCE(ba.to_time,now())>=day::timestamp AT TIME ZONE 'Asia/Kolkata' ORDER BY ba.from_time ASC LIMIT 1;
 SELECT * INTO r FROM hospitalflow.care_rates WHERE hospital_id=a.hospital_id AND ward=assignment.ward AND effective_from<=day ORDER BY effective_from DESC LIMIT 1;
 IF NOT FOUND THEN IF p_strict THEN RAISE EXCEPTION 'Configure dated bed/ward/ICU/nursing rates before final billing for %',assignment.ward USING ERRCODE='23514';END IF;CONTINUE;END IF;
 IF invoice IS NULL THEN invoice:=hf_api.new_id('INV');INSERT INTO hospitalflow.bills(id,patient_id) VALUES(invoice,a.patient_id);INSERT INTO hospitalflow.care_invoices(admission_id,bill_id) VALUES(a.id,invoice);END IF;
 FOREACH kind IN ARRAY ARRAY['Bed','Ward','ICU','Nursing'] LOOP
 IF EXISTS(SELECT 1 FROM hospitalflow.care_charge_entries WHERE admission_id=a.id AND charge_day=day AND category=kind) THEN CONTINUE;END IF;
 amount:=CASE kind WHEN 'Bed' THEN r.bed_daily WHEN 'Ward' THEN r.ward_daily WHEN 'ICU' THEN CASE WHEN assignment.category ILIKE '%ICU%' OR assignment.ward ILIKE '%ICU%' THEN r.icu_daily ELSE 0 END ELSE r.nursing_daily END;
 line:=NULL;IF amount>0 THEN line:=hf_api.new_id('LINE');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(line,invoice,kind||' · '||assignment.ward||' · '||day,amount);END IF;
 INSERT INTO hospitalflow.care_charge_entries(admission_id,patient_id,charge_day,category,amount,rate_id,bed_id,line_id) VALUES(a.id,a.patient_id,day,kind,amount,r.id,assignment.bed_id,line);
 PERFORM hf_api.care_event(a.patient_id,'Daily charge',kind||' · '||day||' · INR '||amount,COALESCE(line,a.id||':'||day||':'||kind),jsonb_build_object('category',kind,'amount',amount,'day',day,'invoice',invoice));
 END LOOP;END LOOP;PERFORM set_config('hospitalflow.actor_id',COALESCE(original_actor,''),true);RETURN invoice;
END $$;
CREATE TABLE hospitalflow.care_extra_categories(line_id text PRIMARY KEY REFERENCES hospitalflow.bill_lines(id),category text NOT NULL);
CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.care_extra_categories FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes();
CREATE TABLE hospitalflow.care_managed_orders(order_id uuid PRIMARY KEY REFERENCES hospitalflow.clinical_orders(id),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id));
CREATE FUNCTION hf_api.care_command(p_action text,p jsonb,p_key uuid,p_hash text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,hf_security,pg_temp AS $$
DECLARE actor text;pid text;result text;old hospitalflow.care_command_keys%ROWTYPE;plan hospitalflow.care_plans%ROWTYPE;adm hospitalflow.admissions%ROWTYPE;dose_row hospitalflow.medication_doses%ROWTYPE;review hospitalflow.care_discharge_reviews%ROWTYPE;rx hospitalflow.prescriptions%ROWTYPE;number integer;quantity integer;actual timestamptz;note text;item jsonb;payload jsonb;approval uuid;bill text;kind text;BEGIN
 actor:=hf_api.booking_actor();PERFORM pg_advisory_xact_lock(74192301);
 IF p_key IS NULL OR p_hash!~'^[A-Fa-f0-9]{64}$' OR jsonb_typeof(p)<>'object' THEN RAISE EXCEPTION 'A valid retry key and object are required' USING ERRCODE='23514';END IF;
 SELECT * INTO old FROM hospitalflow.care_command_keys WHERE actor_id=actor AND key=p_key;IF FOUND THEN IF old.action<>p_action OR old.request_hash<>p_hash THEN RAISE EXCEPTION 'Retry key already used for another change' USING ERRCODE='23514';END IF;RETURN old.reference;END IF;
 note:=COALESCE(NULLIF(btrim(p->>'comments'),''),NULLIF(btrim(p->>'notes'),''));
 IF p_action='rate' THEN
 IF NOT hf_security.care_role(ARRAY['Admin']) THEN RAISE EXCEPTION 'Admin configures hospital rates' USING ERRCODE='42501';END IF;
 IF (p->>'effectiveFrom')::date<date '1900-01-01' THEN RAISE EXCEPTION 'Enter a valid rate effective date' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each_text(p) v WHERE v.key IN ('bedDaily','wardDaily','icuDaily','nursingDaily') AND ((v.value::numeric)<0 OR v.value::numeric>10000000 OR v.value::numeric<>round(v.value::numeric,2))) THEN RAISE EXCEPTION 'Rates require nonnegative amounts with at most two decimals' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.care_rates(ward,effective_from,bed_daily,ward_daily,icu_daily,nursing_daily,configured_by) VALUES(hf_api.required_text(p,'ward'),(p->>'effectiveFrom')::date,(p->>'bedDaily')::numeric,(p->>'wardDaily')::numeric,(p->>'icuDaily')::numeric,(p->>'nursingDaily')::numeric,actor) RETURNING id::text INTO result;
 ELSIF p_action='admission-request' THEN
 pid:=hf_api.required_text(p,'patientId');IF NOT hf_security.care_role(ARRAY['Doctor']) OR NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'A treating Doctor must request admission' USING ERRCODE='42501';END IF;
 IF p->>'nurseId' IS NOT NULL AND p->>'nurseId'<>'' AND NOT EXISTS(SELECT 1 FROM hospitalflow.users u JOIN hospitalflow.hospital_memberships m ON m.user_id=u.id WHERE u.id=p->>'nurseId' AND u.role IN ('Nurse','Developer') AND u.active AND m.hospital_id=hf_security.current_hospital() AND m.active) THEN RAISE EXCEPTION 'Choose a Nurse assigned to this hospital' USING ERRCODE='23514';END IF;
 IF NULLIF(p->>'admissionId','') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hospitalflow.admissions WHERE id=p->>'admissionId' AND patient_id=pid AND hospital_id=hf_security.current_hospital() AND status='Admitted') THEN RAISE EXCEPTION 'Choose this patient active admission' USING ERRCODE='23514';END IF;
 IF NULLIF(p->>'appointmentId','') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hospitalflow.appointments WHERE id=p->>'appointmentId' AND patient_id=pid AND hospital_id=hf_security.current_hospital()) THEN RAISE EXCEPTION 'Appointment must belong to this patient and hospital' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.care_plans(patient_id,doctor_id,nurse_id,appointment_id,admission_id,requested_ward,planned_days,diagnosis,instructions,status) VALUES(pid,actor,NULLIF(p->>'nurseId',''),NULLIF(p->>'appointmentId',''),NULLIF(p->>'admissionId',''),NULLIF(p->>'ward',''),(p->>'days')::integer,hf_api.required_text(p,'diagnosis',2000),hf_api.required_text(p,'instructions',4000),CASE WHEN NULLIF(p->>'admissionId','') IS NOT NULL THEN 'Admitted' ELSE 'Requested' END) RETURNING id::text INTO result;
 INSERT INTO hospitalflow.patient_access_grants(user_id,patient_id,purpose,expires_at,granted_by) SELECT u,pid,'Managed admission care',now()+make_interval(days => COALESCE((p->>'days')::integer,5)+30),actor FROM unnest(ARRAY[actor,NULLIF(p->>'nurseId','')]) u WHERE u IS NOT NULL;
 ELSIF p_action IN ('accept-admission','assign-bed','extend-plan') THEN
 SELECT * INTO STRICT plan FROM hospitalflow.care_plans WHERE id=(p->>'id')::uuid AND hospital_id=hf_security.current_hospital() FOR UPDATE;pid:=plan.patient_id;
 IF p_action='extend-plan' THEN IF NOT hf_security.care_role(ARRAY['Doctor']) OR (plan.doctor_id<>actor AND NOT hf_security.care_role(ARRAY['Developer'])) OR plan.status='Discharged' THEN RAISE EXCEPTION 'Only the treating Doctor can update the treatment plan' USING ERRCODE='42501';END IF;
 UPDATE hospitalflow.care_plans SET planned_days=(p->>'days')::integer,nursing_days=(p->>'days')::integer,instructions=hf_api.required_text(p,'instructions',4000),updated_at=now() WHERE id=plan.id;
 ELSE
 IF NOT hf_security.care_role(ARRAY['Nurse']) OR plan.status='Discharged' OR(plan.nurse_id IS NOT NULL AND plan.nurse_id<>actor AND NOT hf_security.care_role(ARRAY['Developer'])) THEN RAISE EXCEPTION 'Assigned nursing staff are required' USING ERRCODE='42501';END IF;
 UPDATE hospitalflow.care_plans SET nurse_id=actor,status=CASE WHEN admission_id IS NULL THEN 'Accepted' ELSE status END,updated_at=now() WHERE id=plan.id;
 INSERT INTO hospitalflow.patient_access_grants(user_id,patient_id,purpose,expires_at,granted_by) VALUES(actor,pid,'Accepted nursing admission care',now()+make_interval(days => plan.planned_days+30),actor);
 IF p_action='assign-bed' THEN
 IF plan.admission_id IS NOT NULL THEN RAISE EXCEPTION 'Use the bed transfer workflow for an existing admission' USING ERRCODE='23514';END IF;
 IF plan.requested_ward IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hospitalflow.beds WHERE id=p->>'bedId' AND ward=plan.requested_ward AND hospital_id=hf_security.current_hospital()) THEN RAISE EXCEPTION 'Choose an available bed in the requested ward' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.care_plans SET nursing_days=COALESCE((p->>'confirmedDays')::integer,plan.planned_days),nursing_notes=hf_api.required_text(p,'nursingNotes',2000) WHERE id=plan.id;
 result:=hf_api.execute('admit',jsonb_build_object('patientId',pid,'bedId',hf_api.required_text(p,'bedId'),'reason',plan.diagnosis||' · '||plan.instructions),p_key,p_hash);
 UPDATE hospitalflow.care_plans SET admission_id=result,status='Admitted',updated_at=now() WHERE id=plan.id;PERFORM hf_api.accrue_stay_charges(result);
 END IF;END IF;result:=COALESCE(result,plan.id::text);
 ELSIF p_action='monitor' THEN
 SELECT * INTO STRICT adm FROM hospitalflow.admissions WHERE id=p->>'admissionId' AND hospital_id=hf_security.current_hospital() AND status='Admitted';pid:=adm.patient_id;
 IF NOT hf_security.care_role(ARRAY['Nurse']) OR NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'Nursing care access is required' USING ERRCODE='42501';END IF;
 payload:=COALESCE(p->'vitals','{}');IF jsonb_typeof(payload)<>'object' OR length(payload::text)>2000 THEN RAISE EXCEPTION 'Vitals must be an object of recorded measurements' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(payload) j WHERE j.key NOT IN ('temperatureC','systolicBP','diastolicBP','pulseBpm','respirationsPerMin','oxygenSaturationPct') OR jsonb_typeof(j.value)<>'number') THEN RAISE EXCEPTION 'Enter numeric vital measurements using the displayed fields' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.care_observations(admission_id,patient_id,recorded_by,health_status,vitals,progress,notes) VALUES(adm.id,pid,actor,hf_api.required_text(p,'healthStatus',1000),payload,hf_api.required_text(p,'progress',2000),hf_api.required_text(p,'notes',4000)) RETURNING id::text INTO result;
 PERFORM hf_api.accrue_stay_charges(adm.id);
 ELSIF p_action IN ('send-pharmacy','schedule-dose') THEN
 SELECT * INTO STRICT rx FROM hospitalflow.prescriptions WHERE id=p->>'prescriptionId' AND hospital_id=hf_security.current_hospital();pid:=rx.patient_id;
 IF NOT hf_security.can_read_care(pid) OR (p_action='schedule-dose' AND NOT hf_security.care_role(ARRAY['Doctor','Nurse'])) THEN RAISE EXCEPTION 'Care access is required' USING ERRCODE='42501';END IF;
 IF rx.status='Cancelled' THEN RAISE EXCEPTION 'Cancelled prescriptions cannot be used' USING ERRCODE='23514';END IF;
 IF p_action='send-pharmacy' THEN IF rx.status<>'Pending' THEN RAISE EXCEPTION 'This prescription is already fulfilled or cancelled' USING ERRCODE='23514';END IF;IF NOT(hf_security.care_role(ARRAY['Doctor','Nurse']) OR hf_security.own_patient(pid)) THEN RAISE EXCEPTION 'Patient, Doctor or Nurse access required' USING ERRCODE='42501';END IF;
 INSERT INTO hospitalflow.pharmacy_requests(prescription_id,patient_id,requested_by,comments) VALUES(rx.id,pid,actor,hf_api.required_text(p,'comments',1000)) RETURNING id::text INTO result;
 ELSE
 quantity:=(p->>'quantity')::integer;IF quantity<1 OR quantity+COALESCE((SELECT sum(d.quantity) FROM hospitalflow.medication_doses d WHERE d.prescription_id=rx.id AND status='Scheduled'),0)+COALESCE((SELECT sum(a.quantity) FROM hospitalflow.medication_administrations a WHERE a.prescription_id=rx.id),0)>rx.quantity THEN RAISE EXCEPTION 'Dose schedule exceeds the remaining prescribed quantity' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.medication_doses(prescription_id,admission_id,patient_id,dose,quantity,scheduled_at,created_by) VALUES(rx.id,(SELECT id FROM hospitalflow.admissions WHERE patient_id=pid AND hospital_id=hf_security.current_hospital() AND status='Admitted'),pid,hf_api.required_text(p,'dose',200),quantity,(p->>'scheduledAt')::timestamptz,actor) RETURNING id::text INTO result;END IF;
 ELSIF p_action='record-dose' THEN
 SELECT * INTO STRICT dose_row FROM hospitalflow.medication_doses WHERE id=(p->>'id')::uuid AND hospital_id=hf_security.current_hospital() FOR UPDATE;pid:=dose_row.patient_id;
 IF NOT hf_security.care_role(ARRAY['Nurse']) OR NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'Nursing care access required' USING ERRCODE='42501';END IF;
 IF dose_row.status<>'Scheduled' THEN RAISE EXCEPTION 'Dose outcome already recorded; create a new schedule for a later dose' USING ERRCODE='23514';END IF;
 IF p->>'status' NOT IN ('Given','Not given') THEN RAISE EXCEPTION 'Choose Given or Not given' USING ERRCODE='23514';END IF;
 note:=hf_api.required_text(p,'remarks',1000);
 IF p->>'status'='Given' THEN actual:=COALESCE(NULLIF(p->>'actualAt','')::timestamptz,now());IF actual>now() OR actual<(SELECT created_at FROM hospitalflow.prescriptions WHERE id=dose_row.prescription_id) THEN RAISE EXCEPTION 'Actual time must be after prescription creation and cannot be in the future' USING ERRCODE='23514';END IF;
 approval:=hf_api.provide_medication(dose_row.prescription_id,dose_row.quantity,note,p_key);END IF;
 UPDATE hospitalflow.medication_doses SET status=p->>'status',actual_at=actual,recorded_by=actor,recorded_at=now(),remarks=note,administration_id=approval WHERE id=dose_row.id;result:=dose_row.id::text;
 ELSIF p_action IN ('prepare-discharge','approve-discharge','finalize-discharge','accrue-charges') THEN
 SELECT * INTO STRICT adm FROM hospitalflow.admissions WHERE id=p->>'admissionId' AND hospital_id=hf_security.current_hospital();pid:=adm.patient_id;
 IF NOT hf_security.can_read_care(pid) AND NOT hf_security.care_role(ARRAY['Billing']) THEN RAISE EXCEPTION 'Care access required' USING ERRCODE='42501';END IF;
 IF p_action='accrue-charges' THEN IF NOT hf_security.care_role(ARRAY['Admin','Billing','Doctor','Nurse']) THEN RAISE EXCEPTION 'Staff access required' USING ERRCODE='42501';END IF;result:=hf_api.accrue_stay_charges(adm.id,true);
 ELSE
 IF adm.status<>'Admitted' THEN RAISE EXCEPTION 'Patient is already discharged' USING ERRCODE='23514';END IF;
 SELECT * INTO review FROM hospitalflow.care_discharge_reviews WHERE admission_id=adm.id FOR UPDATE;
 IF p_action='prepare-discharge' THEN
 IF NOT hf_security.care_role(ARRAY['Nurse']) THEN RAISE EXCEPTION 'Nurse prepares discharge' USING ERRCODE='42501';END IF;
 IF review.approved_at IS NOT NULL THEN RAISE EXCEPTION 'Doctor has approved this summary; it is no longer editable' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.care_discharge_reviews(admission_id,patient_id,nurse_id,final_condition,nurse_remarks) VALUES(adm.id,pid,actor,hf_api.required_text(p,'finalCondition',2000),hf_api.required_text(p,'nurseRemarks',2000)) ON CONFLICT(admission_id) DO UPDATE SET nurse_id=actor,final_condition=EXCLUDED.final_condition,nurse_remarks=EXCLUDED.nurse_remarks,prepared_at=now();
 ELSIF p_action='approve-discharge' THEN
 IF NOT hf_security.care_role(ARRAY['Doctor']) OR review.admission_id IS NULL OR review.approved_at IS NOT NULL THEN RAISE EXCEPTION 'A treating Doctor must review the nursing discharge preparation' USING ERRCODE='42501';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.care_plans WHERE admission_id=adm.id AND doctor_id<>actor) AND NOT hf_security.care_role(ARRAY['Developer']) THEN RAISE EXCEPTION 'Only the treating Doctor can approve discharge' USING ERRCODE='42501';END IF;
 UPDATE hospitalflow.care_discharge_reviews SET doctor_id=actor,approved_at=now(),diagnosis=hf_api.required_text(p,'diagnosis',2000),treatment=hf_api.required_text(p,'treatment',4000),discharge_medications=hf_api.required_text(p,'dischargeMedications',4000),follow_up=hf_api.required_text(p,'followUp',4000),doctor_remarks=hf_api.required_text(p,'doctorRemarks',2000) WHERE admission_id=adm.id;
 ELSE
 IF NOT hf_security.care_role(ARRAY['Nurse']) OR review.approved_at IS NULL THEN RAISE EXCEPTION 'Doctor approval is required before Nurse finalization' USING ERRCODE='42501';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.medication_doses WHERE admission_id=adm.id AND status='Scheduled') THEN RAISE EXCEPTION 'Record Given or Not given outcomes for remaining inpatient scheduled doses' USING ERRCODE='23514';END IF;
 PERFORM hf_api.accrue_stay_charges(adm.id,true);
 PERFORM set_config('hospitalflow.care_finalization',adm.id,true);
 CALL hf_api.discharge_patient(adm.id,review.diagnosis||E'\nTreatment: '||review.treatment||E'\nDischarge medicines: '||review.discharge_medications||E'\nFollow-up: '||review.follow_up||E'\nDoctor: '||review.doctor_remarks||E'\nNurse: '||review.final_condition||' · '||review.nurse_remarks);
 UPDATE hospitalflow.care_discharge_reviews SET completed_by=actor,completed_at=now() WHERE admission_id=adm.id;UPDATE hospitalflow.care_plans SET status='Discharged',updated_at=now() WHERE admission_id=adm.id;
 END IF;result:=adm.id;END IF;
 ELSIF p_action='complete-lab' THEN
 SELECT e.patient_id INTO STRICT pid FROM hospitalflow.clinical_orders o JOIN hospitalflow.encounters e ON e.id=o.encounter_id WHERE o.id=(p->>'id')::uuid AND o.hospital_id=hf_security.current_hospital();
 IF NOT hf_security.care_role(ARRAY['Doctor','Nurse']) OR NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'Clinical care access required' USING ERRCODE='42501';END IF;
 result:=hf_api.execute('complete-clinical-order',p,p_key,p_hash);
 ELSIF p_action='lab-order' THEN
 IF NOT hf_security.care_role(ARRAY['Doctor']) THEN RAISE EXCEPTION 'A Doctor recommends laboratory tests' USING ERRCODE='42501';END IF;
 SELECT patient_id INTO STRICT pid FROM hospitalflow.encounters WHERE id=(p->>'encounterId')::uuid AND hospital_id=hf_security.current_hospital();
 IF NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'Patient care access required' USING ERRCODE='42501';END IF;
 result:=hf_api.execute('clinical-order',p,p_key,p_hash);INSERT INTO hospitalflow.care_managed_orders(order_id,patient_id) VALUES(result::uuid,pid);
 ELSIF p_action='cancel-prescription' THEN
 SELECT patient_id INTO STRICT pid FROM hospitalflow.prescriptions WHERE id=p->>'id' AND hospital_id=hf_security.current_hospital();
 IF NOT hf_security.care_role(ARRAY['Doctor']) OR NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'Treating Doctor access required' USING ERRCODE='42501';END IF;
 note:=hf_api.required_text(p,'comments',1000);result:=hf_api.execute('cancel-prescription',p,p_key,p_hash);
 ELSIF p_action='extra-charge' THEN
 IF NOT hf_security.care_role(ARRAY['Admin','Billing']) THEN RAISE EXCEPTION 'Billing staff enter additional charges' USING ERRCODE='42501';END IF;
 pid:=hf_api.required_text(p,'patientId');kind:=hf_api.required_text(p,'category');IF kind NOT IN ('Consultation','Laboratory','Nursing','Consumables','Other service') THEN RAISE EXCEPTION 'Choose a charge category' USING ERRCODE='23514';END IF;
 CALL hf_api.create_bill(bill,pid,hf_api.required_text(p,'description',500),(p->>'amount')::numeric);
 INSERT INTO hospitalflow.care_extra_categories(line_id,category) SELECT id,kind FROM hospitalflow.bill_lines WHERE bill_id=bill;result:=bill;
 ELSIF p_action='prescription-set' THEN
 IF NOT hf_security.care_role(ARRAY['Doctor']) OR jsonb_typeof(p->'items')<>'array' OR jsonb_array_length(p->'items') NOT BETWEEN 1 AND 30 THEN RAISE EXCEPTION 'A Doctor can enter 1–30 prescription medicines' USING ERRCODE='23514';END IF;
 number:=0;FOR item IN SELECT * FROM jsonb_array_elements(p->'items') LOOP number:=number+1;result:=hf_api.prescribe_visit(hf_api.required_text(p,'appointmentId'),item,md5(p_key::text||number)::uuid,p_hash);END LOOP;
 SELECT patient_id INTO pid FROM hospitalflow.appointments WHERE id=p->>'appointmentId';
 ELSE RAISE EXCEPTION 'Unknown care action' USING ERRCODE='23514';END IF;
 IF pid IS NOT NULL THEN PERFORM hf_api.care_event(pid,replace(initcap(replace(p_action,'-',' ')),'  ',' '),COALESCE(NULLIF(concat_ws(' · ',note,p->>'instructions',p->>'diagnosis',p->>'healthStatus',p->>'progress',p->>'remarks',p->>'nursingNotes',p->>'dose',p->>'finalCondition',p->>'nurseRemarks',p->>'doctorRemarks'),''),'Record saved'),COALESCE(result,''),p-ARRAY['password']);END IF;
 PERFORM hf_security.audit('care:'||p_action,COALESCE(result,''));INSERT INTO hospitalflow.care_command_keys VALUES(actor,p_key,p_action,p_hash,COALESCE(result,''));RETURN COALESCE(result,'');
END $$;
-- Managed admissions cannot use the legacy discharge action to skip clinical approval/finalization.
CREATE FUNCTION hf_security.guard_care_discharge() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ BEGIN IF NEW.status='Discharged' AND OLD.status<>'Discharged' AND (EXISTS(SELECT 1 FROM hospitalflow.care_plans WHERE admission_id=NEW.id) OR EXISTS(SELECT 1 FROM hospitalflow.care_discharge_reviews WHERE admission_id=NEW.id)) AND (current_setting('hospitalflow.care_finalization',true) IS DISTINCT FROM NEW.id OR NOT EXISTS(SELECT 1 FROM hospitalflow.care_discharge_reviews WHERE admission_id=NEW.id AND approved_at IS NOT NULL)) THEN RAISE EXCEPTION 'Use Doctor approval and Nurse discharge finalization' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER care_discharge_guard BEFORE UPDATE ON hospitalflow.admissions FOR EACH ROW EXECUTE FUNCTION hf_security.guard_care_discharge();
CREATE FUNCTION hf_security.guard_dose_outcome() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF OLD.status<>'Scheduled' THEN RAISE EXCEPTION 'Completed dose records are immutable' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER immutable_outcome BEFORE UPDATE OR DELETE ON hospitalflow.medication_doses FOR EACH ROW EXECUTE FUNCTION hf_security.guard_dose_outcome();
REVOKE ALL ON ALL TABLES IN SCHEMA hospitalflow FROM PUBLIC;
REVOKE ALL ON FUNCTION hf_security.care_role(text[]),hf_security.can_read_care(text),hf_api.care_event(text,text,text,text,jsonb),hf_security.capture_care_activity(),hf_api.accrue_stay_charges(text,boolean),hf_api.care_command(text,jsonb,uuid,text),hf_security.guard_care_discharge(),hf_security.guard_dose_outcome() FROM PUBLIC;
-- Background accrual writes only configured, immutable daily rates for managed stays.
CREATE FUNCTION hf_api.accrue_due_care_charges() RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$ DECLARE a record;n integer:=0;BEGIN
 IF nullif(current_setting('hospitalflow.actor_id',true),'') IS NOT NULL OR session_user NOT IN ('hospitalflow_app','hospitalflow_jobs') THEN RAISE EXCEPTION 'Internal accrual worker only' USING ERRCODE='42501';END IF;
 FOR a IN SELECT p.admission_id,p.hospital_id FROM hospitalflow.care_plans p JOIN hospitalflow.admissions s ON s.id=p.admission_id WHERE s.status='Admitted' LOOP
 PERFORM set_config('hospitalflow.hospital_id',a.hospital_id,true);PERFORM hf_api.accrue_stay_charges(a.admission_id);n:=n+1;END LOOP;RETURN n;
END $$;
REVOKE ALL ON FUNCTION hf_api.accrue_due_care_charges() FROM PUBLIC;
CREATE TABLE hospitalflow.care_lab_charges(order_id uuid PRIMARY KEY REFERENCES hospitalflow.clinical_orders(id),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),line_id text NOT NULL UNIQUE REFERENCES hospitalflow.bill_lines(id),price_id uuid NOT NULL REFERENCES hospitalflow.service_prices(id),created_at timestamptz NOT NULL DEFAULT now());
CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.care_lab_charges FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes();
CREATE FUNCTION hf_security.bill_completed_care_lab() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE e hospitalflow.encounters%ROWTYPE;price hospitalflow.service_prices%ROWTYPE;invoice text;line text;service_name text;BEGIN
 IF NEW.status<>'Completed' OR OLD.status='Completed' OR EXISTS(SELECT 1 FROM hospitalflow.care_lab_charges WHERE order_id=NEW.id) THEN RETURN NEW;END IF;
 SELECT * INTO STRICT e FROM hospitalflow.encounters WHERE id=NEW.encounter_id;
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.care_plans WHERE admission_id=e.admission_id) AND NOT EXISTS(SELECT 1 FROM hospitalflow.care_managed_orders WHERE order_id=NEW.id) THEN RETURN NEW;END IF;
 SELECT * INTO price FROM hospitalflow.service_prices WHERE service_id=NEW.service_id AND effective_from<=now() AND(effective_to IS NULL OR effective_to>now()) ORDER BY effective_from DESC LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'Configure a laboratory service price before completing this managed-care test' USING ERRCODE='23514';END IF;
 SELECT name INTO service_name FROM hospitalflow.service_catalog WHERE id=NEW.service_id;
 SELECT bill_id INTO invoice FROM hospitalflow.care_invoices WHERE admission_id=e.admission_id;
 IF invoice IS NULL THEN invoice:=hf_api.new_id('INV');INSERT INTO hospitalflow.bills(id,patient_id) VALUES(invoice,e.patient_id);IF e.admission_id IS NOT NULL THEN INSERT INTO hospitalflow.care_invoices(admission_id,bill_id) VALUES(e.admission_id,invoice);END IF;END IF;
 line:=hf_api.new_id('LINE');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(line,invoice,'Laboratory · '||service_name,price.amount);
 INSERT INTO hospitalflow.invoice_line_context(line_id,service_price_id,quantity,unit_price,currency) VALUES(line,price.id,1,price.amount,price.currency);
 INSERT INTO hospitalflow.care_lab_charges(order_id,patient_id,line_id,price_id) VALUES(NEW.id,e.patient_id,line,price.id);
 INSERT INTO hospitalflow.care_extra_categories(line_id,category) VALUES(line,'Laboratory');
 PERFORM hf_api.care_event(e.patient_id,'Laboratory completed',service_name||' · INR '||price.amount,NEW.id::text,jsonb_build_object('invoice',invoice));RETURN NEW;
END $$;
CREATE TRIGGER care_lab_billing AFTER UPDATE ON hospitalflow.clinical_orders FOR EACH ROW EXECUTE FUNCTION hf_security.bill_completed_care_lab();
CREATE FUNCTION hf_api.invalidate_care_approval(p_patient text,p_reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$ DECLARE changed text;BEGIN
 UPDATE hospitalflow.care_discharge_reviews r SET doctor_id=NULL,approved_at=NULL WHERE patient_id=p_patient AND hospital_id=hf_security.current_hospital() AND approved_at IS NOT NULL AND completed_at IS NULL RETURNING admission_id INTO changed;
 IF changed IS NOT NULL THEN PERFORM hf_api.care_event(p_patient,'Discharge review reopened',p_reason,changed);END IF;END $$;
CREATE FUNCTION hf_security.reopen_care_review() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$ DECLARE pid text;BEGIN
 IF TG_TABLE_NAME='notes' THEN IF NEW.kind='Discharge summary' THEN RETURN NEW;END IF;END IF;
 pid:=NEW.patient_id;PERFORM hf_api.invalidate_care_approval(pid,'Care changed after approval: '||TG_TABLE_NAME||'. Doctor review is required again.');RETURN NEW;
END $$;
CREATE TRIGGER reopen_care_review AFTER INSERT ON hospitalflow.care_observations FOR EACH ROW EXECUTE FUNCTION hf_security.reopen_care_review();
CREATE TRIGGER reopen_care_review AFTER INSERT OR UPDATE OF status ON hospitalflow.prescriptions FOR EACH ROW EXECUTE FUNCTION hf_security.reopen_care_review();
CREATE TRIGGER reopen_care_review AFTER INSERT ON hospitalflow.medication_administrations FOR EACH ROW EXECUTE FUNCTION hf_security.reopen_care_review();
CREATE TRIGGER reopen_care_review AFTER INSERT ON hospitalflow.notes FOR EACH ROW EXECUTE FUNCTION hf_security.reopen_care_review();
REVOKE ALL ON hospitalflow.care_lab_charges,hospitalflow.care_extra_categories FROM PUBLIC;
REVOKE ALL ON FUNCTION hf_security.bill_completed_care_lab(),hf_api.invalidate_care_approval(text,text),hf_security.reopen_care_review() FROM PUBLIC;
CREATE TRIGGER reopen_care_review AFTER INSERT OR UPDATE OF status ON hospitalflow.medication_doses FOR EACH ROW EXECUTE FUNCTION hf_security.reopen_care_review();
CREATE TRIGGER reopen_care_review AFTER INSERT OR UPDATE OF planned_days,instructions ON hospitalflow.care_plans FOR EACH ROW EXECUTE FUNCTION hf_security.reopen_care_review();
-- Narrow projections let patients read their own historical bed/lab metadata without granting
-- access to the shared bed board, clinical encounters or other patients' billing context.
CREATE FUNCTION hf_api.care_stays() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
 SELECT COALESCE(jsonb_agg((CASE WHEN hf_security.care_role(ARRAY['Admin','Doctor','Nurse']) OR hf_security.own_patient(a.patient_id) THEN to_jsonb(a) ELSE to_jsonb(a)-'reason' END)||jsonb_build_object('ward',b.ward,'category',b.category,'patient_name',p.name,'patient_code',p.registration_id)),'[]') FROM hospitalflow.admissions a JOIN hospitalflow.beds b ON b.id=a.bed_id JOIN hospitalflow.patients p ON p.id=a.patient_id WHERE a.hospital_id=hf_security.current_hospital() AND (hf_security.can_read_care(a.patient_id) OR hf_security.care_role(ARRAY['Billing','Pharmacist'])) $$;
CREATE FUNCTION hf_api.care_lab_orders() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
 SELECT COALESCE(jsonb_agg(to_jsonb(o)||jsonb_build_object('patient_id',e.patient_id,'service_name',s.name,'ordered_name',u.name)),'[]') FROM hospitalflow.clinical_orders o JOIN hospitalflow.encounters e ON e.id=o.encounter_id JOIN hospitalflow.service_catalog s ON s.id=o.service_id JOIN hospitalflow.users u ON u.id=o.ordered_by WHERE o.hospital_id=hf_security.current_hospital() AND hf_security.can_read_care(e.patient_id) $$;
CREATE FUNCTION hf_api.care_line_category(p_line text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
 SELECT CASE WHEN x.medicine_id IS NOT NULL THEN 'Pharmacy' WHEN x.service_price_id IS NOT NULL THEN COALESCE(s.category,'Other') ELSE 'Other' END FROM hospitalflow.bill_lines l JOIN hospitalflow.bills b ON b.id=l.bill_id LEFT JOIN hospitalflow.invoice_line_context x ON x.line_id=l.id LEFT JOIN hospitalflow.service_prices sp ON sp.id=x.service_price_id LEFT JOIN hospitalflow.service_catalog s ON s.id=sp.service_id WHERE l.id=p_line AND b.hospital_id=hf_security.current_hospital() AND(hf_security.can_read_care(b.patient_id) OR hf_security.care_role(ARRAY['Billing','Pharmacist'])) $$;
REVOKE ALL ON FUNCTION hf_api.care_stays(),hf_api.care_lab_orders(),hf_api.care_line_category(text) FROM PUBLIC;
-- An accepted/admitted care assignment remains valid throughout an extended stay.
CREATE OR REPLACE FUNCTION hf_security.can_access_patient(p_patient text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_security,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM hospitalflow.users u WHERE u.id=nullif(current_setting('hospitalflow.actor_id',true),'') AND u.active AND
 (EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships m WHERE m.user_id=u.id AND m.hospital_id=hf_security.current_hospital() AND m.active) OR u.role='Developer' OR EXISTS(SELECT 1 FROM hospitalflow.network_operators o WHERE o.user_id=u.id)) AND
 (u.role IN ('Admin','Developer') OR EXISTS(SELECT 1 FROM hospitalflow.patient_access_grants g WHERE g.user_id=u.id AND g.hospital_id=hf_security.current_hospital() AND g.patient_id=p_patient AND g.expires_at>now()) OR
 EXISTS(SELECT 1 FROM hospitalflow.care_plans p WHERE p.hospital_id=hf_security.current_hospital() AND p.patient_id=p_patient AND p.status IN ('Accepted','Admitted') AND (p.doctor_id=u.id OR p.nurse_id=u.id)) OR
 EXISTS(SELECT 1 FROM hospitalflow.admissions a JOIN hospitalflow.beds b ON b.id=a.bed_id JOIN hospitalflow.wards w ON w.name=b.ward JOIN hospitalflow.user_departments d ON d.department=w.department AND d.hospital_id=hf_security.current_hospital() WHERE a.patient_id=p_patient AND a.hospital_id=hf_security.current_hospital() AND a.status='Admitted' AND d.user_id=u.id))) $$;
REVOKE ALL ON FUNCTION hf_security.can_access_patient(text) FROM PUBLIC;
-- Enforce clinical read boundaries for the runtime account as well as the HTTP projections.
DO $$ DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['care_plans','care_observations','medication_doses','care_discharge_reviews','care_events','care_managed_orders'] LOOP
 EXECUTE format('ALTER TABLE hospitalflow.%I ENABLE ROW LEVEL SECURITY',t);
 IF t='care_managed_orders' THEN EXECUTE format('CREATE POLICY hospital_scope ON hospitalflow.%I USING(hospital_id=hf_security.current_hospital())',t);END IF;
 EXECUTE format('CREATE POLICY clinical_reader ON hospitalflow.%I AS RESTRICTIVE FOR SELECT USING(hf_security.can_read_care(patient_id))',t);END LOOP;
 FOREACH t IN ARRAY ARRAY['care_charge_entries','pharmacy_requests','care_lab_charges'] LOOP
 EXECUTE format('ALTER TABLE hospitalflow.%I ENABLE ROW LEVEL SECURITY',t);
 IF t='care_lab_charges' THEN EXECUTE format('CREATE POLICY hospital_scope ON hospitalflow.%I USING(hospital_id=hf_security.current_hospital())',t);END IF;
 EXECUTE format('CREATE POLICY care_financial_reader ON hospitalflow.%I AS RESTRICTIVE FOR SELECT USING(hospital_id=hf_security.current_hospital() AND(hf_security.can_read_care(patient_id) OR hf_security.care_role(ARRAY[''Billing'',''Pharmacist''])))',t);END LOOP;
END $$;
CREATE INDEX care_plan_queue ON hospitalflow.care_plans(hospital_id,status,nurse_id);
CREATE INDEX care_observation_history ON hospitalflow.care_observations(hospital_id,patient_id,at);
CREATE INDEX care_dose_history ON hospitalflow.medication_doses(hospital_id,patient_id,scheduled_at);
CREATE INDEX care_pharmacy_queue ON hospitalflow.pharmacy_requests(hospital_id,prescription_id,at);
CREATE INDEX care_discharge_patient ON hospitalflow.care_discharge_reviews(hospital_id,patient_id);

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.025_complete_care_flow.sql','AAC10A4EC62C0C00AFF2458A61F6CC9EC89EB0F325E4C6AF82A2DEE242063BFA');

-- 026_billing_calendar_releases.sql
-- Hospital-scoped tariff versions, transparent invoice settlement, annual calendars and releases.
ALTER TABLE hospitalflow.care_rates DROP CONSTRAINT care_rates_hospital_id_ward_effective_from_key;
CREATE INDEX care_rates_lookup ON hospitalflow.care_rates(hospital_id,ward,effective_from DESC,created_at DESC,id DESC);
CREATE TABLE hospitalflow.invoice_discounts(line_id text PRIMARY KEY REFERENCES hospitalflow.bill_lines(id),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),bill_id text NOT NULL REFERENCES hospitalflow.bills(id),amount numeric(14,2) NOT NULL CHECK(amount>0),reason text NOT NULL CHECK(length(reason) BETWEEN 1 AND 500),created_by text NOT NULL REFERENCES hospitalflow.users(id),created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.portal_payments(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),bill_id text NOT NULL REFERENCES hospitalflow.bills(id),payment_id text NOT NULL UNIQUE REFERENCES hospitalflow.payments(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),amount numeric(14,2) NOT NULL CHECK(amount>0),method text NOT NULL CHECK(method IN ('UPI','Netbanking','Card','QR')),mode text NOT NULL CHECK(mode='Test'),paid_by text NOT NULL REFERENCES hospitalflow.users(id),created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.medicine_price_history(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),medicine_id text NOT NULL REFERENCES hospitalflow.medicine_batches(id),old_price numeric(14,2) NOT NULL,new_price numeric(14,2) NOT NULL CHECK(new_price>0),reason text NOT NULL,created_by text NOT NULL REFERENCES hospitalflow.users(id),created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.hospital_holidays(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),name text NOT NULL CHECK(length(name) BETWEEN 1 AND 150),on_date date,annual_month integer,annual_day integer,kind text NOT NULL CHECK(kind IN ('National','Festival','Regional','Hospital')),is_leave boolean NOT NULL DEFAULT false,active boolean NOT NULL DEFAULT true,notes text NOT NULL DEFAULT '',source text NOT NULL DEFAULT '',updated_by text REFERENCES hospitalflow.users(id),updated_at timestamptz NOT NULL DEFAULT now(),CHECK((on_date IS NOT NULL AND annual_month IS NULL AND annual_day IS NULL) OR(on_date IS NULL AND annual_month BETWEEN 1 AND 12 AND annual_day BETWEEN 1 AND extract(day FROM (make_date(2000,annual_month,1)+interval '1 month - 1 day')))));
CREATE TABLE hospitalflow.application_releases(version text PRIMARY KEY CHECK(version~'^[0-9]+\.[0-9]\.[0-9]$'),released_at timestamptz NOT NULL,source_parent text NOT NULL,notes text NOT NULL,installed_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE hospitalflow.application_releases ENABLE ROW LEVEL SECURITY;
CREATE POLICY release_admin_read ON hospitalflow.application_releases FOR SELECT USING(hf_security.care_role(ARRAY['Admin']));
CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.application_releases FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes();
-- National fixed-date entries repeat each year; no regional closure is assumed.
INSERT INTO hospitalflow.hospital_holidays(hospital_id,name,annual_month,annual_day,kind,is_leave,source)
SELECT h.id,v.name,v.month,v.day,'National',true,'India national fixed-date observance' FROM hospitalflow.hospitals h CROSS JOIN(VALUES('Republic Day',1,26),('Independence Day',8,15),('Gandhi Jayanti',10,2))v(name,month,day);
INSERT INTO hospitalflow.hospital_holidays(hospital_id,name,on_date,kind,is_leave,source)
SELECT h.id,v.name,v.day::date,'Festival',false,'https://dfe.gov.in/uploads/documents/list-of-gazetted-holidays-2026.pdf — central government reference; hospital policy requires Admin confirmation' FROM hospitalflow.hospitals h CROSS JOIN(VALUES
('Holi','2026-03-04'),('Id-ul-Fitr','2026-03-21'),('Ram Navami','2026-03-26'),('Mahavir Jayanti','2026-03-31'),('Good Friday','2026-04-03'),('Buddha Purnima','2026-05-01'),('Id-ul-Zuha (Bakrid)','2026-05-27'),('Muharram','2026-06-26'),('Milad-un-Nabi','2026-08-26'),('Janmashtami','2026-09-04'),('Dussehra','2026-10-20'),('Diwali','2026-11-08'),('Guru Nanak Jayanti','2026-11-24'),('Christmas','2026-12-25'))v(name,day);
DO $$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['invoice_discounts','portal_payments','medicine_price_history','hospital_holidays'] LOOP
 EXECUTE format('ALTER TABLE hospitalflow.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('CREATE POLICY hospital_read ON hospitalflow.%I FOR SELECT USING(hospital_id=hf_security.current_hospital() AND hf_security.care_role(ARRAY[''Admin'']))',t);
 EXECUTE format('CREATE TRIGGER z_hospital_guard BEFORE INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hf_security.guard_hospital_row()',t);
 EXECUTE format('CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history()',t);
 IF t<>'hospital_holidays' THEN EXECUTE format('CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes()',t);END IF;
END LOOP;END $$;
CREATE FUNCTION hf_api.finance_state() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();BEGIN
 IF NOT(hf_security.care_role(ARRAY['Admin','Doctor','Nurse','Billing','Pharmacist']) OR EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor)) THEN RAISE EXCEPTION 'Patient billing access required' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object(
 'invoices',(SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.id),'[]') FROM(SELECT b.id,b.patient_id,p.name patient_name,p.registration_id patient_code,v.total,v.paid,v.balance,
 COALESCE((SELECT sum(amount) FROM hospitalflow.bill_lines WHERE bill_id=b.id AND amount>0),0) gross,
 COALESCE((SELECT -sum(amount) FROM hospitalflow.bill_lines WHERE bill_id=b.id AND amount<0),0) credits,
 COALESCE((SELECT sum(amount) FROM hospitalflow.invoice_discounts WHERE bill_id=b.id),0) discount,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('amount',amount,'reason',reason,'by',u.name,'at',d.created_at)) FROM hospitalflow.invoice_discounts d JOIN hospitalflow.users u ON u.id=d.created_by WHERE d.bill_id=b.id),'[]') discounts,
 COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM(SELECT pay.id,pay.amount,pay.method,pay.at,pp.mode,pp.method portal_method FROM hospitalflow.payments pay LEFT JOIN hospitalflow.portal_payments pp ON pp.payment_id=pay.id WHERE pay.bill_id=b.id ORDER BY pay.at)r),'[]') receipts
 FROM hospitalflow.bills b JOIN hospitalflow.patients p ON p.id=b.patient_id JOIN hospitalflow.invoice_balances v ON v.id=b.id WHERE b.hospital_id=hf_security.current_hospital() AND(hf_security.care_role(ARRAY['Admin','Billing','Pharmacist']) OR hf_security.can_read_care(b.patient_id)))q),
 'medicines',(SELECT COALESCE(jsonb_agg(to_jsonb(q)),'[]') FROM(SELECT b.patient_id,b.id invoice,m.name medicine,x.quantity,x.unit_price,l.amount,l.created_at,pres.id prescription_id,pres.status FROM hospitalflow.bill_lines l JOIN hospitalflow.bills b ON b.id=l.bill_id JOIN hospitalflow.invoice_line_context x ON x.line_id=l.id JOIN hospitalflow.medicine_batches m ON m.id=x.medicine_id LEFT JOIN hospitalflow.prescription_dispensations d ON d.bill_id=b.id LEFT JOIN hospitalflow.prescriptions pres ON pres.id=d.prescription_id WHERE b.hospital_id=hf_security.current_hospital() AND(hf_security.care_role(ARRAY['Admin','Billing','Pharmacist']) OR hf_security.can_read_care(b.patient_id)))q),
 'prices',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'batch',m.batch,'price',m.price)),'[]') FROM hospitalflow.medicine_batches m WHERE m.hospital_id=hf_security.current_hospital()),
 'priceHistory',(SELECT COALESCE(jsonb_agg(to_jsonb(q)),'[]') FROM(SELECT ph.*,u.name changed_by FROM hospitalflow.medicine_price_history ph JOIN hospitalflow.users u ON u.id=ph.created_by WHERE ph.hospital_id=hf_security.current_hospital() AND hf_security.care_role(ARRAY['Admin','Doctor','Nurse','Pharmacist']))q));
END $$;
CREATE FUNCTION hf_api.year_calendar(p_year integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();BEGIN
 IF p_year NOT BETWEEN 1900 AND 9998 THEN RAISE EXCEPTION 'Choose a year from 1900 to 9998' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor) THEN RAISE EXCEPTION 'Staff calendar only' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('year',p_year,'hospitalName',(SELECT name FROM hospitalflow.hospitals WHERE id=hf_security.current_hospital()),'holidays',
 (SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.day,q.name),'[]') FROM(SELECT h.*,CASE WHEN h.on_date IS NOT NULL THEN h.on_date ELSE make_date(p_year,h.annual_month,h.annual_day) END AS day FROM hospitalflow.hospital_holidays h WHERE h.hospital_id=hf_security.current_hospital() AND h.active AND(extract(year FROM h.on_date)=p_year OR(h.on_date IS NULL AND(h.annual_month<>2 OR h.annual_day<>29 OR extract(day FROM(make_date(p_year,2,1)+interval '1 month - 1 day'))=29))))q),
 'leaves',(SELECT COALESCE(jsonb_agg(jsonb_build_object('name',u.name,'code',u.registration_id,'startsOn',l.starts_on,'endsOn',l.ends_on,'role',u.role)),'[]') FROM hospitalflow.staff_leaves l JOIN hospitalflow.users u ON u.id=l.user_id JOIN hospitalflow.hospital_memberships m ON m.user_id=u.id AND m.hospital_id=l.hospital_id AND m.active WHERE l.hospital_id=hf_security.current_hospital() AND l.status='Approved' AND l.starts_on<make_date(p_year+1,1,1) AND l.ends_on>=make_date(p_year,1,1) AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id)));
END $$;
CREATE FUNCTION hf_api.record_release(p jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ BEGIN
 IF nullif(hf_security.actor_id(),'') IS NOT NULL OR session_user<>'hospitalflow_app' THEN RAISE EXCEPTION 'Internal release registration only' USING ERRCODE='42501';END IF;
 INSERT INTO hospitalflow.application_releases(version,released_at,source_parent,notes) VALUES(p->>'version',(p->>'releasedAt')::timestamptz,COALESCE(p->>'sourceParent',''),COALESCE(p->>'notes','')) ON CONFLICT(version) DO NOTHING;
END $$;
CREATE FUNCTION hf_api.enterprise_command(p_action text,p jsonb,p_key uuid,p_hash text,p_test boolean) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();result text;prior hospitalflow.care_command_keys%ROWTYPE;b hospitalflow.bills%ROWTYPE;bal numeric;amount numeric;line text;method text;med hospitalflow.medicine_batches%ROWTYPE;holiday uuid;BEGIN
 IF p_key IS NULL OR p_hash!~'^[A-Fa-f0-9]{64}$' OR jsonb_typeof(p)<>'object' THEN RAISE EXCEPTION 'Valid retry key and details required' USING ERRCODE='23514';END IF;
 PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO prior FROM hospitalflow.care_command_keys WHERE actor_id=actor AND key=p_key;
 IF FOUND THEN IF prior.action<>'enterprise:'||p_action OR prior.request_hash<>p_hash THEN RAISE EXCEPTION 'Retry key belongs to different details' USING ERRCODE='23514';END IF;RETURN prior.reference;END IF;
 IF p_action IN ('discount','portal-pay') THEN
 SELECT * INTO b FROM hospitalflow.bills WHERE id=hf_api.required_text(p,'invoiceId') AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Invoice unavailable' USING ERRCODE='23514';END IF;
 IF p_action='discount' THEN
 IF NOT hf_security.care_role(ARRAY['Admin','Billing']) THEN RAISE EXCEPTION 'Hospital Admin or Billing approval required' USING ERRCODE='42501';END IF;
 ELSE
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor AND patient_id=b.patient_id) THEN RAISE EXCEPTION 'Only the invoice patient can use portal payment' USING ERRCODE='42501';END IF;
 IF COALESCE((p->>'confirmed')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'Confirm the TEST payment before continuing' USING ERRCODE='23514';END IF;
 IF NOT p_test THEN RAISE EXCEPTION 'Online payment provider is not configured; payment was not taken' USING ERRCODE='23514';END IF;
 END IF;
 amount:=hf_api.positive_number(p,'amount');IF amount<>round(amount,2) THEN RAISE EXCEPTION 'Use at most two decimal places' USING ERRCODE='23514';END IF;SELECT balance INTO bal FROM hospitalflow.invoice_balances WHERE id=b.id;
 IF amount>bal THEN RAISE EXCEPTION 'Amount exceeds the current outstanding balance' USING ERRCODE='23514';END IF;
 IF p_action='discount' THEN
 line:=hf_api.new_id('DISC');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(line,b.id,'Discount: '||hf_api.required_text(p,'reason'),-amount);
 INSERT INTO hospitalflow.invoice_discounts(line_id,bill_id,amount,reason,created_by) VALUES(line,b.id,amount,hf_api.required_text(p,'reason'),actor);
 INSERT INTO hospitalflow.care_extra_categories(line_id,category) VALUES(line,'Discount');result:=line;
 PERFORM hf_api.care_event(b.patient_id,'Discount applied','INR '||amount||' · '||hf_api.required_text(p,'reason'),line);
 ELSE
 method:=hf_api.required_text(p,'method');IF method NOT IN ('UPI','Netbanking','Card','QR') THEN RAISE EXCEPTION 'Choose a supported payment option' USING ERRCODE='23514';END IF;
 line:=hf_api.new_id('PAY');INSERT INTO hospitalflow.payments(id,bill_id,amount,method,at) VALUES(line,b.id,amount,CASE method WHEN 'Netbanking' THEN 'Bank transfer' WHEN 'QR' THEN 'UPI' ELSE method END,now());
 INSERT INTO hospitalflow.portal_payments(bill_id,payment_id,patient_id,amount,method,mode,paid_by) VALUES(b.id,line,b.patient_id,amount,method,'Test',actor) RETURNING id::text INTO result;
 PERFORM hf_api.care_event(b.patient_id,'Portal payment','TEST payment · '||method||' · INR '||amount,line);
 END IF;
 ELSIF p_action='medicine-price' THEN
 IF NOT hf_security.care_role(ARRAY['Admin']) THEN RAISE EXCEPTION 'Admin manages medicine prices' USING ERRCODE='42501';END IF;
 SELECT * INTO STRICT med FROM hospitalflow.medicine_batches WHERE id=hf_api.required_text(p,'medicineId') AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 amount:=hf_api.positive_number(p,'price');IF amount<>round(amount,2) THEN RAISE EXCEPTION 'Use at most two decimal places' USING ERRCODE='23514';END IF;UPDATE hospitalflow.medicine_batches SET price=amount WHERE id=med.id;
 INSERT INTO hospitalflow.medicine_price_history(medicine_id,old_price,new_price,reason,created_by) VALUES(med.id,med.price,amount,hf_api.required_text(p,'reason'),actor) RETURNING id::text INTO result;
 ELSIF p_action='holiday' THEN
 IF NOT hf_security.care_role(ARRAY['Admin']) THEN RAISE EXCEPTION 'Admin manages hospital holidays' USING ERRCODE='42501';END IF;
 holiday:=nullif(p->>'id','')::uuid;
 IF holiday IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hospitalflow.hospital_holidays WHERE id=holiday AND hospital_id=hf_security.current_hospital()) THEN RAISE EXCEPTION 'Holiday unavailable in this hospital' USING ERRCODE='42501';END IF;
 IF holiday IS NULL THEN holiday:=gen_random_uuid();INSERT INTO hospitalflow.hospital_holidays(id,name,on_date,kind) VALUES(holiday,hf_api.required_text(p,'name'),(p->>'day')::date,hf_api.required_text(p,'kind'));END IF;
 UPDATE hospitalflow.hospital_holidays SET name=hf_api.required_text(p,'name'),on_date=CASE WHEN COALESCE((p->>'annual')::boolean,false) THEN NULL ELSE(p->>'day')::date END,annual_month=CASE WHEN COALESCE((p->>'annual')::boolean,false) THEN extract(month FROM(p->>'day')::date) END,annual_day=CASE WHEN COALESCE((p->>'annual')::boolean,false) THEN extract(day FROM(p->>'day')::date) END,kind=hf_api.required_text(p,'kind'),is_leave=(p->>'isLeave')::boolean,active=COALESCE((p->>'active')::boolean,true),notes=left(COALESCE(p->>'notes',''),2000),source='Hospital Admin',updated_by=actor,updated_at=now() WHERE id=holiday;result:=holiday::text;
 ELSE RAISE EXCEPTION 'Unsupported enterprise action' USING ERRCODE='23514';END IF;
 PERFORM hf_security.audit('enterprise:'||p_action,result);
 INSERT INTO hospitalflow.care_command_keys(actor_id,key,action,request_hash,reference) VALUES(actor,p_key,'enterprise:'||p_action,p_hash,result);RETURN result;
END $$;
REVOKE ALL ON FUNCTION hf_api.finance_state(),hf_api.year_calendar(integer),hf_api.record_release(jsonb),hf_api.enterprise_command(text,jsonb,uuid,text,boolean) FROM PUBLIC;
CREATE OR REPLACE FUNCTION hf_api.accrue_stay_charges(p_admission text,p_strict boolean DEFAULT false) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE a hospitalflow.admissions%ROWTYPE;r hospitalflow.care_rates%ROWTYPE;assignment record;day date;last_day date;invoice text;line text;kind text;amount numeric;original_actor text:=hf_security.actor_id();BEGIN
 IF nullif(hf_security.actor_id(),'') IS NOT NULL AND NOT hf_security.care_role(ARRAY['Admin','Billing','Doctor','Nurse']) THEN RAISE EXCEPTION 'Care billing staff required' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(74192301);SELECT * INTO STRICT a FROM hospitalflow.admissions WHERE id=p_admission AND hospital_id=hf_security.current_hospital();
 IF nullif(original_actor,'') IS NOT NULL AND NOT hf_security.can_read_care(a.patient_id) AND NOT hf_security.care_role(ARRAY['Admin','Billing']) THEN RAISE EXCEPTION 'Patient care access required for charge calculation' USING ERRCODE='42501';END IF;
 PERFORM set_config('hospitalflow.actor_id','',true);
 SELECT bill_id INTO invoice FROM hospitalflow.care_invoices WHERE admission_id=a.id;
 last_day:=(COALESCE(a.discharged,now()) AT TIME ZONE 'Asia/Kolkata')::date;
 FOR day IN SELECT generate_series((a.at AT TIME ZONE 'Asia/Kolkata')::date,last_day,'1 day')::date LOOP
 SELECT ba.bed_id,b.ward,b.category INTO assignment FROM hospitalflow.bed_assignments ba JOIN hospitalflow.beds b ON b.id=ba.bed_id WHERE ba.admission_id=a.id AND ba.from_time<((day+1)::timestamp AT TIME ZONE 'Asia/Kolkata') AND COALESCE(ba.to_time,now())>=day::timestamp AT TIME ZONE 'Asia/Kolkata' ORDER BY ba.from_time ASC LIMIT 1;
 SELECT * INTO r FROM hospitalflow.care_rates WHERE hospital_id=a.hospital_id AND ward=assignment.ward AND effective_from<=day ORDER BY effective_from DESC,created_at DESC,id DESC LIMIT 1;
 IF NOT FOUND THEN IF p_strict THEN RAISE EXCEPTION 'Configure dated bed/ward/ICU/nursing rates before final billing for %',assignment.ward USING ERRCODE='23514';END IF;CONTINUE;END IF;
 IF invoice IS NULL THEN invoice:=hf_api.new_id('INV');INSERT INTO hospitalflow.bills(id,patient_id) VALUES(invoice,a.patient_id);INSERT INTO hospitalflow.care_invoices(admission_id,bill_id) VALUES(a.id,invoice);END IF;
 FOREACH kind IN ARRAY ARRAY['Bed','Ward','ICU','Nursing'] LOOP
 IF EXISTS(SELECT 1 FROM hospitalflow.care_charge_entries WHERE admission_id=a.id AND charge_day=day AND category=kind) THEN CONTINUE;END IF;
 amount:=CASE kind WHEN 'Bed' THEN r.bed_daily WHEN 'Ward' THEN r.ward_daily WHEN 'ICU' THEN CASE WHEN assignment.category ILIKE '%ICU%' OR assignment.ward ILIKE '%ICU%' THEN r.icu_daily ELSE 0 END ELSE r.nursing_daily END;
 line:=NULL;IF amount>0 THEN line:=hf_api.new_id('LINE');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(line,invoice,kind||' · '||assignment.ward||' · '||day,amount);END IF;
 INSERT INTO hospitalflow.care_charge_entries(admission_id,patient_id,charge_day,category,amount,rate_id,bed_id,line_id) VALUES(a.id,a.patient_id,day,kind,amount,r.id,assignment.bed_id,line);
 PERFORM hf_api.care_event(a.patient_id,'Daily charge',kind||' · '||day||' · INR '||amount,COALESCE(line,a.id||':'||day||':'||kind),jsonb_build_object('category',kind,'amount',amount,'day',day,'invoice',invoice));
 END LOOP;END LOOP;PERFORM set_config('hospitalflow.actor_id',COALESCE(original_actor,''),true);RETURN invoice;
END $$;

CREATE OR REPLACE FUNCTION hf_api.accrue_due_care_charges() RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$ DECLARE a record;n integer:=0;original_hospital text:=hf_security.current_hospital();BEGIN
 IF nullif(current_setting('hospitalflow.actor_id',true),'') IS NOT NULL OR session_user NOT IN ('hospitalflow_app','hospitalflow_jobs') THEN RAISE EXCEPTION 'Internal accrual worker only' USING ERRCODE='42501';END IF;
 FOR a IN SELECT id,hospital_id FROM hospitalflow.admissions WHERE status='Admitted' LOOP
 PERFORM set_config('hospitalflow.hospital_id',a.hospital_id,true);PERFORM hf_api.accrue_stay_charges(a.id);n:=n+1;END LOOP;
 PERFORM set_config('hospitalflow.hospital_id',original_hospital,true);RETURN n;
END $$;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.026_billing_calendar_releases.sql','CB4FBBD2F9144D475A62B2A6EEF5D5FB923279D449489B05FD81F9545997F9F5');

-- 027_patient_charge_summary.sql
-- Refresh only the requesting identity's authorized active stays; no duplicate daily entries.
CREATE FUNCTION hf_api.refresh_finance_charges() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();a record;BEGIN
 IF NOT(hf_security.care_role(ARRAY['Admin','Billing','Doctor','Nurse','Pharmacist']) OR EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor)) THEN RAISE EXCEPTION 'Patient billing access required' USING ERRCODE='42501';END IF;
 FOR a IN SELECT s.id FROM hospitalflow.admissions s WHERE s.hospital_id=hf_security.current_hospital() AND s.status='Admitted' AND(hf_security.care_role(ARRAY['Admin','Billing','Pharmacist']) OR hf_security.can_read_care(s.patient_id)) LOOP
 PERFORM set_config('hospitalflow.actor_id','',true);PERFORM hf_api.accrue_stay_charges(a.id);PERFORM set_config('hospitalflow.actor_id',actor,true);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION hf_api.refresh_finance_charges() FROM PUBLIC;
CREATE OR REPLACE FUNCTION hf_api.enterprise_command(p_action text,p jsonb,p_key uuid,p_hash text,p_test boolean) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();result text;prior hospitalflow.care_command_keys%ROWTYPE;b hospitalflow.bills%ROWTYPE;bal numeric;amount numeric;line text;method text;med hospitalflow.medicine_batches%ROWTYPE;holiday uuid;pid text;entry record;total_due numeric;child_key uuid;BEGIN
 IF p_key IS NULL OR p_hash!~'^[A-Fa-f0-9]{64}$' OR jsonb_typeof(p)<>'object' THEN RAISE EXCEPTION 'Valid retry key and details required' USING ERRCODE='23514';END IF;
 PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO prior FROM hospitalflow.care_command_keys WHERE actor_id=actor AND key=p_key;
 IF FOUND THEN IF prior.action<>'enterprise:'||p_action OR prior.request_hash<>p_hash THEN RAISE EXCEPTION 'Retry key belongs to different details' USING ERRCODE='23514';END IF;RETURN prior.reference;END IF;
 IF p_action IN ('discount','portal-pay') THEN
 SELECT * INTO b FROM hospitalflow.bills WHERE id=hf_api.required_text(p,'invoiceId') AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Invoice unavailable' USING ERRCODE='23514';END IF;
 IF p_action='discount' THEN
 IF NOT (hf_security.care_role(ARRAY['Admin','Billing']) OR (hf_security.care_role(ARRAY['Doctor']) AND hf_security.can_read_care(b.patient_id)) OR (hf_security.care_role(ARRAY['Pharmacist']) AND EXISTS(SELECT 1 FROM hospitalflow.bill_lines l JOIN hospitalflow.invoice_line_context x ON x.line_id=l.id WHERE l.bill_id=b.id AND x.medicine_id IS NOT NULL) AND NOT EXISTS(SELECT 1 FROM hospitalflow.bill_lines l WHERE l.bill_id=b.id AND l.amount>0 AND NOT EXISTS(SELECT 1 FROM hospitalflow.invoice_line_context x WHERE x.line_id=l.id AND x.medicine_id IS NOT NULL)))) THEN RAISE EXCEPTION 'Discount requires hospital Admin/Billing, an authorized Doctor, or Pharmacy for medicine-only invoices' USING ERRCODE='42501';END IF;
 ELSE
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor AND patient_id=b.patient_id) THEN RAISE EXCEPTION 'Only the invoice patient can use portal payment' USING ERRCODE='42501';END IF;
 IF COALESCE((p->>'confirmed')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'Confirm the TEST payment before continuing' USING ERRCODE='23514';END IF;
 IF NOT p_test THEN RAISE EXCEPTION 'Online payment provider is not configured; payment was not taken' USING ERRCODE='23514';END IF;
 END IF;
 amount:=hf_api.positive_number(p,'amount');IF amount<>round(amount,2) THEN RAISE EXCEPTION 'Use at most two decimal places' USING ERRCODE='23514';END IF;SELECT balance INTO bal FROM hospitalflow.invoice_balances WHERE id=b.id;
 IF amount>bal THEN RAISE EXCEPTION 'Amount exceeds the current outstanding balance' USING ERRCODE='23514';END IF;
 IF p_action='discount' THEN
 line:=hf_api.new_id('DISC');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(line,b.id,'Discount: '||hf_api.required_text(p,'reason'),-amount);
 INSERT INTO hospitalflow.invoice_discounts(line_id,bill_id,amount,reason,created_by) VALUES(line,b.id,amount,hf_api.required_text(p,'reason'),actor);
 INSERT INTO hospitalflow.care_extra_categories(line_id,category) VALUES(line,'Discount');result:=line;
 PERFORM hf_api.care_event(b.patient_id,'Discount applied','INR '||amount||' · '||hf_api.required_text(p,'reason'),line);
 ELSE
 method:=hf_api.required_text(p,'method');IF method NOT IN ('UPI','Netbanking','Card','QR') THEN RAISE EXCEPTION 'Choose a supported payment option' USING ERRCODE='23514';END IF;
 line:=hf_api.new_id('PAY');INSERT INTO hospitalflow.payments(id,bill_id,amount,method,at) VALUES(line,b.id,amount,CASE method WHEN 'Netbanking' THEN 'Bank transfer' WHEN 'QR' THEN 'UPI' ELSE method END,now());
 INSERT INTO hospitalflow.portal_payments(bill_id,payment_id,patient_id,amount,method,mode,paid_by) VALUES(b.id,line,b.patient_id,amount,method,'Test',actor) RETURNING id::text INTO result;
 PERFORM hf_api.care_event(b.patient_id,'Portal payment','TEST payment · '||method||' · INR '||amount,line);
 END IF;
 ELSIF p_action='portal-pay-total' THEN
 SELECT patient_id INTO pid FROM hospitalflow.patient_accounts WHERE user_id=actor;
 IF pid IS NULL THEN RAISE EXCEPTION 'Patient account required for total payment' USING ERRCODE='42501';END IF;
 PERFORM hf_api.refresh_finance_charges();
 SELECT COALESCE(sum(v.balance),0) INTO total_due FROM hospitalflow.invoice_balances v JOIN hospitalflow.bills bill ON bill.id=v.id WHERE bill.patient_id=pid AND bill.hospital_id=hf_security.current_hospital() AND v.balance>0;
 IF total_due<=0 OR total_due<>hf_api.positive_number(p,'amount') THEN RAISE EXCEPTION 'The total has changed. Refresh and review the current amount before paying.' USING ERRCODE='23514';END IF;
 FOR entry IN SELECT v.id,v.balance FROM hospitalflow.invoice_balances v JOIN hospitalflow.bills bill ON bill.id=v.id WHERE bill.patient_id=pid AND bill.hospital_id=hf_security.current_hospital() AND v.balance>0 ORDER BY v.id LOOP
 child_key:=md5(p_key::text||':'||entry.id)::uuid;
 PERFORM hf_api.enterprise_command('portal-pay',jsonb_build_object('invoiceId',entry.id,'amount',entry.balance,'method',p->>'method','confirmed',p->'confirmed'),child_key,p_hash,p_test);
 END LOOP;result:=p_key::text;
 ELSIF p_action='medicine-price' THEN
 IF NOT hf_security.care_role(ARRAY['Admin']) THEN RAISE EXCEPTION 'Admin manages medicine prices' USING ERRCODE='42501';END IF;
 SELECT * INTO STRICT med FROM hospitalflow.medicine_batches WHERE id=hf_api.required_text(p,'medicineId') AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 amount:=hf_api.positive_number(p,'price');IF amount<>round(amount,2) THEN RAISE EXCEPTION 'Use at most two decimal places' USING ERRCODE='23514';END IF;UPDATE hospitalflow.medicine_batches SET price=amount WHERE id=med.id;
 INSERT INTO hospitalflow.medicine_price_history(medicine_id,old_price,new_price,reason,created_by) VALUES(med.id,med.price,amount,hf_api.required_text(p,'reason'),actor) RETURNING id::text INTO result;
 ELSIF p_action='holiday' THEN
 IF NOT hf_security.care_role(ARRAY['Admin']) THEN RAISE EXCEPTION 'Admin manages hospital holidays' USING ERRCODE='42501';END IF;
 holiday:=nullif(p->>'id','')::uuid;
 IF holiday IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hospitalflow.hospital_holidays WHERE id=holiday AND hospital_id=hf_security.current_hospital()) THEN RAISE EXCEPTION 'Holiday unavailable in this hospital' USING ERRCODE='42501';END IF;
 IF holiday IS NULL THEN holiday:=gen_random_uuid();INSERT INTO hospitalflow.hospital_holidays(id,name,on_date,kind) VALUES(holiday,hf_api.required_text(p,'name'),(p->>'day')::date,hf_api.required_text(p,'kind'));END IF;
 UPDATE hospitalflow.hospital_holidays SET name=hf_api.required_text(p,'name'),on_date=CASE WHEN COALESCE((p->>'annual')::boolean,false) THEN NULL ELSE(p->>'day')::date END,annual_month=CASE WHEN COALESCE((p->>'annual')::boolean,false) THEN extract(month FROM(p->>'day')::date) END,annual_day=CASE WHEN COALESCE((p->>'annual')::boolean,false) THEN extract(day FROM(p->>'day')::date) END,kind=hf_api.required_text(p,'kind'),is_leave=(p->>'isLeave')::boolean,active=COALESCE((p->>'active')::boolean,true),notes=left(COALESCE(p->>'notes',''),2000),source='Hospital Admin',updated_by=actor,updated_at=now() WHERE id=holiday;result:=holiday::text;
 ELSE RAISE EXCEPTION 'Unsupported enterprise action' USING ERRCODE='23514';END IF;
 PERFORM hf_security.audit('enterprise:'||p_action,result);
 INSERT INTO hospitalflow.care_command_keys(actor_id,key,action,request_hash,reference) VALUES(actor,p_key,'enterprise:'||p_action,p_hash,result);RETURN result;
END $$;

INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('HospitalFlow.Database.Migrations.027_patient_charge_summary.sql','CF3B2F0618569E9EFCCB8046943E7ADAC084E666BC27CDB37B8D786F6FF92A98');
COMMIT;
-- Provision the restricted application login separately; no password is embedded here.
