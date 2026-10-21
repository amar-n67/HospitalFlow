-- Hospital-scoped tariff versions, transparent invoice settlement, annual calendars and releases.
ALTER TABLE hospitalflow.care_rates DROP CONSTRAINT care_rates_hospital_id_ward_effective_from_key;
CREATE INDEX care_rates_lookup ON hospitalflow.care_rates(hospital_id,ward,effective_from DESC,created_at DESC,id DESC);
CREATE TABLE hospitalflow.invoice_discounts(line_id text PRIMARY KEY REFERENCES hospitalflow.bill_lines(id),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),bill_id text NOT NULL REFERENCES hospitalflow.bills(id),amount numeric(14,2) NOT NULL CHECK(amount>0),reason text NOT NULL CHECK(length(reason) BETWEEN 1 AND 500),created_by text NOT NULL REFERENCES hospitalflow.users(id),created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.portal_payments(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),bill_id text NOT NULL REFERENCES hospitalflow.bills(id),payment_id text NOT NULL UNIQUE REFERENCES hospitalflow.payments(id),patient_id text NOT NULL REFERENCES hospitalflow.patients(id),amount numeric(14,2) NOT NULL CHECK(amount>0),method text NOT NULL CHECK(method IN ('UPI','Netbanking','Card','QR')),mode text NOT NULL CHECK(mode='Test'),paid_by text NOT NULL REFERENCES hospitalflow.users(id),created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.medicine_price_history(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),medicine_id text NOT NULL REFERENCES hospitalflow.medicine_batches(id),old_price numeric(14,2) NOT NULL,new_price numeric(14,2) NOT NULL CHECK(new_price>0),reason text NOT NULL,created_by text NOT NULL REFERENCES hospitalflow.users(id),created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE hospitalflow.hospital_holidays(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),hospital_id text NOT NULL DEFAULT hf_security.current_hospital() REFERENCES hospitalflow.hospitals(id),name text NOT NULL CHECK(length(name) BETWEEN 1 AND 150),on_date date,annual_month integer,annual_day integer,kind text NOT NULL CHECK(kind IN ('National','Festival','Regional','Hospital')),is_leave boolean NOT NULL DEFAULT false,active boolean NOT NULL DEFAULT true,notes text NOT NULL DEFAULT '',source text NOT NULL DEFAULT '',updated_by text REFERENCES hospitalflow.users(id),updated_at timestamptz NOT NULL DEFAULT now(),CHECK((on_date IS NOT NULL AND annual_month IS NULL AND annual_day IS NULL) OR(on_date IS NULL AND annual_month BETWEEN 1 AND 12 AND annual_day BETWEEN 1 AND extract(day FROM (make_date(2000,annual_month,1)+interval '1 month - 1 day')))));
CREATE TABLE hospitalflow.application_releases(version text PRIMARY KEY CHECK(version~'^[0-9]+\.[0-9]\.[0-9]$'),released_at timestamptz NOT NULL,source_parent text NOT NULL,notes text NOT NULL,installed_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE hospitalflow.application_releases ENABLE ROW LEVEL SECURITY;
CREATE POLICY release_admin_read ON hospitalflow.application_releases FOR SELECT USING(hf_security.care_role(ARRAY['Admin']));
CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.application_releases FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes();
-- National fixed-date entries repeat each year; no regional closure is assumed.
INSERT INTO hospitalflow.hospital_holidays(hospital_id,name,annual_month,annual_day,kind,is_leave,source)
SELECT h.id,v.name,v.month,v.day,'National',true,'India national fixed-date observance' FROM hospitalflow.hospitals h CROSS JOIN(VALUES('Republic Day',1,26),('Independence Day',8,15),('Gandhi Jayanti',10,2))v(name,month,day);
INSERT INTO hospitalflow.hospital_holidays(hospital_id,name,on_date,kind,is_leave,source)
SELECT h.id,v.name,v.day::date,'Festival',false,'https://dfe.gov.in/uploads/documents/list-of-gazetted-holidays-2026.pdf — central government reference; hospital policy requires Admin confirmation' FROM hospitalflow.hospitals h CROSS JOIN(VALUES
('Holi','2026-03-04'),('Id-ul-Fitr','2026-03-21'),('Ram Navami','2026-03-26'),('Mahavir Jayanti','2026-03-31'),('Good Friday','2026-04-03'),('Buddha Purnima','2026-05-01'),('Id-ul-Zuha (Bakrid)','2026-05-27'),('Muharram','2026-06-26'),('Milad-un-Nabi','2026-08-26'),('Janmashtami','2026-09-04'),('Dussehra','2026-10-20'),('Diwali','2026-11-08'),('Guru Nanak Jayanti','2026-11-24'),('Christmas','2026-12-25'))v(name,day);
DO $$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['invoice_discounts','portal_payments','medicine_price_history','hospital_holidays'] LOOP
 EXECUTE format('ALTER TABLE hospitalflow.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('CREATE POLICY hospital_read ON hospitalflow.%I FOR SELECT USING(hospital_id=hf_security.current_hospital() AND hf_security.care_role(ARRAY[''Admin'']))',t);
 EXECUTE format('CREATE TRIGGER z_hospital_guard BEFORE INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hf_security.guard_hospital_row()',t);
 EXECUTE format('CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history()',t);
 IF t<>'hospital_holidays' THEN EXECUTE format('CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes()',t);END IF;
END LOOP;END $$;
CREATE FUNCTION hf_api.finance_state() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();BEGIN
 IF NOT(hf_security.care_role(ARRAY['Admin','Doctor','Nurse','Billing','Pharmacist']) OR EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor)) THEN RAISE EXCEPTION 'Patient billing access required' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object(
 'invoices',(SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.id),'[]') FROM(SELECT b.id,b.patient_id,p.name patient_name,p.registration_id patient_code,v.total,v.paid,v.balance,
 COALESCE((SELECT sum(amount) FROM hospitalflow.bill_lines WHERE bill_id=b.id AND amount>0),0) gross,
 COALESCE((SELECT -sum(amount) FROM hospitalflow.bill_lines WHERE bill_id=b.id AND amount<0),0) credits,
 COALESCE((SELECT sum(amount) FROM hospitalflow.invoice_discounts WHERE bill_id=b.id),0) discount,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('amount',amount,'reason',reason,'by',u.name,'at',d.created_at)) FROM hospitalflow.invoice_discounts d JOIN hospitalflow.users u ON u.id=d.created_by WHERE d.bill_id=b.id),'[]') discounts,
 COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM(SELECT pay.id,pay.amount,pay.method,pay.at,pp.mode,pp.method portal_method FROM hospitalflow.payments pay LEFT JOIN hospitalflow.portal_payments pp ON pp.payment_id=pay.id WHERE pay.bill_id=b.id ORDER BY pay.at)r),'[]') receipts
 FROM hospitalflow.bills b JOIN hospitalflow.patients p ON p.id=b.patient_id JOIN hospitalflow.invoice_balances v ON v.id=b.id WHERE b.hospital_id=hf_security.current_hospital() AND(hf_security.care_role(ARRAY['Admin','Billing','Pharmacist']) OR hf_security.can_read_care(b.patient_id)))q),
 'medicines',(SELECT COALESCE(jsonb_agg(to_jsonb(q)),'[]') FROM(SELECT b.patient_id,b.id invoice,m.name medicine,x.quantity,x.unit_price,l.amount,l.created_at,pres.id prescription_id,pres.status FROM hospitalflow.bill_lines l JOIN hospitalflow.bills b ON b.id=l.bill_id JOIN hospitalflow.invoice_line_context x ON x.line_id=l.id JOIN hospitalflow.medicine_batches m ON m.id=x.medicine_id LEFT JOIN hospitalflow.prescription_dispensations d ON d.bill_id=b.id LEFT JOIN hospitalflow.prescriptions pres ON pres.id=d.prescription_id WHERE b.hospital_id=hf_security.current_hospital() AND(hf_security.care_role(ARRAY['Admin','Billing','Pharmacist']) OR hf_security.can_read_care(b.patient_id)))q),
 'prices',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'batch',m.batch,'price',m.price)),'[]') FROM hospitalflow.medicine_batches m WHERE m.hospital_id=hf_security.current_hospital()),
 'priceHistory',(SELECT COALESCE(jsonb_agg(to_jsonb(q)),'[]') FROM(SELECT ph.*,u.name changed_by FROM hospitalflow.medicine_price_history ph JOIN hospitalflow.users u ON u.id=ph.created_by WHERE ph.hospital_id=hf_security.current_hospital() AND hf_security.care_role(ARRAY['Admin','Doctor','Nurse','Pharmacist']))q));
