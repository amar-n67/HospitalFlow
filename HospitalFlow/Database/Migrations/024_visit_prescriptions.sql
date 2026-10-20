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
