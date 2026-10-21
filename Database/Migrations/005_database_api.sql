CREATE FUNCTION hf_security.actor_id() RETURNS text LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('hospitalflow.actor_id',true),'') $$;
CREATE FUNCTION hf_security.require_actor(p_roles text[]) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE u hospitalflow.users%ROWTYPE;BEGIN
 SELECT * INTO u FROM hospitalflow.users WHERE id=nullif(current_setting('hospitalflow.actor_id',true),'') AND active;
 IF NOT FOUND OR (u.role<>'Administrator' AND NOT(u.role=ANY(p_roles))) THEN RAISE EXCEPTION 'Active authorized application identity required' USING ERRCODE='42501';END IF;
 RETURN u.id;END $$;
CREATE FUNCTION hf_security.can_access_patient(p_patient text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM hospitalflow.users u WHERE u.id=nullif(current_setting('hospitalflow.actor_id',true),'') AND u.active AND
 (u.role='Administrator' OR EXISTS(SELECT 1 FROM hospitalflow.patient_access_grants g WHERE g.user_id=u.id AND g.patient_id=p_patient AND g.expires_at>now()) OR
 EXISTS(SELECT 1 FROM hospitalflow.admissions a JOIN hospitalflow.beds b ON b.id=a.bed_id JOIN hospitalflow.wards w ON w.name=b.ward JOIN hospitalflow.user_departments d ON d.department=w.department WHERE a.patient_id=p_patient AND a.status='Admitted' AND d.user_id=u.id))) $$;
CREATE FUNCTION hf_security.audit(p_action text,p_reference text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE v_actor text;v_name text;BEGIN
 v_actor:=nullif(current_setting('hospitalflow.actor_id',true),'');SELECT name INTO v_name FROM hospitalflow.users WHERE id=v_actor AND active;
 IF v_name IS NULL THEN RAISE EXCEPTION 'Audit requires an active actor' USING ERRCODE='42501';END IF;
 INSERT INTO hospitalflow.activity_log(id,actor,action,reference,at,actor_id,correlation_id,method)
 VALUES(gen_random_uuid()::text,v_name,p_action,p_reference,clock_timestamp(),v_actor,nullif(current_setting('hospitalflow.correlation_id',true),''),'SQL');END $$;
CREATE FUNCTION hf_api.new_id(p_prefix text) RETURNS text LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF p_prefix!~'^[A-Z]{2,8}$' THEN RAISE EXCEPTION 'Invalid identifier prefix' USING ERRCODE='23514';END IF;
 RETURN p_prefix||'-'||nextval('hospitalflow.document_number')::text;END $$;
CREATE FUNCTION hf_api.required_text(p_body jsonb,p_key text,p_max integer DEFAULT 500) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text;BEGIN v:=trim(p_body->>p_key);IF jsonb_typeof(p_body->p_key)<>'string' OR v IS NULL OR length(v) NOT BETWEEN 1 AND p_max THEN
 RAISE EXCEPTION 'Required text field is invalid: %',p_key USING ERRCODE='23514';END IF;RETURN v;END $$;
CREATE FUNCTION hf_api.positive_number(p_body jsonb,p_key text,p_integer boolean DEFAULT false) RETURNS numeric LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE n numeric;BEGIN IF jsonb_typeof(p_body->p_key) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Numeric field required: %',p_key USING ERRCODE='23514';END IF;
 n:=(p_body->>p_key)::numeric;IF n<=0 OR n>10000000 OR (p_integer AND(n<>trunc(n) OR n>100000)) OR (NOT p_integer AND n<>round(n,2)) THEN
 RAISE EXCEPTION 'Positive value out of range: %',p_key USING ERRCODE='23514';END IF;RETURN n;END $$;
CREATE FUNCTION hf_api.hospital_today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE (SELECT value FROM hospitalflow.system_settings WHERE key='hospital_timezone'))::date $$;