END $$;
CREATE FUNCTION hf_api.year_calendar(p_year integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();BEGIN
 IF p_year NOT BETWEEN 1900 AND 9998 THEN RAISE EXCEPTION 'Choose a year from 1900 to 9998' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=actor) THEN RAISE EXCEPTION 'Staff calendar only' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('year',p_year,'hospitalName',(SELECT name FROM hospitalflow.hospitals WHERE id=hf_security.current_hospital()),'holidays',
 (SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.day,q.name),'[]') FROM(SELECT h.*,CASE WHEN h.on_date IS NOT NULL THEN h.on_date ELSE make_date(p_year,h.annual_month,h.annual_day) END AS day FROM hospitalflow.hospital_holidays h WHERE h.hospital_id=hf_security.current_hospital() AND h.active AND(extract(year FROM h.on_date)=p_year OR(h.on_date IS NULL AND(h.annual_month<>2 OR h.annual_day<>29 OR extract(day FROM(make_date(p_year,2,1)+interval '1 month - 1 day'))=29))))q),
 'leaves',(SELECT COALESCE(jsonb_agg(jsonb_build_object('name',u.name,'code',u.registration_id,'startsOn',l.starts_on,'endsOn',l.ends_on,'role',u.role)),'[]') FROM hospitalflow.staff_leaves l JOIN hospitalflow.users u ON u.id=l.user_id JOIN hospitalflow.hospital_memberships m ON m.user_id=u.id AND m.hospital_id=l.hospital_id AND m.active WHERE l.hospital_id=hf_security.current_hospital() AND l.status='Approved' AND l.starts_on<make_date(p_year+1,1,1) AND l.ends_on>=make_date(p_year,1,1) AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id)));
