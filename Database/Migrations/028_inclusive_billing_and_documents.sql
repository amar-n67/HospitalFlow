-- Inclusive tax splits preserve recorded invoice totals; tax settings and snapshots are audited.
CREATE TABLE hospitalflow.billing_tax_settings(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),bed_rate numeric(5,2) NOT NULL DEFAULT 18 CHECK(bed_rate BETWEEN 0 AND 100),medicine_rate numeric(5,2) NOT NULL DEFAULT 7 CHECK(medicine_rate BETWEEN 0 AND 100),other_rate numeric(5,2) NOT NULL DEFAULT 0 CHECK(other_rate BETWEEN 0 AND 100),configured_by text REFERENCES hospitalflow.users(id),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
INSERT INTO hospitalflow.billing_tax_settings(hospital_id) SELECT id FROM hospitalflow.hospitals;
CREATE TABLE hospitalflow.billing_tax_snapshots(line_id text PRIMARY KEY REFERENCES hospitalflow.bill_lines(id),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),setting_id uuid NOT NULL REFERENCES hospitalflow.billing_tax_settings(id),category text NOT NULL,rate numeric(5,2) NOT NULL CHECK(rate BETWEEN 0 AND 100),captured_at timestamptz NOT NULL DEFAULT now());
DO $$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['billing_tax_settings','billing_tax_snapshots'] LOOP
 EXECUTE format('ALTER TABLE hospitalflow.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('CREATE POLICY hospital_read ON hospitalflow.%I FOR SELECT USING(hospital_id=hf_security.current_hospital() AND hf_security.care_role(ARRAY[''Admin'',''Reception'']))',t);
 EXECUTE format('CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history()',t);
 EXECUTE format('CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes()',t);
 EXECUTE format('CREATE TRIGGER z_hospital_guard BEFORE INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hf_security.guard_hospital_row()',t);
END LOOP;END $$;
CREATE FUNCTION hf_security.billing_staff() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ SELECT hf_security.care_role(ARRAY['Admin','Reception']) AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=hf_security.actor_id()) $$;
CREATE FUNCTION hf_security.billing_pharmacy_only() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT hf_security.care_role(ARRAY['Pharmacist']) AND NOT hf_security.billing_staff() $$;
CREATE FUNCTION hf_security.medicine_invoice(p_bill text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ SELECT EXISTS(SELECT 1 FROM hospitalflow.bills WHERE id=p_bill AND hospital_id=hf_security.current_hospital()) AND EXISTS(SELECT 1 FROM hospitalflow.bill_lines l JOIN hospitalflow.invoice_line_context x ON x.line_id=l.id WHERE l.bill_id=p_bill AND x.medicine_id IS NOT NULL) AND NOT EXISTS(SELECT 1 FROM hospitalflow.bill_lines l WHERE l.bill_id=p_bill AND l.amount>0 AND NOT EXISTS(SELECT 1 FROM hospitalflow.invoice_line_context x WHERE x.line_id=l.id AND x.medicine_id IS NOT NULL)) $$;
CREATE FUNCTION hf_security.can_read_invoice(p_bill text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ SELECT EXISTS(SELECT 1 FROM hospitalflow.bills b WHERE b.id=p_bill AND b.hospital_id=hf_security.current_hospital() AND CASE WHEN hf_security.billing_pharmacy_only() THEN hf_security.medicine_invoice(b.id) ELSE hf_security.billing_staff() OR hf_security.care_role(ARRAY['Billing']) OR hf_security.can_read_care(b.patient_id) END) $$;
CREATE FUNCTION hf_security.guard_billing_discount() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ BEGIN
 IF NOT(hf_security.billing_staff() OR(hf_security.billing_pharmacy_only() AND hf_security.medicine_invoice(NEW.bill_id))) THEN RAISE EXCEPTION 'Reception/Admin may edit billing; Pharmacy may discount medicine-only invoices. Other roles are read-only.' USING ERRCODE='42501';END IF;RETURN NEW;
END $$;
CREATE TRIGGER billing_discount_editor BEFORE INSERT ON hospitalflow.invoice_discounts FOR EACH ROW EXECUTE FUNCTION hf_security.guard_billing_discount();
CREATE FUNCTION hf_api.snapshot_invoice_tax(p_bill text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$ DECLARE s hospitalflow.billing_tax_settings%ROWTYPE;original_actor text:=hf_security.actor_id();BEGIN
 IF nullif(original_actor,'') IS NOT NULL AND NOT hf_security.can_read_invoice(p_bill) THEN RAISE EXCEPTION 'Invoice access required' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM hospitalflow.bills WHERE id=p_bill AND hospital_id=hf_security.current_hospital()) THEN RAISE EXCEPTION 'Invoice unavailable' USING ERRCODE='42501';END IF;
 SELECT * INTO s FROM hospitalflow.billing_tax_settings WHERE hospital_id=hf_security.current_hospital() ORDER BY created_at DESC,id DESC LIMIT 1;
 IF NOT FOUND THEN INSERT INTO hospitalflow.billing_tax_settings(hospital_id) VALUES(hf_security.current_hospital()) RETURNING * INTO s;END IF;
 PERFORM set_config('hospitalflow.actor_id','',true);
 INSERT INTO hospitalflow.billing_tax_snapshots(line_id,setting_id,category,rate)
 SELECT l.id,s.id,c.category,CASE WHEN c.category IN ('Bed','Ward','ICU') THEN s.bed_rate WHEN c.category='Pharmacy' THEN s.medicine_rate ELSE s.other_rate END
 FROM hospitalflow.bill_lines l LEFT JOIN hospitalflow.care_charge_entries ce ON ce.line_id=l.id LEFT JOIN hospitalflow.care_extra_categories xc ON xc.line_id=l.id LEFT JOIN hospitalflow.invoice_line_context x ON x.line_id=l.id LEFT JOIN hospitalflow.service_prices sp ON sp.id=x.service_price_id LEFT JOIN hospitalflow.service_catalog sc ON sc.id=sp.service_id
 CROSS JOIN LATERAL(SELECT COALESCE(ce.category,xc.category,CASE WHEN x.medicine_id IS NOT NULL THEN 'Pharmacy' END,sc.category,'Other') category)c
 WHERE l.bill_id=p_bill AND l.amount>0 ON CONFLICT(line_id) DO NOTHING;
 PERFORM set_config('hospitalflow.actor_id',COALESCE(original_actor,''),true);
END $$;
CREATE FUNCTION hf_api.invoice_tax_detail(p_bill text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$ DECLARE result jsonb;BEGIN
 IF NOT hf_security.can_read_invoice(p_bill) THEN RAISE EXCEPTION 'Invoice access required' USING ERRCODE='42501';END IF;
 PERFORM hf_api.snapshot_invoice_tax(p_bill);
 WITH totals AS(SELECT COALESCE(sum(amount) FILTER(WHERE amount>0),0) gross,COALESCE(-sum(amount) FILTER(WHERE amount<0),0) credits FROM hospitalflow.bill_lines WHERE bill_id=p_bill), ordered AS(SELECT l.*,s.category,s.rate,sum(l.amount) OVER(ORDER BY l.created_at,l.id) cumulative FROM hospitalflow.bill_lines l JOIN hospitalflow.billing_tax_snapshots s ON s.line_id=l.id WHERE l.bill_id=p_bill AND l.amount>0), allocated AS(SELECT o.*,round(LEAST(t.credits,t.gross)*o.cumulative/NULLIF(t.gross,0),2)-round(LEAST(t.credits,t.gross)*(o.cumulative-o.amount)/NULLIF(t.gross,0),2) credit FROM ordered o CROSS JOIN totals t), detail AS(SELECT id,description,category,rate,amount gross,credit discount_credit,amount-credit inclusive_amount,round((amount-credit)/(1+rate/100),2) base_amount,(amount-credit)-round((amount-credit)/(1+rate/100),2) gst FROM allocated)
 SELECT jsonb_build_object('base',COALESCE(sum(base_amount),0),'gst',COALESCE(sum(gst),0),'grand_total',COALESCE(sum(inclusive_amount),0),'lines',COALESCE(jsonb_agg(to_jsonb(detail)),'[]')) INTO result FROM detail;RETURN result;
END $$;
CREATE OR REPLACE FUNCTION hf_security.require_actor(p_roles text[]) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE u hospitalflow.users%ROWTYPE;BEGIN
 IF p_roles=ARRAY['Billing']::text[] THEN IF NOT hf_security.billing_staff() THEN RAISE EXCEPTION 'Billing edits require Reception or Admin' USING ERRCODE='42501';END IF;RETURN hf_security.actor_id();END IF;
 SELECT * INTO u FROM hospitalflow.users WHERE id=nullif(current_setting('hospitalflow.actor_id',true),'') AND active AND email_confirmed;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id) OR u.role='Volunteer' OR
 (u.role NOT IN ('Admin','Developer') AND NOT(u.role=ANY(p_roles)) AND NOT EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id AND p.permission=ANY(p_roles))) THEN
 RAISE EXCEPTION 'Active authorized staff identity required' USING ERRCODE='42501';END IF;RETURN u.id;END $$;
CREATE OR REPLACE FUNCTION hf_api.refresh_finance_charges() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();a record;BEGIN
 IF NOT(hf_security.care_role(ARRAY['Admin','Reception','Billing','Doctor','Nurse','Pharmacist']) OR EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor)) THEN RAISE EXCEPTION 'Patient billing access required' USING ERRCODE='42501';END IF;
 FOR a IN SELECT s.id FROM hospitalflow.admissions s WHERE s.hospital_id=hf_security.current_hospital() AND s.status='Admitted' AND(hf_security.care_role(ARRAY['Admin','Reception','Billing','Pharmacist']) OR hf_security.can_read_care(s.patient_id)) LOOP
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
 IF NOT(hf_security.billing_staff() OR(hf_security.billing_pharmacy_only() AND hf_security.medicine_invoice(b.id))) THEN RAISE EXCEPTION 'Reception/Admin or medicine-only Pharmacy approval required' USING ERRCODE='42501';END IF;
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
 IF NOT (hf_security.billing_staff() OR hf_security.billing_pharmacy_only()) THEN RAISE EXCEPTION 'Reception/Admin or Pharmacy manages medicine prices' USING ERRCODE='42501';END IF;
 SELECT * INTO STRICT med FROM hospitalflow.medicine_batches WHERE id=hf_api.required_text(p,'medicineId') AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 amount:=hf_api.positive_number(p,'price');IF amount<>round(amount,2) THEN RAISE EXCEPTION 'Use at most two decimal places' USING ERRCODE='23514';END IF;UPDATE hospitalflow.medicine_batches SET price=amount WHERE id=med.id;
 INSERT INTO hospitalflow.medicine_price_history(medicine_id,old_price,new_price,reason,created_by) VALUES(med.id,med.price,amount,hf_api.required_text(p,'reason'),actor) RETURNING id::text INTO result;
 ELSIF p_action='charge' THEN
 IF NOT hf_security.billing_staff() THEN RAISE EXCEPTION 'Reception or Admin adds charges' USING ERRCODE='42501';END IF;
 pid:=hf_api.required_text(p,'patientId');IF NOT hf_security.enrolled_patient(pid) THEN RAISE EXCEPTION 'Patient is not registered at this hospital' USING ERRCODE='42501';END IF;
 amount:=hf_api.positive_number(p,'amount');result:=hf_api.new_id('INV');INSERT INTO hospitalflow.bills(id,patient_id) VALUES(result,pid);line:=hf_api.new_id('LINE');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(line,result,hf_api.required_text(p,'description'),amount);
 method:=hf_api.required_text(p,'category');IF method NOT IN ('Bed','Ward','ICU','Laboratory','Consultation','Nursing','Consumables','Other') THEN RAISE EXCEPTION 'Choose a charge category' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.care_extra_categories(line_id,category) VALUES(line,method);PERFORM hf_api.snapshot_invoice_tax(result);PERFORM hf_api.care_event(pid,'Charge recorded',hf_api.required_text(p,'description')||' · INR '||amount,result);
 ELSIF p_action='tax-settings' THEN
 IF NOT hf_security.care_role(ARRAY['Admin']) THEN RAISE EXCEPTION 'Admin configures tax rates' USING ERRCODE='42501';END IF;
 IF NOT(p ?& ARRAY['bedRate','medicineRate','otherRate']) OR EXISTS(SELECT 1 FROM jsonb_each(p) e WHERE e.key IN ('bedRate','medicineRate','otherRate') AND jsonb_typeof(e.value)<>'number') THEN RAISE EXCEPTION 'Enter all three numeric tax rates' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each_text(p) e WHERE e.key IN ('bedRate','medicineRate','otherRate') AND e.value::numeric<>round(e.value::numeric,2)) THEN RAISE EXCEPTION 'Tax rates allow at most two decimal places' USING ERRCODE='23514';END IF;
 IF (p->>'bedRate')::numeric NOT BETWEEN 0 AND 100 OR(p->>'medicineRate')::numeric NOT BETWEEN 0 AND 100 OR(p->>'otherRate')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Rates must be between 0 and 100' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.billing_tax_settings(bed_rate,medicine_rate,other_rate,configured_by) VALUES((p->>'bedRate')::numeric,(p->>'medicineRate')::numeric,(p->>'otherRate')::numeric,actor) RETURNING id::text INTO result;
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
CREATE OR REPLACE FUNCTION hf_api.finance_state() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();result jsonb;item jsonb;enriched jsonb:='[]';tax jsonb;BEGIN
 IF NOT(hf_security.care_role(ARRAY['Admin','Reception','Doctor','Nurse','Billing','Pharmacist']) OR EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor)) THEN RAISE EXCEPTION 'Patient billing access required' USING ERRCODE='42501';END IF;
 result:=jsonb_build_object(
 'invoices',(SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.id),'[]') FROM(SELECT b.id,b.patient_id,p.name patient_name,p.registration_id patient_code,v.total,v.paid,v.balance,
 COALESCE((SELECT sum(amount) FROM hospitalflow.bill_lines WHERE bill_id=b.id AND amount>0),0) gross,
 COALESCE((SELECT -sum(amount) FROM hospitalflow.bill_lines WHERE bill_id=b.id AND amount<0),0) credits,
 COALESCE((SELECT sum(amount) FROM hospitalflow.invoice_discounts WHERE bill_id=b.id),0) discount,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('amount',amount,'reason',reason,'by',u.name,'at',d.created_at)) FROM hospitalflow.invoice_discounts d JOIN hospitalflow.users u ON u.id=d.created_by WHERE d.bill_id=b.id),'[]') discounts,
 COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM(SELECT pay.id,pay.amount,pay.method,pay.at,pp.mode,pp.method portal_method FROM hospitalflow.payments pay LEFT JOIN hospitalflow.portal_payments pp ON pp.payment_id=pay.id WHERE pay.bill_id=b.id ORDER BY pay.at)r),'[]') receipts
 FROM hospitalflow.bills b JOIN hospitalflow.patients p ON p.id=b.patient_id JOIN hospitalflow.invoice_balances v ON v.id=b.id WHERE b.hospital_id=hf_security.current_hospital() AND(hf_security.care_role(ARRAY['Admin','Reception','Billing','Pharmacist']) OR hf_security.can_read_care(b.patient_id)))q),
 'medicines',(SELECT COALESCE(jsonb_agg(to_jsonb(q)),'[]') FROM(SELECT b.patient_id,b.id invoice,m.name medicine,x.quantity,x.unit_price,l.amount,l.created_at,pres.id prescription_id,pres.status FROM hospitalflow.bill_lines l JOIN hospitalflow.bills b ON b.id=l.bill_id JOIN hospitalflow.invoice_line_context x ON x.line_id=l.id JOIN hospitalflow.medicine_batches m ON m.id=x.medicine_id LEFT JOIN hospitalflow.prescription_dispensations d ON d.bill_id=b.id LEFT JOIN hospitalflow.prescriptions pres ON pres.id=d.prescription_id WHERE b.hospital_id=hf_security.current_hospital() AND(hf_security.care_role(ARRAY['Admin','Reception','Billing','Pharmacist']) OR hf_security.can_read_care(b.patient_id)))q),
 'prices',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'batch',m.batch,'price',m.price)),'[]') FROM hospitalflow.medicine_batches m WHERE m.hospital_id=hf_security.current_hospital()),
 'priceHistory',(SELECT COALESCE(jsonb_agg(to_jsonb(q)),'[]') FROM(SELECT ph.*,u.name changed_by FROM hospitalflow.medicine_price_history ph JOIN hospitalflow.users u ON u.id=ph.created_by WHERE ph.hospital_id=hf_security.current_hospital() AND hf_security.care_role(ARRAY['Admin','Reception','Doctor','Nurse','Pharmacist']))q));
 FOR item IN SELECT value FROM jsonb_array_elements(result->'invoices') LOOP
 IF hf_security.can_read_invoice(item->>'id') THEN tax:=hf_api.invoice_tax_detail(item->>'id');enriched:=enriched||jsonb_build_array(item||jsonb_build_object('base',tax->'base','gst',tax->'gst','grand_total',tax->'grand_total','lines',tax->'lines','read_only',NOT(hf_security.billing_staff() OR hf_security.billing_pharmacy_only())));END IF;
 END LOOP;
 RETURN result||jsonb_build_object('invoices',enriched,'taxSettings',(SELECT to_jsonb(s) FROM hospitalflow.billing_tax_settings s WHERE s.hospital_id=hf_security.current_hospital() ORDER BY s.created_at DESC,id DESC LIMIT 1),'hospital',(SELECT jsonb_build_object('id',id,'name',name,'address',address,'city',city) FROM hospitalflow.hospitals WHERE id=hf_security.current_hospital()));
