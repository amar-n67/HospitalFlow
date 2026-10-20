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