END $$;
CREATE FUNCTION hf_api.record_release(p jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ BEGIN
 IF nullif(hf_security.actor_id(),'') IS NOT NULL OR session_user<>'hospitalflow_app' THEN RAISE EXCEPTION 'Internal release registration only' USING ERRCODE='42501';END IF;
 INSERT INTO hospitalflow.application_releases(version,released_at,source_parent,notes) VALUES(p->>'version',(p->>'releasedAt')::timestamptz,COALESCE(p->>'sourceParent',''),COALESCE(p->>'notes','')) ON CONFLICT(version) DO NOTHING;
END $$;
CREATE FUNCTION hf_api.enterprise_command(p_action text,p jsonb,p_key uuid,p_hash text,p_test boolean) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE actor text:=hf_api.booking_actor();result text;prior hospitalflow.care_command_keys%ROWTYPE;b hospitalflow.bills%ROWTYPE;bal numeric;amount numeric;line text;method text;med hospitalflow.medicine_batches%ROWTYPE;holiday uuid;BEGIN
 IF p_key IS NULL OR p_hash!~'^[A-Fa-f0-9]{64}$' OR jsonb_typeof(p)<>'object' THEN RAISE EXCEPTION 'Valid retry key and details required' USING ERRCODE='23514';END IF;
 PERFORM pg_advisory_xact_lock(74192301);
 SELECT * INTO prior FROM hospitalflow.care_command_keys WHERE actor_id=actor AND key=p_key;
 IF FOUND THEN IF prior.action<>'enterprise:'||p_action OR prior.request_hash<>p_hash THEN RAISE EXCEPTION 'Retry key belongs to different details' USING ERRCODE='23514';END IF;RETURN prior.reference;END IF;
 IF p_action IN ('discount','portal-pay') THEN
 SELECT * INTO b FROM hospitalflow.bills WHERE id=hf_api.required_text(p,'invoiceId') AND hospital_id=hf_security.current_hospital() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Invoice unavailable' USING ERRCODE='23514';END IF;
 IF p_action='discount' THEN
 IF NOT hf_security.care_role(ARRAY['Admin','Billing']) THEN RAISE EXCEPTION 'Hospital Admin or Billing approval required' USING ERRCODE='42501';END IF;
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
REVOKE ALL ON FUNCTION hf_api.finance_state(),hf_api.year_calendar(integer),hf_api.record_release(jsonb),hf_api.enterprise_command(text,jsonb,uuid,text,boolean) FROM PUBLIC;
CREATE OR REPLACE FUNCTION hf_api.accrue_stay_charges(p_admission text,p_strict boolean DEFAULT false) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE a hospitalflow.admissions%ROWTYPE;r hospitalflow.care_rates%ROWTYPE;assignment record;day date;last_day date;invoice text;line text;kind text;amount numeric;original_actor text:=hf_security.actor_id();BEGIN
 IF nullif(hf_security.actor_id(),'') IS NOT NULL AND NOT hf_security.care_role(ARRAY['Admin','Billing','Doctor','Nurse']) THEN RAISE EXCEPTION 'Care billing staff required' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(74192301);SELECT * INTO STRICT a FROM hospitalflow.admissions WHERE id=p_admission AND hospital_id=hf_security.current_hospital();
 IF nullif(original_actor,'') IS NOT NULL AND NOT hf_security.can_read_care(a.patient_id) AND NOT hf_security.care_role(ARRAY['Admin','Billing']) THEN RAISE EXCEPTION 'Patient care access required for charge calculation' USING ERRCODE='42501';END IF;
 PERFORM set_config('hospitalflow.actor_id','',true);
 SELECT bill_id INTO invoice FROM hospitalflow.care_invoices WHERE admission_id=a.id;
 last_day:=(COALESCE(a.discharged,now()) AT TIME ZONE 'Asia/Kolkata')::date;
 FOR day IN SELECT generate_series((a.at AT TIME ZONE 'Asia/Kolkata')::date,last_day,'1 day')::date LOOP
 SELECT ba.bed_id,b.ward,b.category INTO assignment FROM hospitalflow.bed_assignments ba JOIN hospitalflow.beds b ON b.id=ba.bed_id WHERE ba.admission_id=a.id AND ba.from_time<((day+1)::timestamp AT TIME ZONE 'Asia/Kolkata') AND COALESCE(ba.to_time,now())>=day::timestamp AT TIME ZONE 'Asia/Kolkata' ORDER BY ba.from_time ASC LIMIT 1;
 SELECT * INTO r FROM hospitalflow.care_rates WHERE hospital_id=a.hospital_id AND ward=assignment.ward AND effective_from<=day ORDER BY effective_from DESC,created_at DESC,id DESC LIMIT 1;
 IF NOT FOUND THEN IF p_strict THEN RAISE EXCEPTION 'Configure dated bed/ward/ICU/nursing rates before final billing for %',assignment.ward USING ERRCODE='23514';END IF;CONTINUE;END IF;
 IF invoice IS NULL THEN invoice:=hf_api.new_id('INV');INSERT INTO hospitalflow.bills(id,patient_id) VALUES(invoice,a.patient_id);INSERT INTO hospitalflow.care_invoices(admission_id,bill_id) VALUES(a.id,invoice);END IF;
 FOREACH kind IN ARRAY ARRAY['Bed','Ward','ICU','Nursing'] LOOP
 IF EXISTS(SELECT 1 FROM hospitalflow.care_charge_entries WHERE admission_id=a.id AND charge_day=day AND category=kind) THEN CONTINUE;END IF;
 amount:=CASE kind WHEN 'Bed' THEN r.bed_daily WHEN 'Ward' THEN r.ward_daily WHEN 'ICU' THEN CASE WHEN assignment.category ILIKE '%ICU%' OR assignment.ward ILIKE '%ICU%' THEN r.icu_daily ELSE 0 END ELSE r.nursing_daily END;
 line:=NULL;IF amount>0 THEN line:=hf_api.new_id('LINE');INSERT INTO hospitalflow.bill_lines(id,bill_id,description,amount) VALUES(line,invoice,kind||' · '||assignment.ward||' · '||day,amount);END IF;
 INSERT INTO hospitalflow.care_charge_entries(admission_id,patient_id,charge_day,category,amount,rate_id,bed_id,line_id) VALUES(a.id,a.patient_id,day,kind,amount,r.id,assignment.bed_id,line);
 PERFORM hf_api.care_event(a.patient_id,'Daily charge',kind||' · '||day||' · INR '||amount,COALESCE(line,a.id||':'||day||':'||kind),jsonb_build_object('category',kind,'amount',amount,'day',day,'invoice',invoice));
 END LOOP;END LOOP;PERFORM set_config('hospitalflow.actor_id',COALESCE(original_actor,''),true);RETURN invoice;
END $$;

CREATE OR REPLACE FUNCTION hf_api.accrue_due_care_charges() RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$ DECLARE a record;n integer:=0;original_hospital text:=hf_security.current_hospital();BEGIN
 IF nullif(current_setting('hospitalflow.actor_id',true),'') IS NOT NULL OR session_user NOT IN ('hospitalflow_app','hospitalflow_jobs') THEN RAISE EXCEPTION 'Internal accrual worker only' USING ERRCODE='42501';END IF;
 FOR a IN SELECT id,hospital_id FROM hospitalflow.admissions WHERE status='Admitted' LOOP
 PERFORM set_config('hospitalflow.hospital_id',a.hospital_id,true);PERFORM hf_api.accrue_stay_charges(a.id);n:=n+1;END LOOP;
 PERFORM set_config('hospitalflow.hospital_id',original_hospital,true);RETURN n;
END $$;
