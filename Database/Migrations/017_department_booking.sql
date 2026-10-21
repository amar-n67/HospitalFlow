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
