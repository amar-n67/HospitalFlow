-- Administrators may review their own attendance, within their assigned hospital.
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.booking_command(text,jsonb,boolean)'::regprocedure) INTO definition;
 definition:=replace(definition,'IF NOT FOUND OR attendance.user_id=actor THEN RAISE EXCEPTION ''Attendance is unavailable or belongs to you; another hospital administrator must review it''', 'IF NOT FOUND THEN RAISE EXCEPTION ''Attendance is unavailable in this hospital''');EXECUTE definition;
END $$;
-- Final duration is derived from the recorded timestamps, restricted to this IST calendar day.
-- Unfinished check-ins have no final duration; their live elapsed duration is returned separately.
ALTER TABLE hospitalflow.staff_attendance ADD COLUMN total_seconds bigint GENERATED ALWAYS AS (
 CASE WHEN status='Absent' THEN 0 WHEN check_in IS NULL OR check_out IS NULL THEN NULL
 ELSE greatest(0,extract(epoch FROM(least(check_out,(day+1)::timestamp AT TIME ZONE 'Asia/Kolkata')-greatest(check_in,day::timestamp AT TIME ZONE 'Asia/Kolkata')))::bigint) END) STORED;
CREATE OR REPLACE FUNCTION hf_api.booking_state() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE result jsonb;actor text;reviewer boolean;BEGIN
 result:=hf_api.booking_state_base();actor:=hf_api.booking_actor();reviewer:=hf_api.can_review_attendance();
 RETURN result || jsonb_build_object('canReviewAttendance',reviewer,'attendance',(SELECT COALESCE(jsonb_agg(to_jsonb(a)||jsonb_build_object('name',u.name,'registrationId',u.registration_id,'reviewerName',r.name,
 'totalHours',round(a.total_seconds/3600.0,2),
 'elapsedSeconds',CASE WHEN a.status='Present' AND a.check_in IS NOT NULL AND a.check_out IS NULL THEN greatest(0,extract(epoch FROM(least(now(),(a.day+1)::timestamp AT TIME ZONE 'Asia/Kolkata')-greatest(a.check_in,a.day::timestamp AT TIME ZONE 'Asia/Kolkata')))::bigint) ELSE a.total_seconds END)
 ORDER BY a.day DESC,a.submitted_at DESC),'[]') FROM hospitalflow.staff_attendance a JOIN hospitalflow.users u ON u.id=a.user_id LEFT JOIN hospitalflow.users r ON r.id=a.reviewed_by WHERE a.hospital_id=hf_security.current_hospital() AND (reviewer OR a.user_id=actor) AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor)));
END $$;
COMMENT ON COLUMN hospitalflow.staff_attendance.total_seconds IS 'Completed attendance duration in seconds within the recorded IST date; absent=0, no checkout=NULL. Approval remains separate from elapsed time.';
CREATE FUNCTION hf_api.manage_staff_attendance(p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text;target text;attendance_day date;presence text;started timestamptz;finished timestamptz;reason text;record_id uuid;BEGIN
 actor:=hf_api.booking_actor();IF NOT hf_api.can_review_attendance() THEN RAISE EXCEPTION 'Only an administrator assigned to this hospital can manage attendance' USING ERRCODE='42501';END IF;
 target:=p->>'userId';attendance_day:=(p->>'day')::date;presence:=p->>'status';reason:=trim(COALESCE(p->>'reason',''));
 IF attendance_day IS NULL OR attendance_day>(now() AT TIME ZONE 'Asia/Kolkata')::date OR attendance_day<date '1900-01-01' OR presence IS NULL OR presence NOT IN ('Present','Absent') OR length(reason) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'Choose a valid attendance date, status and reason of 5–500 characters' USING ERRCODE='23514';END IF;
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.users u JOIN hospitalflow.hospital_memberships m ON m.user_id=u.id AND m.hospital_id=hf_security.current_hospital() AND m.active WHERE u.id=target AND u.active AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id)) THEN RAISE EXCEPTION 'Choose an employee assigned to this hospital' USING ERRCODE='42501';END IF;
 IF presence='Present' THEN
 started:=NULLIF(p->>'checkIn','')::timestamptz;finished:=NULLIF(p->>'checkOut','')::timestamptz;
 IF started IS NULL OR (started AT TIME ZONE 'Asia/Kolkata')::date<>attendance_day OR started>now() OR(finished IS NOT NULL AND(finished<started OR finished>now() OR (finished AT TIME ZONE 'Asia/Kolkata')::date<>attendance_day)) THEN RAISE EXCEPTION 'Enter valid check-in/out times on the selected IST date, without future times' USING ERRCODE='23514';END IF;
 END IF;
 PERFORM pg_advisory_xact_lock(74192301);
 INSERT INTO hospitalflow.staff_attendance(user_id,day,status,check_in,check_out,marked_by,approval_status,reviewed_by,reviewed_at,review_note)
 VALUES(target,attendance_day,presence,started,finished,actor,'Approved',actor,now(),reason)
 ON CONFLICT(hospital_id,user_id,day) DO UPDATE SET status=EXCLUDED.status,check_in=EXCLUDED.check_in,check_out=EXCLUDED.check_out,marked_by=actor,approval_status='Approved',reviewed_by=actor,reviewed_at=now(),review_note=reason,submitted_at=now() RETURNING id INTO record_id;
 PERFORM hf_security.audit('attendance-admin-managed',record_id::text);
 RETURN jsonb_build_object('reference',record_id,'state','Approved');
END $$;
REVOKE ALL ON FUNCTION hf_api.manage_staff_attendance(jsonb) FROM PUBLIC;
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.booking_command(text,jsonb,boolean)'::regprocedure) INTO definition;
 definition:=replace(definition,' IF p_action NOT IN', ' IF p_action=''manage-attendance'' THEN RETURN hf_api.manage_staff_attendance(p);END IF;
 IF p_action NOT IN');EXECUTE definition;
END $$;
