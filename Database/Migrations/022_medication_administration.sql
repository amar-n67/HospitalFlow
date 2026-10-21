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
