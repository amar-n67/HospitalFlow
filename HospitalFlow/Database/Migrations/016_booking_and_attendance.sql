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
