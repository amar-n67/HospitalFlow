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
COMMIT;
-- Provision the restricted application login separately; no password is embedded here.
