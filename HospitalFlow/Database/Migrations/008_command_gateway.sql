CREATE FUNCTION hf_api.execute(p_action text,p_payload jsonb,p_key uuid,p_hash text) RETURNS text LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text;allowed text[];result text;ref text;original hospitalflow.idempotency_keys%ROWTYPE;uid uuid;tmp text;
 n numeric;n2 numeric;d date;from_time timestamptz;item jsonb;u hospitalflow.users%ROWTYPE;batch hospitalflow.medicine_batches%ROWTYPE;po uuid;
BEGIN
 IF jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR p_key IS NULL OR p_hash IS NULL OR p_hash!~'^[A-Fa-f0-9]{64}$' THEN RAISE EXCEPTION 'Object payload, retry key and keyed fingerprint required' USING ERRCODE='23514';END IF;
 allowed:=CASE
 WHEN p_action IN ('patient','patient-update','appointment','appointment-status','book-follow-up') THEN ARRAY['Reception']
 WHEN p_action IN ('admit','transfer','discharge','bed-status','discharge-task','complete-discharge-task') THEN ARRAY['Nurse']
 WHEN p_action IN ('medicine','stock','dispense','purchase-order','receive-purchase-order','hold-batch','release-batch','reserve-prescription','release-reservation','stock-adjustment') THEN ARRAY['Pharmacist']
 WHEN p_action IN ('bill','payment','adjustment','service-charge') THEN ARRAY['Billing']
 WHEN p_action IN ('prescription','cancel-prescription') THEN ARRAY['Doctor'] WHEN p_action IN ('note','clinical-order','complete-clinical-order','follow-up','clinical-order-status') THEN ARRAY['Doctor','Nurse']
 WHEN p_action IN ('patient-contact','patient-consent','revoke-consent') THEN ARRAY['Reception','Doctor','Nurse']
 WHEN p_action='notification-ack' THEN ARRAY['Reception','Doctor','Nurse','Pharmacist','Billing']
 WHEN p_action IN ('doctor','bed','user','user-status','supplier','approve-purchase-order','service','service-price','reverse-payment','provider-absence','cancel-absence','provider-session','grant-patient-access','staff-member','grant-department','ward-department','hospital-profile') THEN ARRAY[]::text[]
 ELSE NULL END;
 IF allowed IS NULL THEN RAISE EXCEPTION 'Unknown database command' USING ERRCODE='23514';END IF;
 actor:=hf_security.require_actor(allowed);PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO original FROM hospitalflow.idempotency_keys WHERE user_id=actor AND key=p_key;
 IF FOUND THEN IF original.action<>p_action OR original.request_hash<>p_hash THEN RAISE EXCEPTION 'Retry key already used for a different request' USING ERRCODE='23514';END IF;RETURN original.reference;END IF;
 CASE p_action
 WHEN 'patient','patient-update' THEN
 result:=CASE WHEN p_action='patient-update' THEN hf_api.required_text(p_payload,'id') END;
 CALL hf_api.save_patient(result,hf_api.required_text(p_payload,'name',100),hf_api.required_text(p_payload,'dob')::date,hf_api.required_text(p_payload,'sex'),hf_api.required_text(p_payload,'phone',20));
 WHEN 'doctor' THEN result:=hf_api.new_id('DR');INSERT INTO hospitalflow.departments(name) VALUES(hf_api.required_text(p_payload,'department',80)) ON CONFLICT DO NOTHING;
 INSERT INTO hospitalflow.doctors(id,name,department,start,"end") VALUES(result,hf_api.required_text(p_payload,'name',100),hf_api.required_text(p_payload,'department',80),hf_api.required_text(p_payload,'start')::time,hf_api.required_text(p_payload,'end')::time);
 WHEN 'bed' THEN result:=hf_api.required_text(p_payload,'id',50);IF EXISTS(SELECT 1 FROM hospitalflow.beds WHERE lower(id)=lower(result)) THEN RAISE EXCEPTION 'Bed identifier exists' USING ERRCODE='23505';END IF;
 INSERT INTO hospitalflow.wards(name) VALUES(hf_api.required_text(p_payload,'ward',100)) ON CONFLICT DO NOTHING;
 INSERT INTO hospitalflow.beds(id,ward,category,status) VALUES(result,hf_api.required_text(p_payload,'ward',100),hf_api.required_text(p_payload,'category',100),'Available');
 WHEN 'appointment' THEN CALL hf_api.book_appointment(result,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'doctorId'),hf_api.required_text(p_payload,'at')::timestamptz,hf_api.required_text(p_payload,'type',100));
 WHEN 'appointment-status' THEN result:=hf_api.required_text(p_payload,'id');CALL hf_api.set_appointment_status(result,hf_api.required_text(p_payload,'status'));
 WHEN 'admit' THEN CALL hf_api.admit_patient(result,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'bedId'),hf_api.required_text(p_payload,'reason'));
 WHEN 'transfer' THEN result:=hf_api.required_text(p_payload,'id');CALL hf_api.transfer_patient(result,hf_api.required_text(p_payload,'bedId'),hf_api.required_text(p_payload,'reason'));
 WHEN 'discharge' THEN result:=hf_api.required_text(p_payload,'id');CALL hf_api.discharge_patient(result,hf_api.required_text(p_payload,'summary',4000));
 WHEN 'bed-status' THEN result:=hf_api.required_text(p_payload,'id');ref:=hf_api.required_text(p_payload,'status');
 IF ref NOT IN ('Available','Cleaning','Maintenance') THEN RAISE EXCEPTION 'Invalid manual bed state' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.beds SET status=ref WHERE id=result AND status<>'Occupied';IF NOT FOUND THEN RAISE EXCEPTION 'Bed missing or occupied' USING ERRCODE='23514';END IF;
 WHEN 'medicine' THEN
 result:=hf_api.new_id('MED');d:=hf_api.required_text(p_payload,'expiry')::date;n:=(p_payload->>'quantity')::numeric;
 IF d<=hf_api.hospital_today() OR jsonb_typeof(p_payload->'quantity') IS DISTINCT FROM 'number' OR n IS NULL OR n<0 OR n>100000 OR n<>trunc(n) THEN RAISE EXCEPTION 'Invalid batch expiry or opening quantity' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.medicine_batches VALUES(result,hf_api.required_text(p_payload,'name'),hf_api.required_text(p_payload,'batch'),d,n::integer,hf_api.positive_number(p_payload,'reorder',true)::integer,hf_api.positive_number(p_payload,'price'));
 IF n>0 THEN INSERT INTO hospitalflow.stock_movements VALUES(hf_api.new_id('MOV'),result,n::integer,'Opening stock',now());END IF;
 WHEN 'stock' THEN CALL hf_api.receive_stock(result,hf_api.required_text(p_payload,'id'),hf_api.positive_number(p_payload,'quantity',true)::integer,hf_api.required_text(p_payload,'reason'));
 WHEN 'prescription' THEN result:=hf_api.new_id('RX');INSERT INTO hospitalflow.prescriptions VALUES(result,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'medicineId'),hf_api.positive_number(p_payload,'quantity',true)::integer,hf_api.required_text(p_payload,'instructions'),'Pending');INSERT INTO hospitalflow.prescription_authors(prescription_id,created_by) VALUES(result,actor);
 WHEN 'dispense' THEN result:=hf_api.required_text(p_payload,'id');CALL hf_api.dispense_prescription(result,tmp);
 WHEN 'bill' THEN CALL hf_api.create_bill(result,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'description'),hf_api.positive_number(p_payload,'amount'));
 WHEN 'payment' THEN CALL hf_api.post_payment(hf_api.required_text(p_payload,'id'),hf_api.positive_number(p_payload,'amount'),hf_api.required_text(p_payload,'method'),result);
 WHEN 'adjustment' THEN CALL hf_api.post_adjustment(hf_api.required_text(p_payload,'id'),hf_api.positive_number(p_payload,'amount'),hf_api.required_text(p_payload,'reason'),result);
 WHEN 'note' THEN result:=hf_api.new_id('NOTE');INSERT INTO hospitalflow.notes VALUES(result,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'text',4000),'Operational note',now());
 WHEN 'user' THEN
 result:=hf_api.new_id('USR');ref:=hf_api.required_text(p_payload,'email',150);tmp:=hf_api.required_text(p_payload,'passwordHash',1000);
 IF ref!~'^[^@ ]+@[^@ ]+$' OR length(tmp)<50 OR tmp!~'^[A-Za-z0-9+/=]+$' THEN RAISE EXCEPTION 'Valid email and application-generated password hash required' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.users(id,name,email,role,password_hash,active) VALUES(result,hf_api.required_text(p_payload,'name',100),ref,hf_api.required_text(p_payload,'role'),tmp,true);
 WHEN 'user-status' THEN result:=hf_api.required_text(p_payload,'id');
 IF jsonb_typeof(p_payload->'active') IS DISTINCT FROM 'boolean' OR result=actor THEN RAISE EXCEPTION 'Invalid account status change or self-disable request' USING ERRCODE='23514';END IF;
 SELECT * INTO STRICT u FROM hospitalflow.users WHERE id=result FOR UPDATE;
 IF NOT(p_payload->>'active')::boolean AND u.role='Administrator' AND(SELECT count(*) FROM hospitalflow.users WHERE role='Administrator' AND active)<=1 THEN RAISE EXCEPTION 'An active administrator must remain' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.users SET active=(p_payload->>'active')::boolean WHERE id=result;IF NOT(p_payload->>'active')::boolean THEN DELETE FROM hospitalflow.sessions WHERE user_id=result;END IF;
 WHEN 'supplier' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.suppliers(id,code,name,contact_email,contact_phone) VALUES(uid,hf_api.required_text(p_payload,'code',50),hf_api.required_text(p_payload,'name',150),p_payload->>'email',p_payload->>'phone');result:=uid::text;
 WHEN 'purchase-order' THEN
 uid:=gen_random_uuid();IF jsonb_typeof(p_payload->'lines') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'lines') NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Purchase order requires 1 to 200 lines' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.purchase_orders(id,supplier_id,number,created_by) VALUES(uid,hf_api.required_text(p_payload,'supplierId')::uuid,hf_api.new_id('PO'),actor);
 FOR item IN SELECT * FROM jsonb_array_elements(p_payload->'lines') LOOP INSERT INTO hospitalflow.purchase_order_lines(purchase_order_id,medicine_id,quantity,unit_cost) VALUES(uid,hf_api.required_text(item,'medicineId'),hf_api.positive_number(item,'quantity',true)::integer,hf_api.positive_number(item,'unitCost'));END LOOP;result:=uid::text;
 WHEN 'approve-purchase-order' THEN result:=hf_api.required_text(p_payload,'id');CALL hf_api.approve_purchase_order(result::uuid);
 WHEN 'receive-purchase-order' THEN CALL hf_api.receive_purchase_order(hf_api.required_text(p_payload,'id')::uuid,hf_api.required_text(p_payload,'reference',200),p_payload->'lines',uid);result:=uid::text;
 WHEN 'hold-batch' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.medicine_batch_holds(id,medicine_id,reason,held_by) VALUES(uid,hf_api.required_text(p_payload,'medicineId'),hf_api.required_text(p_payload,'reason'),actor);result:=uid::text;
 WHEN 'release-batch' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.medicine_batch_holds SET released_by=actor,released_at=now() WHERE id=result::uuid AND released_at IS NULL;IF NOT FOUND THEN RAISE EXCEPTION 'Active hold not found' USING ERRCODE='23514';END IF;
 WHEN 'reserve-prescription' THEN CALL hf_api.reserve_prescription(hf_api.required_text(p_payload,'id'),uid);result:=uid::text;
 WHEN 'release-reservation' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.stock_reservations SET status='Released' WHERE id=result::uuid AND status='Active';IF NOT FOUND THEN RAISE EXCEPTION 'Active reservation missing' USING ERRCODE='23514';END IF;
 WHEN 'stock-adjustment' THEN
 ref:=hf_api.required_text(p_payload,'id');n:=(p_payload->>'quantity')::numeric;
 IF jsonb_typeof(p_payload->'quantity') IS DISTINCT FROM 'number' OR n IS NULL OR n=0 OR abs(n)>100000 OR n<>trunc(n) THEN RAISE EXCEPTION 'Signed whole-number adjustment required' USING ERRCODE='23514';END IF;
 PERFORM 1 FROM hospitalflow.medicine_batches WHERE id=ref FOR UPDATE;UPDATE hospitalflow.medicine_batches SET quantity=quantity+n::integer WHERE id=ref;
 result:=hf_api.new_id('MOV');INSERT INTO hospitalflow.stock_movements VALUES(result,ref,n::integer,hf_api.required_text(p_payload,'reason'),now());
 WHEN 'service' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.service_catalog(id,code,name,department,category) VALUES(uid,hf_api.required_text(p_payload,'code',50),hf_api.required_text(p_payload,'name',150),p_payload->>'department',hf_api.required_text(p_payload,'category'));result:=uid::text;
 WHEN 'service-price' THEN
 uid:=gen_random_uuid();po:=hf_api.required_text(p_payload,'serviceId')::uuid;from_time:=COALESCE((p_payload->>'effectiveFrom')::timestamptz,now());
 IF from_time<now()-interval '1 minute' THEN RAISE EXCEPTION 'Price periods cannot be backdated' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.service_prices SET effective_to=from_time WHERE service_id=po AND effective_from<from_time AND(effective_to IS NULL OR effective_to>from_time);
 INSERT INTO hospitalflow.service_prices(id,service_id,amount,effective_from,created_by) VALUES(uid,po,hf_api.positive_number(p_payload,'amount'),from_time,actor);result:=uid::text;
 WHEN 'service-charge' THEN CALL hf_api.post_service_charge(hf_api.required_text(p_payload,'id'),hf_api.required_text(p_payload,'serviceId')::uuid,hf_api.positive_number(p_payload,'quantity'),result);
 WHEN 'reverse-payment' THEN CALL hf_api.reverse_payment(hf_api.required_text(p_payload,'id'),hf_api.positive_number(p_payload,'amount'),hf_api.required_text(p_payload,'reason'),uid);result:=uid::text;
 WHEN 'provider-absence' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.provider_absences(id,doctor_id,starts_at,ends_at,reason_code,approved_by) VALUES(uid,hf_api.required_text(p_payload,'doctorId'),hf_api.required_text(p_payload,'startsAt')::timestamptz,hf_api.required_text(p_payload,'endsAt')::timestamptz,hf_api.required_text(p_payload,'reasonCode',100),actor);result:=uid::text;
 WHEN 'grant-patient-access' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.patient_access_grants(id,user_id,patient_id,purpose,expires_at,granted_by) VALUES(uid,hf_api.required_text(p_payload,'userId'),hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'purpose',200),hf_api.required_text(p_payload,'expiresAt')::timestamptz,actor);result:=uid::text;
 WHEN 'discharge-task' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.discharge_tasks(id,admission_id,code,required) VALUES(uid,hf_api.required_text(p_payload,'admissionId'),hf_api.required_text(p_payload,'code',100),COALESCE((p_payload->>'required')::boolean,true));result:=uid::text;
 WHEN 'complete-discharge-task' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.discharge_tasks SET completed_by=actor,completed_at=now() WHERE id=result::uuid AND completed_at IS NULL;IF NOT FOUND THEN RAISE EXCEPTION 'Pending discharge task not found' USING ERRCODE='23514';END IF;
 WHEN 'follow-up' THEN uid:=gen_random_uuid();from_time:=hf_api.required_text(p_payload,'dueAt')::timestamptz;IF from_time<=now() THEN RAISE EXCEPTION 'Future follow-up required' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.follow_ups(id,patient_id,admission_id,due_at,doctor_id,instructions,status) VALUES(uid,hf_api.required_text(p_payload,'patientId'),p_payload->>'admissionId',from_time,p_payload->>'doctorId',hf_api.required_text(p_payload,'instructions'),'Pending');result:=uid::text;
 WHEN 'clinical-order' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.clinical_orders(id,encounter_id,service_id,ordered_by,status) VALUES(uid,hf_api.required_text(p_payload,'encounterId')::uuid,hf_api.required_text(p_payload,'serviceId')::uuid,actor,'Requested');result:=uid::text;
 WHEN 'complete-clinical-order' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.clinical_orders SET status='Completed',completed_at=now() WHERE id=result::uuid AND status IN ('Requested','In progress');IF NOT FOUND THEN RAISE EXCEPTION 'Pending clinical order not found' USING ERRCODE='23514';END IF;
 WHEN 'cancel-prescription' THEN result:=hf_api.required_text(p_payload,'id');
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.users WHERE id=actor AND role='Administrator') AND NOT EXISTS(SELECT 1 FROM hospitalflow.prescription_authors WHERE prescription_id=result AND created_by=actor) THEN RAISE EXCEPTION 'Only the author or administrator can cancel a prescription' USING ERRCODE='42501';END IF;
 UPDATE hospitalflow.prescriptions SET status='Cancelled' WHERE id=result AND status='Pending';IF NOT FOUND THEN RAISE EXCEPTION 'Pending prescription not found' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.stock_reservations SET status='Released' WHERE prescription_id=result AND status='Active';
 WHEN 'patient-contact' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.patient_contacts(id,patient_id,name,relationship,phone,is_emergency) VALUES(uid,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'name',100),hf_api.required_text(p_payload,'relationship',100),hf_api.required_text(p_payload,'phone',20),COALESCE((p_payload->>'isEmergency')::boolean,false));result:=uid::text;
 WHEN 'patient-consent' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.patient_consents(id,patient_id,purpose,granted_at,expires_at,evidence_reference,recorded_by) VALUES(uid,hf_api.required_text(p_payload,'patientId'),hf_api.required_text(p_payload,'purpose',200),COALESCE((p_payload->>'grantedAt')::timestamptz,now()),(p_payload->>'expiresAt')::timestamptz,hf_api.required_text(p_payload,'evidenceReference',200),actor);result:=uid::text;
 WHEN 'revoke-consent' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.patient_consents SET revoked_at=now() WHERE id=result::uuid AND revoked_at IS NULL;IF NOT FOUND THEN RAISE EXCEPTION 'Active consent not found' USING ERRCODE='23514';END IF;
 WHEN 'staff-member' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.staff_members(id,user_id,doctor_id,employee_number,department,job_title) VALUES(uid,p_payload->>'userId',p_payload->>'doctorId',hf_api.required_text(p_payload,'employeeNumber',50),hf_api.required_text(p_payload,'department',80),hf_api.required_text(p_payload,'jobTitle',100));result:=uid::text;
 WHEN 'grant-department' THEN result:=hf_api.required_text(p_payload,'userId');INSERT INTO hospitalflow.user_departments(user_id,department) VALUES(result,hf_api.required_text(p_payload,'department',80)) ON CONFLICT DO NOTHING;
 WHEN 'ward-department' THEN result:=hf_api.required_text(p_payload,'ward',100);UPDATE hospitalflow.wards SET department=hf_api.required_text(p_payload,'department',80) WHERE name=result;IF NOT FOUND THEN RAISE EXCEPTION 'Ward not found' USING ERRCODE='23503';END IF;
 WHEN 'hospital-profile' THEN result:='1';UPDATE hospitalflow.hospital_profile SET name=hf_api.required_text(p_payload,'name',150),updated_at=now() WHERE id=1;
 WHEN 'provider-session' THEN uid:=gen_random_uuid();INSERT INTO hospitalflow.provider_sessions(id,doctor_id,starts_at,ends_at) VALUES(uid,hf_api.required_text(p_payload,'doctorId'),hf_api.required_text(p_payload,'startsAt')::timestamptz,hf_api.required_text(p_payload,'endsAt')::timestamptz);result:=uid::text;
 WHEN 'cancel-absence' THEN result:=hf_api.required_text(p_payload,'id');UPDATE hospitalflow.provider_absences SET cancelled_at=now() WHERE id=result::uuid AND cancelled_at IS NULL;IF NOT FOUND THEN RAISE EXCEPTION 'Active absence not found' USING ERRCODE='23514';END IF;
 WHEN 'clinical-order-status' THEN result:=hf_api.required_text(p_payload,'id');ref:=hf_api.required_text(p_payload,'status');IF ref NOT IN ('In progress','Cancelled') THEN RAISE EXCEPTION 'Use the completion command to finalize an order' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.clinical_orders SET status=ref WHERE id=result::uuid AND status IN ('Requested','In progress');IF NOT FOUND THEN RAISE EXCEPTION 'Open clinical order not found' USING ERRCODE='23514';END IF;
 WHEN 'book-follow-up' THEN
 uid:=hf_api.required_text(p_payload,'id')::uuid;SELECT patient_id,COALESCE(p_payload->>'doctorId',doctor_id) INTO STRICT ref,tmp FROM hospitalflow.follow_ups WHERE id=uid AND status='Pending' FOR UPDATE;
 CALL hf_api.book_appointment(result,ref,tmp,hf_api.required_text(p_payload,'at')::timestamptz,'Follow-up');UPDATE hospitalflow.follow_ups SET appointment_id=result,status='Booked' WHERE id=uid;
 WHEN 'notification-ack' THEN result:=hf_api.required_text(p_payload,'id');IF EXISTS(SELECT 1 FROM hospitalflow.notifications WHERE id=result AND target='pharmacy') THEN PERFORM hf_security.require_actor(ARRAY['Pharmacist','Doctor']);END IF;
 INSERT INTO hospitalflow.notification_acknowledgements(notification_id,user_id,reason) VALUES(result,actor,hf_api.required_text(p_payload,'reason'));
 END CASE;
 PERFORM hf_security.audit(p_action,result);
 INSERT INTO hospitalflow.idempotency_keys(user_id,key,action,request_hash,reference) VALUES(actor,p_key,p_action,p_hash,result);
 CALL hf_ops.refresh_alerts();RETURN result;