END $$;

CREATE FUNCTION hf_api.billing_receipt(p_bill text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$ DECLARE state jsonb;item jsonb;BEGIN
 state:=hf_api.finance_state();SELECT value INTO item FROM jsonb_array_elements(state->'invoices') WHERE value->>'id'=p_bill;
 IF item IS NULL THEN RETURN NULL;END IF;RETURN item||jsonb_build_object('hospital',state->'hospital');END $$;
REVOKE ALL ON FUNCTION hf_security.billing_staff(),hf_security.billing_pharmacy_only(),hf_security.medicine_invoice(text),hf_security.can_read_invoice(text),hf_security.guard_billing_discount(),hf_api.snapshot_invoice_tax(text),hf_api.invoice_tax_detail(text),hf_api.billing_receipt(text) FROM PUBLIC;
CREATE FUNCTION hf_security.capture_invoice_tax() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$ DECLARE original_hospital text:=hf_security.current_hospital();original_actor text:=hf_security.actor_id();target text;BEGIN
 IF NEW.amount<=0 THEN RETURN NEW;END IF;
 SELECT hospital_id INTO target FROM hospitalflow.bills WHERE id=NEW.bill_id;
 PERFORM set_config('hospitalflow.hospital_id',target,true);PERFORM set_config('hospitalflow.actor_id','',true);PERFORM hf_api.snapshot_invoice_tax(NEW.bill_id);PERFORM set_config('hospitalflow.actor_id',COALESCE(original_actor,''),true);PERFORM set_config('hospitalflow.hospital_id',original_hospital,true);RETURN NEW;
END $$;
CREATE CONSTRAINT TRIGGER capture_inclusive_tax AFTER INSERT ON hospitalflow.bill_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION hf_security.capture_invoice_tax();
REVOKE ALL ON FUNCTION hf_security.capture_invoice_tax() FROM PUBLIC;

-- Preserve clinical workflow while restricting the legacy manual charge action.
CREATE OR REPLACE FUNCTION hf_api.care_command(p_action text,p jsonb,p_key uuid,p_hash text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,hf_security,pg_temp AS $$
DECLARE actor text;pid text;result text;old hospitalflow.care_command_keys%ROWTYPE;plan hospitalflow.care_plans%ROWTYPE;adm hospitalflow.admissions%ROWTYPE;dose_row hospitalflow.medication_doses%ROWTYPE;review hospitalflow.care_discharge_reviews%ROWTYPE;rx hospitalflow.prescriptions%ROWTYPE;number integer;quantity integer;actual timestamptz;note text;item jsonb;payload jsonb;approval uuid;bill text;kind text;BEGIN
 actor:=hf_api.booking_actor();PERFORM pg_advisory_xact_lock(74192301);
 IF p_key IS NULL OR p_hash!~'^[A-Fa-f0-9]{64}$' OR jsonb_typeof(p)<>'object' THEN RAISE EXCEPTION 'A valid retry key and object are required' USING ERRCODE='23514';END IF;
 SELECT * INTO old FROM hospitalflow.care_command_keys WHERE actor_id=actor AND key=p_key;IF FOUND THEN IF old.action<>p_action OR old.request_hash<>p_hash THEN RAISE EXCEPTION 'Retry key already used for another change' USING ERRCODE='23514';END IF;RETURN old.reference;END IF;
 note:=COALESCE(NULLIF(btrim(p->>'comments'),''),NULLIF(btrim(p->>'notes'),''));
 IF p_action='rate' THEN
 IF NOT hf_security.care_role(ARRAY['Admin']) THEN RAISE EXCEPTION 'Admin configures hospital rates' USING ERRCODE='42501';END IF;
 IF (p->>'effectiveFrom')::date<date '1900-01-01' THEN RAISE EXCEPTION 'Enter a valid rate effective date' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each_text(p) v WHERE v.key IN ('bedDaily','wardDaily','icuDaily','nursingDaily') AND ((v.value::numeric)<0 OR v.value::numeric>10000000 OR v.value::numeric<>round(v.value::numeric,2))) THEN RAISE EXCEPTION 'Rates require nonnegative amounts with at most two decimals' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.care_rates(ward,effective_from,bed_daily,ward_daily,icu_daily,nursing_daily,configured_by) VALUES(hf_api.required_text(p,'ward'),(p->>'effectiveFrom')::date,(p->>'bedDaily')::numeric,(p->>'wardDaily')::numeric,(p->>'icuDaily')::numeric,(p->>'nursingDaily')::numeric,actor) RETURNING id::text INTO result;
 ELSIF p_action='admission-request' THEN
 pid:=hf_api.required_text(p,'patientId');IF NOT hf_security.care_role(ARRAY['Doctor']) OR NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'A treating Doctor must request admission' USING ERRCODE='42501';END IF;
 IF p->>'nurseId' IS NOT NULL AND p->>'nurseId'<>'' AND NOT EXISTS(SELECT 1 FROM hospitalflow.users u JOIN hospitalflow.hospital_memberships m ON m.user_id=u.id WHERE u.id=p->>'nurseId' AND u.role IN ('Nurse','Developer') AND u.active AND m.hospital_id=hf_security.current_hospital() AND m.active) THEN RAISE EXCEPTION 'Choose a Nurse assigned to this hospital' USING ERRCODE='23514';END IF;
 IF NULLIF(p->>'admissionId','') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hospitalflow.admissions WHERE id=p->>'admissionId' AND patient_id=pid AND hospital_id=hf_security.current_hospital() AND status='Admitted') THEN RAISE EXCEPTION 'Choose this patient active admission' USING ERRCODE='23514';END IF;
 IF NULLIF(p->>'appointmentId','') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hospitalflow.appointments WHERE id=p->>'appointmentId' AND patient_id=pid AND hospital_id=hf_security.current_hospital()) THEN RAISE EXCEPTION 'Appointment must belong to this patient and hospital' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.care_plans(patient_id,doctor_id,nurse_id,appointment_id,admission_id,requested_ward,planned_days,diagnosis,instructions,status) VALUES(pid,actor,NULLIF(p->>'nurseId',''),NULLIF(p->>'appointmentId',''),NULLIF(p->>'admissionId',''),NULLIF(p->>'ward',''),(p->>'days')::integer,hf_api.required_text(p,'diagnosis',2000),hf_api.required_text(p,'instructions',4000),CASE WHEN NULLIF(p->>'admissionId','') IS NOT NULL THEN 'Admitted' ELSE 'Requested' END) RETURNING id::text INTO result;
 INSERT INTO hospitalflow.patient_access_grants(user_id,patient_id,purpose,expires_at,granted_by) SELECT u,pid,'Managed admission care',now()+make_interval(days => COALESCE((p->>'days')::integer,5)+30),actor FROM unnest(ARRAY[actor,NULLIF(p->>'nurseId','')]) u WHERE u IS NOT NULL;
 ELSIF p_action IN ('accept-admission','assign-bed','extend-plan') THEN
 SELECT * INTO STRICT plan FROM hospitalflow.care_plans WHERE id=(p->>'id')::uuid AND hospital_id=hf_security.current_hospital() FOR UPDATE;pid:=plan.patient_id;
 IF p_action='extend-plan' THEN IF NOT hf_security.care_role(ARRAY['Doctor']) OR (plan.doctor_id<>actor AND NOT hf_security.care_role(ARRAY['Developer'])) OR plan.status='Discharged' THEN RAISE EXCEPTION 'Only the treating Doctor can update the treatment plan' USING ERRCODE='42501';END IF;
 UPDATE hospitalflow.care_plans SET planned_days=(p->>'days')::integer,nursing_days=(p->>'days')::integer,instructions=hf_api.required_text(p,'instructions',4000),updated_at=now() WHERE id=plan.id;
 ELSE
 IF NOT hf_security.care_role(ARRAY['Nurse']) OR plan.status='Discharged' OR(plan.nurse_id IS NOT NULL AND plan.nurse_id<>actor AND NOT hf_security.care_role(ARRAY['Developer'])) THEN RAISE EXCEPTION 'Assigned nursing staff are required' USING ERRCODE='42501';END IF;
 UPDATE hospitalflow.care_plans SET nurse_id=actor,status=CASE WHEN admission_id IS NULL THEN 'Accepted' ELSE status END,updated_at=now() WHERE id=plan.id;
 INSERT INTO hospitalflow.patient_access_grants(user_id,patient_id,purpose,expires_at,granted_by) VALUES(actor,pid,'Accepted nursing admission care',now()+make_interval(days => plan.planned_days+30),actor);
 IF p_action='assign-bed' THEN
 IF plan.admission_id IS NOT NULL THEN RAISE EXCEPTION 'Use the bed transfer workflow for an existing admission' USING ERRCODE='23514';END IF;
 IF plan.requested_ward IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hospitalflow.beds WHERE id=p->>'bedId' AND ward=plan.requested_ward AND hospital_id=hf_security.current_hospital()) THEN RAISE EXCEPTION 'Choose an available bed in the requested ward' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.care_plans SET nursing_days=COALESCE((p->>'confirmedDays')::integer,plan.planned_days),nursing_notes=hf_api.required_text(p,'nursingNotes',2000) WHERE id=plan.id;
 result:=hf_api.execute('admit',jsonb_build_object('patientId',pid,'bedId',hf_api.required_text(p,'bedId'),'reason',plan.diagnosis||' · '||plan.instructions),p_key,p_hash);
 UPDATE hospitalflow.care_plans SET admission_id=result,status='Admitted',updated_at=now() WHERE id=plan.id;PERFORM hf_api.accrue_stay_charges(result);
 END IF;END IF;result:=COALESCE(result,plan.id::text);
 ELSIF p_action='monitor' THEN
 SELECT * INTO STRICT adm FROM hospitalflow.admissions WHERE id=p->>'admissionId' AND hospital_id=hf_security.current_hospital() AND status='Admitted';pid:=adm.patient_id;
 IF NOT hf_security.care_role(ARRAY['Nurse']) OR NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'Nursing care access is required' USING ERRCODE='42501';END IF;
 payload:=COALESCE(p->'vitals','{}');IF jsonb_typeof(payload)<>'object' OR length(payload::text)>2000 THEN RAISE EXCEPTION 'Vitals must be an object of recorded measurements' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(payload) j WHERE j.key NOT IN ('temperatureC','systolicBP','diastolicBP','pulseBpm','respirationsPerMin','oxygenSaturationPct') OR jsonb_typeof(j.value)<>'number') THEN RAISE EXCEPTION 'Enter numeric vital measurements using the displayed fields' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.care_observations(admission_id,patient_id,recorded_by,health_status,vitals,progress,notes) VALUES(adm.id,pid,actor,hf_api.required_text(p,'healthStatus',1000),payload,hf_api.required_text(p,'progress',2000),hf_api.required_text(p,'notes',4000)) RETURNING id::text INTO result;
 PERFORM hf_api.accrue_stay_charges(adm.id);
 ELSIF p_action IN ('send-pharmacy','schedule-dose') THEN
 SELECT * INTO STRICT rx FROM hospitalflow.prescriptions WHERE id=p->>'prescriptionId' AND hospital_id=hf_security.current_hospital();pid:=rx.patient_id;
 IF NOT hf_security.can_read_care(pid) OR (p_action='schedule-dose' AND NOT hf_security.care_role(ARRAY['Doctor','Nurse'])) THEN RAISE EXCEPTION 'Care access is required' USING ERRCODE='42501';END IF;
 IF rx.status='Cancelled' THEN RAISE EXCEPTION 'Cancelled prescriptions cannot be used' USING ERRCODE='23514';END IF;
 IF p_action='send-pharmacy' THEN IF rx.status<>'Pending' THEN RAISE EXCEPTION 'This prescription is already fulfilled or cancelled' USING ERRCODE='23514';END IF;IF NOT(hf_security.care_role(ARRAY['Doctor','Nurse']) OR hf_security.own_patient(pid)) THEN RAISE EXCEPTION 'Patient, Doctor or Nurse access required' USING ERRCODE='42501';END IF;
 INSERT INTO hospitalflow.pharmacy_requests(prescription_id,patient_id,requested_by,comments) VALUES(rx.id,pid,actor,hf_api.required_text(p,'comments',1000)) RETURNING id::text INTO result;
 ELSE
 quantity:=(p->>'quantity')::integer;IF quantity<1 OR quantity+COALESCE((SELECT sum(d.quantity) FROM hospitalflow.medication_doses d WHERE d.prescription_id=rx.id AND status='Scheduled'),0)+COALESCE((SELECT sum(a.quantity) FROM hospitalflow.medication_administrations a WHERE a.prescription_id=rx.id),0)>rx.quantity THEN RAISE EXCEPTION 'Dose schedule exceeds the remaining prescribed quantity' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.medication_doses(prescription_id,admission_id,patient_id,dose,quantity,scheduled_at,created_by) VALUES(rx.id,(SELECT id FROM hospitalflow.admissions WHERE patient_id=pid AND hospital_id=hf_security.current_hospital() AND status='Admitted'),pid,hf_api.required_text(p,'dose',200),quantity,(p->>'scheduledAt')::timestamptz,actor) RETURNING id::text INTO result;END IF;
 ELSIF p_action='record-dose' THEN
 SELECT * INTO STRICT dose_row FROM hospitalflow.medication_doses WHERE id=(p->>'id')::uuid AND hospital_id=hf_security.current_hospital() FOR UPDATE;pid:=dose_row.patient_id;
 IF NOT hf_security.care_role(ARRAY['Nurse']) OR NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'Nursing care access required' USING ERRCODE='42501';END IF;
 IF dose_row.status<>'Scheduled' THEN RAISE EXCEPTION 'Dose outcome already recorded; create a new schedule for a later dose' USING ERRCODE='23514';END IF;
 IF p->>'status' NOT IN ('Given','Not given') THEN RAISE EXCEPTION 'Choose Given or Not given' USING ERRCODE='23514';END IF;
 note:=hf_api.required_text(p,'remarks',1000);
 IF p->>'status'='Given' THEN actual:=COALESCE(NULLIF(p->>'actualAt','')::timestamptz,now());IF actual>now() OR actual<(SELECT created_at FROM hospitalflow.prescriptions WHERE id=dose_row.prescription_id) THEN RAISE EXCEPTION 'Actual time must be after prescription creation and cannot be in the future' USING ERRCODE='23514';END IF;
 approval:=hf_api.provide_medication(dose_row.prescription_id,dose_row.quantity,note,p_key);END IF;
 UPDATE hospitalflow.medication_doses SET status=p->>'status',actual_at=actual,recorded_by=actor,recorded_at=now(),remarks=note,administration_id=approval WHERE id=dose_row.id;result:=dose_row.id::text;
 ELSIF p_action IN ('prepare-discharge','approve-discharge','finalize-discharge','accrue-charges') THEN
 SELECT * INTO STRICT adm FROM hospitalflow.admissions WHERE id=p->>'admissionId' AND hospital_id=hf_security.current_hospital();pid:=adm.patient_id;
 IF NOT hf_security.can_read_care(pid) AND NOT hf_security.care_role(ARRAY['Billing']) THEN RAISE EXCEPTION 'Care access required' USING ERRCODE='42501';END IF;
 IF p_action='accrue-charges' THEN IF NOT hf_security.care_role(ARRAY['Admin','Billing','Doctor','Nurse']) THEN RAISE EXCEPTION 'Staff access required' USING ERRCODE='42501';END IF;result:=hf_api.accrue_stay_charges(adm.id,true);
 ELSE
 IF adm.status<>'Admitted' THEN RAISE EXCEPTION 'Patient is already discharged' USING ERRCODE='23514';END IF;
 SELECT * INTO review FROM hospitalflow.care_discharge_reviews WHERE admission_id=adm.id FOR UPDATE;
 IF p_action='prepare-discharge' THEN
 IF NOT hf_security.care_role(ARRAY['Nurse']) THEN RAISE EXCEPTION 'Nurse prepares discharge' USING ERRCODE='42501';END IF;
 IF review.approved_at IS NOT NULL THEN RAISE EXCEPTION 'Doctor has approved this summary; it is no longer editable' USING ERRCODE='23514';END IF;
 INSERT INTO hospitalflow.care_discharge_reviews(admission_id,patient_id,nurse_id,final_condition,nurse_remarks) VALUES(adm.id,pid,actor,hf_api.required_text(p,'finalCondition',2000),hf_api.required_text(p,'nurseRemarks',2000)) ON CONFLICT(admission_id) DO UPDATE SET nurse_id=actor,final_condition=EXCLUDED.final_condition,nurse_remarks=EXCLUDED.nurse_remarks,prepared_at=now();
 ELSIF p_action='approve-discharge' THEN
 IF NOT hf_security.care_role(ARRAY['Doctor']) OR review.admission_id IS NULL OR review.approved_at IS NOT NULL THEN RAISE EXCEPTION 'A treating Doctor must review the nursing discharge preparation' USING ERRCODE='42501';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.care_plans WHERE admission_id=adm.id AND doctor_id<>actor) AND NOT hf_security.care_role(ARRAY['Developer']) THEN RAISE EXCEPTION 'Only the treating Doctor can approve discharge' USING ERRCODE='42501';END IF;
 UPDATE hospitalflow.care_discharge_reviews SET doctor_id=actor,approved_at=now(),diagnosis=hf_api.required_text(p,'diagnosis',2000),treatment=hf_api.required_text(p,'treatment',4000),discharge_medications=hf_api.required_text(p,'dischargeMedications',4000),follow_up=hf_api.required_text(p,'followUp',4000),doctor_remarks=hf_api.required_text(p,'doctorRemarks',2000) WHERE admission_id=adm.id;
 ELSE
 IF NOT hf_security.care_role(ARRAY['Nurse']) OR review.approved_at IS NULL THEN RAISE EXCEPTION 'Doctor approval is required before Nurse finalization' USING ERRCODE='42501';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.medication_doses WHERE admission_id=adm.id AND status='Scheduled') THEN RAISE EXCEPTION 'Record Given or Not given outcomes for remaining inpatient scheduled doses' USING ERRCODE='23514';END IF;
 PERFORM hf_api.accrue_stay_charges(adm.id,true);
 PERFORM set_config('hospitalflow.care_finalization',adm.id,true);
 CALL hf_api.discharge_patient(adm.id,review.diagnosis||E'\nTreatment: '||review.treatment||E'\nDischarge medicines: '||review.discharge_medications||E'\nFollow-up: '||review.follow_up||E'\nDoctor: '||review.doctor_remarks||E'\nNurse: '||review.final_condition||' · '||review.nurse_remarks);
 UPDATE hospitalflow.care_discharge_reviews SET completed_by=actor,completed_at=now() WHERE admission_id=adm.id;UPDATE hospitalflow.care_plans SET status='Discharged',updated_at=now() WHERE admission_id=adm.id;
 END IF;result:=adm.id;END IF;
 ELSIF p_action='complete-lab' THEN
 SELECT e.patient_id INTO STRICT pid FROM hospitalflow.clinical_orders o JOIN hospitalflow.encounters e ON e.id=o.encounter_id WHERE o.id=(p->>'id')::uuid AND o.hospital_id=hf_security.current_hospital();
 IF NOT hf_security.care_role(ARRAY['Doctor','Nurse']) OR NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'Clinical care access required' USING ERRCODE='42501';END IF;
 result:=hf_api.execute('complete-clinical-order',p,p_key,p_hash);
 ELSIF p_action='lab-order' THEN
 IF NOT hf_security.care_role(ARRAY['Doctor']) THEN RAISE EXCEPTION 'A Doctor recommends laboratory tests' USING ERRCODE='42501';END IF;
 SELECT patient_id INTO STRICT pid FROM hospitalflow.encounters WHERE id=(p->>'encounterId')::uuid AND hospital_id=hf_security.current_hospital();
 IF NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'Patient care access required' USING ERRCODE='42501';END IF;
 result:=hf_api.execute('clinical-order',p,p_key,p_hash);INSERT INTO hospitalflow.care_managed_orders(order_id,patient_id) VALUES(result::uuid,pid);
 ELSIF p_action='cancel-prescription' THEN
 SELECT patient_id INTO STRICT pid FROM hospitalflow.prescriptions WHERE id=p->>'id' AND hospital_id=hf_security.current_hospital();
 IF NOT hf_security.care_role(ARRAY['Doctor']) OR NOT hf_security.can_read_care(pid) THEN RAISE EXCEPTION 'Treating Doctor access required' USING ERRCODE='42501';END IF;
 note:=hf_api.required_text(p,'comments',1000);result:=hf_api.execute('cancel-prescription',p,p_key,p_hash);
 ELSIF p_action='extra-charge' THEN
 IF NOT hf_security.billing_staff() THEN RAISE EXCEPTION 'Reception/Admin enter additional charges' USING ERRCODE='42501';END IF;
 pid:=hf_api.required_text(p,'patientId');kind:=hf_api.required_text(p,'category');IF kind NOT IN ('Consultation','Laboratory','Nursing','Consumables','Other service') THEN RAISE EXCEPTION 'Choose a charge category' USING ERRCODE='23514';END IF;
 CALL hf_api.create_bill(bill,pid,hf_api.required_text(p,'description',500),(p->>'amount')::numeric);
 INSERT INTO hospitalflow.care_extra_categories(line_id,category) SELECT id,kind FROM hospitalflow.bill_lines WHERE bill_id=bill;result:=bill;
 ELSIF p_action='prescription-set' THEN
 IF NOT hf_security.care_role(ARRAY['Doctor']) OR jsonb_typeof(p->'items')<>'array' OR jsonb_array_length(p->'items') NOT BETWEEN 1 AND 30 THEN RAISE EXCEPTION 'A Doctor can enter 1–30 prescription medicines' USING ERRCODE='23514';END IF;
 number:=0;FOR item IN SELECT * FROM jsonb_array_elements(p->'items') LOOP number:=number+1;result:=hf_api.prescribe_visit(hf_api.required_text(p,'appointmentId'),item,md5(p_key::text||number)::uuid,p_hash);END LOOP;
 SELECT patient_id INTO pid FROM hospitalflow.appointments WHERE id=p->>'appointmentId';
 ELSE RAISE EXCEPTION 'Unknown care action' USING ERRCODE='23514';END IF;
 IF pid IS NOT NULL THEN PERFORM hf_api.care_event(pid,replace(initcap(replace(p_action,'-',' ')),'  ',' '),COALESCE(NULLIF(concat_ws(' · ',note,p->>'instructions',p->>'diagnosis',p->>'healthStatus',p->>'progress',p->>'remarks',p->>'nursingNotes',p->>'dose',p->>'finalCondition',p->>'nurseRemarks',p->>'doctorRemarks'),''),'Record saved'),COALESCE(result,''),p-ARRAY['password']);END IF;
 PERFORM hf_security.audit('care:'||p_action,COALESCE(result,''));INSERT INTO hospitalflow.care_command_keys VALUES(actor,p_key,p_action,p_hash,COALESCE(result,''));RETURN COALESCE(result,'');
END $$;