CREATE PROCEDURE hf_api.save_patient(INOUT p_id text,IN p_name text,IN p_dob date,IN p_sex text,IN p_phone text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY['Reception']);PERFORM pg_advisory_xact_lock(74192301);
 IF length(trim(p_name)) NOT BETWEEN 1 AND 100 OR p_dob IS NULL OR p_dob<date '1900-01-01' OR p_dob>hf_api.hospital_today() OR p_phone!~'^\+?[0-9 ()-]{7,20}$' OR p_sex NOT IN ('Male','Female','Other','Prefer not to say') THEN RAISE EXCEPTION 'Invalid patient details' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.patients WHERE id IS DISTINCT FROM p_id AND dob=p_dob AND(lower(name)=lower(trim(p_name)) OR phone=p_phone)) THEN RAISE EXCEPTION 'Possible duplicate patient; review existing identity' USING ERRCODE='23505';END IF;
 IF p_id IS NULL THEN p_id:=hf_api.new_id('HF');INSERT INTO hospitalflow.patients VALUES(p_id,trim(p_name),p_dob,p_sex,p_phone,now());
 ELSE UPDATE hospitalflow.patients SET name=trim(p_name),dob=p_dob,sex=p_sex,phone=p_phone WHERE id=p_id;IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found' USING ERRCODE='23503';END IF;END IF;
 PERFORM hf_security.audit('procedure:save-patient',p_id);END $$;
CREATE PROCEDURE hf_api.book_appointment(INOUT p_id text,IN p_patient text,IN p_doctor text,IN p_at timestamptz,IN p_type text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY['Reception']);PERFORM pg_advisory_xact_lock(74192301);
 IF p_at<now() OR p_at IS NULL OR length(trim(p_type)) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'A future appointment and visit type are required' USING ERRCODE='23514';END IF;
 p_id:=hf_api.new_id('APT');INSERT INTO hospitalflow.appointments(id,patient_id,doctor_id,at,type,status) VALUES(p_id,p_patient,p_doctor,p_at,p_type,'Scheduled');
 PERFORM hf_security.audit('procedure:book-appointment',p_id);END $$;
