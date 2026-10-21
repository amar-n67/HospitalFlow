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
