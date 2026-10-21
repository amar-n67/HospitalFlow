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
