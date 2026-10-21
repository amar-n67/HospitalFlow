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
