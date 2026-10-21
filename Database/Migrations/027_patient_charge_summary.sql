-- Refresh only the requesting identity's authorized active stays; no duplicate daily entries.
CREATE FUNCTION hf_api.refresh_finance_charges() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();a record;BEGIN
 IF NOT(hf_security.care_role(ARRAY['Admin','Billing','Doctor','Nurse','Pharmacist']) OR EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor)) THEN RAISE EXCEPTION 'Patient billing access required' USING ERRCODE='42501';END IF;
 FOR a IN SELECT s.id FROM hospitalflow.admissions s WHERE s.hospital_id=hf_security.current_hospital() AND s.status='Admitted' AND(hf_security.care_role(ARRAY['Admin','Billing','Pharmacist']) OR hf_security.can_read_care(s.patient_id)) LOOP
 PERFORM set_config('hospitalflow.actor_id','',true);PERFORM hf_api.accrue_stay_charges(a.id);PERFORM set_config('hospitalflow.actor_id',actor,true);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION hf_api.refresh_finance_charges() FROM PUBLIC;
CREATE OR REPLACE FUNCTION hf_api.enterprise_command(p_action text,p jsonb,p_key uuid,p_hash text,p_test boolean) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();result text;prior hospitalflow.care_command_keys%ROWTYPE;b hospitalflow.bills%ROWTYPE;bal numeric;amount numeric;line text;method text;med hospitalflow.medicine_batches%ROWTYPE;holiday uuid;pid text;entry record;total_due numeric;child_key uuid;BEGIN
 IF p_key IS NULL OR p_hash!~'^[A-Fa-f0-9]{64}$' OR jsonb_typeof(p)<>'object' THEN RAISE EXCEPTION 'Valid retry key and details required' USING ERRCODE='23514';END IF;
 PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO prior FROM hospitalflow.care_command_keys WHERE actor_id=actor AND key=p_key;
 IF FOUND THEN IF prior.action<>'enterprise:'||p_action OR prior.request_hash<>p_hash THEN RAISE EXCEPTION 'Retry key belongs to different details' USING ERRCODE='23514';END IF;RETURN prior.reference;END IF;
 IF p_action IN ('discount','portal-pay') THEN
 SELECT * INTO b FROM hospitalflow.bills WHERE id=hf_api.required_text(p,'invoiceId') AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Invoice unavailable' USING ERRCODE='23514';END IF;
 IF p_action='discount' THEN
 IF NOT (hf_security.care_role(ARRAY['Admin','Billing']) OR (hf_security.care_role(ARRAY['Doctor']) AND hf_security.can_read_care(b.patient_id)) OR (hf_security.care_role(ARRAY['Pharmacist']) AND EXISTS(SELECT 1 FROM hospitalflow.bill_lines l JOIN hospitalflow.invoice_line_context x ON x.line_id=l.id WHERE l.bill_id=b.id AND x.medicine_id IS NOT NULL) AND NOT EXISTS(SELECT 1 FROM hospitalflow.bill_lines l WHERE l.bill_id=b.id AND l.amount>0 AND NOT EXISTS(SELECT 1 FROM hospitalflow.invoice_line_context x WHERE x.line_id=l.id AND x.medicine_id IS NOT NULL)))) THEN RAISE EXCEPTION 'Discount requires hospital Admin/Billing, an authorized Doctor, or Pharmacy for medicine-only invoices' USING ERRCODE='42501';END IF;
 ELSE
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor AND patient_id=b.patient_id) THEN RAISE EXCEPTION 'Only the invoice patient can use portal payment' USING ERRCODE='42501';END IF;
 IF COALESCE((p->>'confirmed')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'Confirm the TEST payment before continuing' USING ERRCODE='23514';END IF;
 IF NOT p_test THEN RAISE EXCEPTION 'Online payment provider is not configured; payment was not taken' USING ERRCODE='23514';END IF;
 END IF;
 amount:=hf_api.positive_number(p,'amount');IF amount<>round(amount,2) THEN RAISE EXCEPTION 'Use at most two decimal places' USING ERRCODE='23514';END IF;SELECT balance INTO bal FROM hospitalflow.invoice_balances WHERE id=b.id;
 IF amount>bal THEN RAISE EXCEPTION 'Amount exceeds the current outstanding balance' USING ERRCODE='23514';END IF;
 IF p_action='discount' THEN
 line:=hf_api.new_id('DISC');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(line,b.id,'Discount: '||hf_api.required_text(p,'reason'),-amount);
 INSERT INTO hospitalflow.invoice_discounts(line_id,bill_id,amount,reason,created_by) VALUES(line,b.id,amount,hf_api.required_text(p,'reason'),actor);
 INSERT INTO hospitalflow.care_extra_categories(line_id,category) VALUES(line,'Discount');result:=line;
 PERFORM hf_api.care_event(b.patient_id,'Discount applied','INR '||amount||' · '||hf_api.required_text(p,'reason'),line);
 ELSE
 method:=hf_api.required_text(p,'method');IF method NOT IN ('UPI','Netbanking','Card','QR') THEN RAISE EXCEPTION 'Choose a supported payment option' USING ERRCODE='23514';END IF;
 line:=hf_api.new_id('PAY');INSERT INTO hospitalflow.payments(id,bill_id,amount,method,at) VALUES(line,b.id,amount,CASE method WHEN 'Netbanking' THEN 'Bank transfer' WHEN 'QR' THEN 'UPI' ELSE method END,now());
 INSERT INTO hospitalflow.portal_payments(bill_id,payment_id,patient_id,amount,method,mode,paid_by) VALUES(b.id,line,b.patient_id,amount,method,'Test',actor) RETURNING id::text INTO result;
 PERFORM hf_api.care_event(b.patient_id,'Portal payment','TEST payment · '||method||' · INR '||amount,line);
 END IF;
 ELSIF p_action='portal-pay-total' THEN
 SELECT patient_id INTO pid FROM hospitalflow.patient_accounts WHERE user_id=actor;
 IF pid IS NULL THEN RAISE EXCEPTION 'Patient account required for total payment' USING ERRCODE='42501';END IF;
 PERFORM hf_api.refresh_finance_charges();
 SELECT COALESCE(sum(v.balance),0) INTO total_due FROM hospitalflow.invoice_balances v JOIN hospitalflow.bills bill ON bill.id=v.id WHERE bill.patient_id=pid AND bill.hospital_id=hf_security.current_hospital() AND v.balance>0;
 IF total_due<=0 OR total_due<>hf_api.positive_number(p,'amount') THEN RAISE EXCEPTION 'The total has changed. Refresh and review the current amount before paying.' USING ERRCODE='23514';END IF;
 FOR entry IN SELECT v.id,v.balance FROM hospitalflow.invoice_balances v JOIN hospitalflow.bills bill ON bill.id=v.id WHERE bill.patient_id=pid AND bill.hospital_id=hf_security.current_hospital() AND v.balance>0 ORDER BY v.id LOOP
 child_key:=md5(p_key::text||':'||entry.id)::uuid;
 PERFORM hf_api.enterprise_command('portal-pay',jsonb_build_object('invoiceId',entry.id,'amount',entry.balance,'method',p->>'method','confirmed',p->'confirmed'),child_key,p_hash,p_test);
 END LOOP;result:=p_key::text;
 ELSIF p_action='medicine-price' THEN
 IF NOT hf_security.care_role(ARRAY['Admin']) THEN RAISE EXCEPTION 'Admin manages medicine prices' USING ERRCODE='42501';END IF;
 SELECT * INTO STRICT med FROM hospitalflow.medicine_batches WHERE id=hf_api.required_text(p,'medicineId') AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 amount:=hf_api.positive_number(p,'price');IF amount<>round(amount,2) THEN RAISE EXCEPTION 'Use at most two decimal places' USING ERRCODE='23514';END IF;UPDATE hospitalflow.medicine_batches SET price=amount WHERE id=med.id;
 INSERT INTO hospitalflow.medicine_price_history(medicine_id,old_price,new_price,reason,created_by) VALUES(med.id,med.price,amount,hf_api.required_text(p,'reason'),actor) RETURNING id::text INTO result;
 ELSIF p_action='holiday' THEN
 IF NOT hf_security.care_role(ARRAY['Admin']) THEN RAISE EXCEPTION 'Admin manages hospital holidays' USING ERRCODE='42501';END IF;
 holiday:=nullif(p->>'id','')::uuid;
 IF holiday IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hospitalflow.hospital_holidays WHERE id=holiday AND hospital_id=hf_security.current_hospital()) THEN RAISE EXCEPTION 'Holiday unavailable in this hospital' USING ERRCODE='42501';END IF;
 IF holiday IS NULL THEN holiday:=gen_random_uuid();INSERT INTO hospitalflow.hospital_holidays(id,name,on_date,kind) VALUES(holiday,hf_api.required_text(p,'name'),(p->>'day')::date,hf_api.required_text(p,'kind'));END IF;
 UPDATE hospitalflow.hospital_holidays SET name=hf_api.required_text(p,'name'),on_date=CASE WHEN COALESCE((p->>'annual')::boolean,false) THEN NULL ELSE(p->>'day')::date END,annual_month=CASE WHEN COALESCE((p->>'annual')::boolean,false) THEN extract(month FROM(p->>'day')::date) END,annual_day=CASE WHEN COALESCE((p->>'annual')::boolean,false) THEN extract(day FROM(p->>'day')::date) END,kind=hf_api.required_text(p,'kind'),is_leave=(p->>'isLeave')::boolean,active=COALESCE((p->>'active')::boolean,true),notes=left(COALESCE(p->>'notes',''),2000),source='Hospital Admin',updated_by=actor,updated_at=now() WHERE id=holiday;result:=holiday::text;
 ELSE RAISE EXCEPTION 'Unsupported enterprise action' USING ERRCODE='23514';END IF;
 PERFORM hf_security.audit('enterprise:'||p_action,result);
 INSERT INTO hospitalflow.care_command_keys(actor_id,key,action,request_hash,reference) VALUES(actor,p_key,'enterprise:'||p_action,p_hash,result);RETURN result;
END $$;