END $$;
REVOKE ALL ON FUNCTION hf_api.execute(text,jsonb,uuid,text) FROM PUBLIC;
COMMENT ON FUNCTION hf_api.execute(text,jsonb,uuid,text) IS 'Trusted-backend command gateway. Validates transaction-local actor, application role, idempotency and domain rules. Supply actor from authenticated session, not client input. Individual CALL procedures are lower-level operator tools.';
CREATE UNIQUE INDEX beds_casefold_id_unique ON hospitalflow.beds(lower(id));
CREATE FUNCTION hospitalflow.validate_absence() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);IF NEW.cancelled_at IS NULL AND EXISTS(SELECT 1 FROM hospitalflow.appointments WHERE doctor_id=NEW.doctor_id AND status IN ('Scheduled','Checked in','In consultation') AND at<NEW.ends_at AND at+interval '30 minutes'>NEW.starts_at) THEN RAISE EXCEPTION 'Cancel or reassign overlapping appointments before approving absence' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER absence_conflict BEFORE INSERT OR UPDATE ON hospitalflow.provider_absences FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_absence();
ALTER TABLE hospitalflow.prescriptions DROP CONSTRAINT prescriptions_status_check;
ALTER TABLE hospitalflow.prescriptions ADD CONSTRAINT prescriptions_status_check CHECK(status IN ('Pending','Dispensed','Cancelled'));
CREATE FUNCTION hospitalflow.validate_prescription_state() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF TG_OP='UPDATE' AND(OLD.status<>'Pending' AND to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD)) THEN RAISE EXCEPTION 'Finalized prescriptions cannot be rewritten' USING ERRCODE='23514';END IF;
 IF TG_OP='UPDATE' AND OLD.status='Pending' AND NEW.status NOT IN ('Pending','Dispensed','Cancelled') THEN RAISE EXCEPTION 'Invalid prescription state' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER prescription_state BEFORE UPDATE ON hospitalflow.prescriptions FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_prescription_state();
CREATE FUNCTION hospitalflow.validate_provider_session() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);
 IF EXISTS(SELECT 1 FROM hospitalflow.provider_sessions WHERE id<>NEW.id AND doctor_id=NEW.doctor_id AND starts_at<NEW.ends_at AND ends_at>NEW.starts_at) THEN RAISE EXCEPTION 'Provider sessions overlap' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER provider_session_overlap BEFORE INSERT OR UPDATE ON hospitalflow.provider_sessions FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_provider_session();
CREATE FUNCTION hospitalflow.complete_follow_up() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF NEW.status='Completed' THEN UPDATE hospitalflow.follow_ups SET status='Completed' WHERE appointment_id=NEW.id AND status='Booked';END IF;RETURN NEW;END $$;
CREATE TRIGGER follow_up_completion AFTER UPDATE OF status ON hospitalflow.appointments FOR EACH ROW EXECUTE FUNCTION hospitalflow.complete_follow_up();
ALTER DEFAULT PRIVILEGES IN SCHEMA hospitalflow,hf_api,hf_security,hf_reporting,hf_ops REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
