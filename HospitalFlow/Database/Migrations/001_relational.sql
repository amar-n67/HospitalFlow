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
