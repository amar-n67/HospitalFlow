-- Shared staff availability exposes approved dates and identities, never private leave reasons.
CREATE FUNCTION hf_api.hospital_leave_calendar() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text;today date:=(now() AT TIME ZONE 'Asia/Kolkata')::date;BEGIN
 actor:=hf_api.booking_actor();
 IF EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor) THEN RAISE EXCEPTION 'The hospital staff leave calendar is unavailable to patient accounts' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('hospitalId',hf_security.current_hospital(),'hospitalName',(SELECT name FROM hospitalflow.hospitals WHERE id=hf_security.current_hospital()),'asOf',today,
 'leaves',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',l.id,'name',u.name,'registrationId',u.registration_id,'role',u.role,'department',COALESCE(p.department,s.department,''),'startsOn',l.starts_on,'endsOn',l.ends_on,'daysRemaining',CASE WHEN l.starts_on<=today THEN l.ends_on-today+1 ELSE NULL END,'availability',CASE WHEN l.starts_on<=today THEN 'On leave' ELSE 'Upcoming' END) ORDER BY CASE WHEN l.starts_on<=today THEN 0 ELSE 1 END,l.starts_on,u.name),'[]')
 FROM hospitalflow.staff_leaves l JOIN hospitalflow.users u ON u.id=l.user_id
 JOIN hospitalflow.hospital_memberships m ON m.user_id=u.id AND m.hospital_id=l.hospital_id AND m.active
 LEFT JOIN hospitalflow.person_profiles p ON p.user_id=u.id LEFT JOIN hospitalflow.staff_members s ON s.user_id=u.id AND s.hospital_id=l.hospital_id AND s.active
 WHERE l.hospital_id=hf_security.current_hospital() AND l.status='Approved' AND l.ends_on>=today AND u.active AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id)));
END $$;
REVOKE ALL ON FUNCTION hf_api.hospital_leave_calendar() FROM PUBLIC;