CREATE PROCEDURE hf_api.set_appointment_status(IN p_id text,IN p_status text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE a hospitalflow.appointments%ROWTYPE;BEGIN PERFORM hf_security.require_actor(ARRAY['Reception']);PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO STRICT a FROM hospitalflow.appointments WHERE id=p_id FOR UPDATE;
 IF NOT((a.status='Scheduled' AND p_status IN ('Checked in','Cancelled','No show')) OR(a.status='Checked in' AND p_status IN ('In consultation','Cancelled')) OR(a.status='In consultation' AND p_status='Completed')) OR(p_status='No show' AND a.at>now()) THEN RAISE EXCEPTION 'Invalid appointment status transition' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.appointments SET status=p_status,checked_in=CASE WHEN p_status='Checked in' THEN now() ELSE checked_in END WHERE id=p_id;
 PERFORM hf_security.audit('procedure:appointment-status',p_id);END $$;
CREATE PROCEDURE hf_api.admit_patient(INOUT p_id text,IN p_patient text,IN p_bed text,IN p_reason text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY['Nurse']);PERFORM pg_advisory_xact_lock(74192301);
 IF length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Admission reason required' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.beds SET status='Occupied' WHERE id=p_bed AND status='Available' AND EXISTS(SELECT 1 FROM hospitalflow.wards w WHERE w.name=ward AND w.active);IF NOT FOUND THEN RAISE EXCEPTION 'Bed unavailable' USING ERRCODE='23514';END IF;
 p_id:=hf_api.new_id('ADM');INSERT INTO hospitalflow.admissions(id,patient_id,bed_id,reason,at,status) VALUES(p_id,p_patient,p_bed,p_reason,now(),'Admitted');
 INSERT INTO hospitalflow.admission_events(admission_id,kind,to_bed,reason,actor_id) VALUES(p_id,'Admission',p_bed,p_reason,hf_security.actor_id());
 PERFORM hf_security.audit('procedure:admit-patient',p_id);END $$;
CREATE PROCEDURE hf_api.transfer_patient(IN p_id text,IN p_bed text,IN p_reason text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE a hospitalflow.admissions%ROWTYPE;BEGIN PERFORM hf_security.require_actor(ARRAY['Nurse']);PERFORM pg_advisory_xact_lock(74192301);
 IF length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Transfer reason required' USING ERRCODE='23514';END IF;
 SELECT * INTO STRICT a FROM hospitalflow.admissions WHERE id=p_id AND status='Admitted' FOR UPDATE;
 UPDATE hospitalflow.beds SET status='Occupied' WHERE id=p_bed AND status='Available' AND EXISTS(SELECT 1 FROM hospitalflow.wards w WHERE w.name=ward AND w.active);IF NOT FOUND THEN RAISE EXCEPTION 'Destination bed unavailable' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.beds SET status='Cleaning' WHERE id=a.bed_id;UPDATE hospitalflow.admissions SET bed_id=p_bed WHERE id=p_id;
 INSERT INTO hospitalflow.admission_events(admission_id,kind,from_bed,to_bed,reason,actor_id) VALUES(p_id,'Transfer',a.bed_id,p_bed,p_reason,hf_security.actor_id());
 PERFORM hf_security.audit('procedure:transfer-patient',p_id||':'||a.bed_id||'->'||p_bed);END $$;
CREATE PROCEDURE hf_api.discharge_patient(IN p_id text,IN p_summary text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE a hospitalflow.admissions%ROWTYPE;BEGIN PERFORM hf_security.require_actor(ARRAY['Nurse']);PERFORM pg_advisory_xact_lock(74192301);
 IF length(trim(p_summary)) NOT BETWEEN 1 AND 4000 THEN RAISE EXCEPTION 'Discharge summary required' USING ERRCODE='23514';END IF;
 SELECT * INTO STRICT a FROM hospitalflow.admissions WHERE id=p_id AND status='Admitted' FOR UPDATE;
 IF EXISTS(SELECT 1 FROM hospitalflow.invoice_balances WHERE patient_id=a.patient_id AND balance>0) OR EXISTS(SELECT 1 FROM hospitalflow.prescriptions WHERE patient_id=a.patient_id AND status='Pending') OR EXISTS(SELECT 1 FROM hospitalflow.discharge_tasks WHERE admission_id=p_id AND required AND completed_at IS NULL) THEN RAISE EXCEPTION 'Discharge prerequisites are incomplete' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.notes VALUES(hf_api.new_id('NOTE'),a.patient_id,p_summary,'Discharge summary',now());
 UPDATE hospitalflow.admissions SET status='Discharged',discharged=now() WHERE id=p_id;UPDATE hospitalflow.beds SET status='Cleaning' WHERE id=a.bed_id;
 INSERT INTO hospitalflow.admission_events(admission_id,kind,from_bed,reason,actor_id) VALUES(p_id,'Discharge',a.bed_id,p_summary,hf_security.actor_id());
 PERFORM hf_security.audit('procedure:discharge-patient',p_id);END $$;
CREATE PROCEDURE hf_api.receive_stock(INOUT p_movement text,IN p_medicine text,IN p_quantity integer,IN p_reason text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY['Pharmacist']);PERFORM pg_advisory_xact_lock(74192301);
 IF p_quantity IS NULL OR p_quantity NOT BETWEEN 1 AND 100000 OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid receipt quantity or reference' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.medicine_batches SET quantity=quantity+p_quantity WHERE id=p_medicine AND expiry>hf_api.hospital_today();IF NOT FOUND THEN RAISE EXCEPTION 'Medicine batch missing or expired' USING ERRCODE='23514';END IF;
 p_movement:=hf_api.new_id('MOV');INSERT INTO hospitalflow.stock_movements VALUES(p_movement,p_medicine,p_quantity,p_reason,now());
 PERFORM hf_security.audit('procedure:receive-stock',p_movement);END $$;
CREATE PROCEDURE hf_api.dispense_prescription(IN p_id text,INOUT p_bill text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE r hospitalflow.prescriptions%ROWTYPE;m hospitalflow.medicine_batches%ROWTYPE;v_movement text;v_line text;v_reserved bigint;BEGIN
 PERFORM hf_security.require_actor(ARRAY['Pharmacist']);PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO STRICT r FROM hospitalflow.prescriptions WHERE id=p_id AND status='Pending' FOR UPDATE;
 SELECT * INTO STRICT m FROM hospitalflow.medicine_batches WHERE id=r.medicine_id FOR UPDATE;
 SELECT COALESCE(sum(quantity),0) INTO v_reserved FROM hospitalflow.stock_reservations WHERE medicine_id=m.id AND status='Active' AND prescription_id<>r.id;
 IF m.expiry<=hf_api.hospital_today() OR m.quantity-v_reserved<r.quantity OR EXISTS(SELECT 1 FROM hospitalflow.medicine_batch_holds WHERE medicine_id=m.id AND released_at IS NULL) THEN RAISE EXCEPTION 'Medicine expired, held or insufficient available stock' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.medicine_batches SET quantity=quantity-r.quantity WHERE id=m.id;
 v_movement:=hf_api.new_id('MOV');INSERT INTO hospitalflow.stock_movements VALUES(v_movement,m.id,-r.quantity,r.id,now());
 p_bill:=hf_api.new_id('INV');v_line:=hf_api.new_id('LINE');INSERT INTO hospitalflow.bills(id,patient_id) VALUES(p_bill,r.patient_id);
 INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(v_line,p_bill,m.name||' × '||r.quantity,m.price*r.quantity);
 INSERT INTO hospitalflow.invoice_line_context(line_id,medicine_id,quantity,unit_price) VALUES(v_line,m.id,r.quantity,m.price);
 UPDATE hospitalflow.prescriptions SET status='Dispensed' WHERE id=r.id;UPDATE hospitalflow.stock_reservations SET status='Consumed' WHERE prescription_id=r.id AND status='Active';
 INSERT INTO hospitalflow.prescription_dispensations(prescription_id,movement_id,bill_id,dispensed_by) VALUES(r.id,v_movement,p_bill,hf_security.actor_id());
 PERFORM hf_security.audit('procedure:dispense-prescription',r.id);END $$;
CREATE PROCEDURE hf_api.create_bill(INOUT p_id text,IN p_patient text,IN p_description text,IN p_amount numeric) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY['Billing']);PERFORM pg_advisory_xact_lock(74192301);
 IF p_amount IS NULL OR p_amount<=0 OR p_amount>10000000 OR p_amount<>round(p_amount,2) OR length(trim(p_description)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid invoice charge' USING ERRCODE='23514';END IF;
 p_id:=hf_api.new_id('INV');INSERT INTO hospitalflow.bills(id,patient_id) VALUES(p_id,p_patient);INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(hf_api.new_id('LINE'),p_id,p_description,p_amount);
 PERFORM hf_security.audit('procedure:create-bill',p_id);END $$;
CREATE PROCEDURE hf_api.post_payment(IN p_bill text,IN p_amount numeric,IN p_method text,INOUT p_id text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE v_balance numeric;BEGIN PERFORM hf_security.require_actor(ARRAY['Billing']);PERFORM pg_advisory_xact_lock(74192301);
 PERFORM 1 FROM hospitalflow.bills WHERE id=p_bill FOR UPDATE;SELECT balance INTO STRICT v_balance FROM hospitalflow.invoice_balances WHERE id=p_bill;
 IF p_amount IS NULL OR p_amount<=0 OR p_amount>v_balance OR p_amount<>round(p_amount,2) OR p_method NOT IN ('Cash','Card','UPI','Bank transfer') THEN RAISE EXCEPTION 'Payment exceeds balance or is invalid' USING ERRCODE='23514';END IF;
 p_id:=hf_api.new_id('PAY');INSERT INTO hospitalflow.payments VALUES(p_id,p_bill,p_amount,p_method,now());PERFORM hf_security.audit('procedure:post-payment',p_id);END $$;
CREATE PROCEDURE hf_api.post_adjustment(IN p_bill text,IN p_amount numeric,IN p_reason text,INOUT p_id text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE v_balance numeric;BEGIN PERFORM hf_security.require_actor(ARRAY['Billing']);PERFORM pg_advisory_xact_lock(74192301);
 PERFORM 1 FROM hospitalflow.bills WHERE id=p_bill FOR UPDATE;SELECT balance INTO STRICT v_balance FROM hospitalflow.invoice_balances WHERE id=p_bill;
 IF p_amount IS NULL OR p_amount<=0 OR p_amount>v_balance OR p_amount<>round(p_amount,2) OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid credit adjustment' USING ERRCODE='23514';END IF;
 p_id:=hf_api.new_id('ADJ');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(p_id,p_bill,'Adjustment: '||p_reason,-p_amount);PERFORM hf_security.audit('procedure:post-adjustment',p_id);END $$;
CREATE PROCEDURE hf_api.reverse_payment(IN p_payment text,IN p_amount numeric,IN p_reason text,INOUT p_id uuid) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE v_amount numeric;v_reversed numeric;BEGIN PERFORM hf_security.require_actor(ARRAY[]::text[]);PERFORM pg_advisory_xact_lock(74192301);
 SELECT amount INTO STRICT v_amount FROM hospitalflow.payments WHERE id=p_payment;SELECT COALESCE(sum(amount),0) INTO v_reversed FROM hospitalflow.payment_reversals WHERE payment_id=p_payment;
 IF p_amount IS NULL OR p_amount<=0 OR p_amount<>round(p_amount,2) OR p_amount+v_reversed>v_amount OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid payment reversal' USING ERRCODE='23514';END IF;
 p_id:=gen_random_uuid();INSERT INTO hospitalflow.payment_reversals(id,payment_id,amount,reason,approved_by) VALUES(p_id,p_payment,p_amount,p_reason,hf_security.actor_id());PERFORM hf_security.audit('procedure:reverse-payment',p_id::text);END $$;
CREATE PROCEDURE hf_api.post_service_charge(IN p_bill text,IN p_service uuid,IN p_quantity numeric,INOUT p_id text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE v_price hospitalflow.service_prices%ROWTYPE;v_name text;BEGIN PERFORM hf_security.require_actor(ARRAY['Billing']);PERFORM pg_advisory_xact_lock(74192301);
 IF p_quantity IS NULL OR p_quantity<=0 OR p_quantity>100000 OR p_quantity<>round(p_quantity,3) THEN RAISE EXCEPTION 'Invalid service quantity' USING ERRCODE='23514';END IF;
 SELECT name INTO STRICT v_name FROM hospitalflow.service_catalog WHERE id=p_service AND active;
 SELECT * INTO STRICT v_price FROM hospitalflow.service_prices WHERE service_id=p_service AND effective_from<=now() AND(effective_to IS NULL OR effective_to>now()) ORDER BY effective_from DESC LIMIT 1;
 p_id:=hf_api.new_id('LINE');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(p_id,p_bill,v_name,round(v_price.amount*p_quantity,2));
 INSERT INTO hospitalflow.invoice_line_context(line_id,service_price_id,quantity,unit_price,currency) VALUES(p_id,v_price.id,p_quantity,v_price.amount,v_price.currency);PERFORM hf_security.audit('procedure:post-service-charge',p_id);END $$;
CREATE PROCEDURE hf_api.reserve_prescription(IN p_prescription text,INOUT p_id uuid) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE r hospitalflow.prescriptions%ROWTYPE;v_available bigint;BEGIN PERFORM hf_security.require_actor(ARRAY['Pharmacist']);PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO STRICT r FROM hospitalflow.prescriptions WHERE id=p_prescription AND status='Pending' FOR UPDATE;
 SELECT quantity-(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_reservations WHERE medicine_id=r.medicine_id AND status='Active') INTO STRICT v_available FROM hospitalflow.medicine_batches WHERE id=r.medicine_id AND expiry>hf_api.hospital_today();
 IF v_available<r.quantity OR EXISTS(SELECT 1 FROM hospitalflow.medicine_batch_holds WHERE medicine_id=r.medicine_id AND released_at IS NULL) THEN RAISE EXCEPTION 'Insufficient available stock for reservation' USING ERRCODE='23514';END IF;
 p_id:=gen_random_uuid();INSERT INTO hospitalflow.stock_reservations(id,prescription_id,medicine_id,quantity,status) VALUES(p_id,r.id,r.medicine_id,r.quantity,'Active');PERFORM hf_security.audit('procedure:reserve-prescription',p_id::text);END $$;
CREATE PROCEDURE hf_api.approve_purchase_order(IN p_id uuid) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY[]::text[]);PERFORM pg_advisory_xact_lock(74192301);
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.purchase_order_lines WHERE purchase_order_id=p_id) THEN RAISE EXCEPTION 'Purchase order has no lines' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.purchase_orders SET status='Approved',approved_by=hf_security.actor_id() WHERE id=p_id AND status='Draft' AND EXISTS(SELECT 1 FROM hospitalflow.suppliers WHERE id=supplier_id AND active);
 IF NOT FOUND THEN RAISE EXCEPTION 'Purchase order unavailable for approval' USING ERRCODE='23514';END IF;PERFORM hf_security.audit('procedure:approve-purchase-order',p_id::text);END $$;
CREATE PROCEDURE hf_api.receive_purchase_order(IN p_order uuid,IN p_reference text,IN p_lines jsonb,INOUT p_id uuid) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE item jsonb;l hospitalflow.purchase_order_lines%ROWTYPE;n integer;already bigint;movement text;v_order hospitalflow.purchase_orders%ROWTYPE;BEGIN
 PERFORM hf_security.require_actor(ARRAY['Pharmacist']);PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO STRICT v_order FROM hospitalflow.purchase_orders WHERE id=p_order AND status IN ('Approved','Partially received') FOR UPDATE;
 IF jsonb_typeof(p_lines) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lines)=0 OR length(trim(p_reference)) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Receipt lines and reference required' USING ERRCODE='23514';END IF;
 p_id:=gen_random_uuid();INSERT INTO hospitalflow.goods_receipts(id,purchase_order_id,reference,received_by) VALUES(p_id,p_order,p_reference,hf_security.actor_id());
 FOR item IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
 SELECT * INTO STRICT l FROM hospitalflow.purchase_order_lines WHERE id=(item->>'lineId')::uuid AND purchase_order_id=p_order FOR UPDATE;
 n:=hf_api.positive_number(item,'quantity',true)::integer;SELECT COALESCE(sum(quantity),0) INTO already FROM hospitalflow.goods_receipt_lines WHERE purchase_order_line_id=l.id;
 IF n+already>l.quantity THEN RAISE EXCEPTION 'Receipt exceeds ordered quantity' USING ERRCODE='23514';END IF;
 CALL hf_api.receive_stock(movement,l.medicine_id,n,'Purchase receipt '||p_id::text);
 INSERT INTO hospitalflow.goods_receipt_lines(receipt_id,purchase_order_line_id,quantity,movement_id) VALUES(p_id,l.id,n,movement);
 END LOOP;
 UPDATE hospitalflow.purchase_orders SET status=CASE WHEN EXISTS(SELECT 1 FROM hospitalflow.purchase_order_lines pl WHERE pl.purchase_order_id=p_order AND pl.quantity>(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.goods_receipt_lines WHERE purchase_order_line_id=pl.id)) THEN 'Partially received'::hospitalflow.purchase_status ELSE 'Received'::hospitalflow.purchase_status END WHERE id=p_order;
 PERFORM hf_security.audit('procedure:receive-purchase-order',p_id::text);END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hf_security,hf_api FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA hf_api FROM PUBLIC;
