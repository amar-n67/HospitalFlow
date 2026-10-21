CREATE OR REPLACE VIEW hospitalflow.invoice_balances AS
 SELECT b.id,b.patient_id,COALESCE(l.total,0)::numeric(14,2) total,
 (COALESCE(p.paid,0)-COALESCE(r.reversed,0))::numeric(14,2) paid,
 (COALESCE(l.total,0)-COALESCE(p.paid,0)+COALESCE(r.reversed,0))::numeric(14,2) balance
 FROM hospitalflow.bills b LEFT JOIN(SELECT bill_id,sum(amount) total FROM hospitalflow.bill_lines GROUP BY bill_id)l ON l.bill_id=b.id
 LEFT JOIN(SELECT bill_id,sum(amount) paid FROM hospitalflow.payments GROUP BY bill_id)p ON p.bill_id=b.id
 LEFT JOIN(SELECT p.bill_id,sum(r.amount) reversed FROM hospitalflow.payment_reversals r JOIN hospitalflow.payments p ON p.id=r.payment_id GROUP BY p.bill_id)r ON r.bill_id=b.id;
CREATE OR REPLACE FUNCTION hospitalflow.validate_stock_balance() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE v_id text;BEGIN IF TG_TABLE_NAME='medicine_batches' THEN v_id:=NEW.id;ELSE v_id:=NEW.medicine_id;END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.medicine_batches m WHERE m.id=v_id AND(m.quantity<>(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_movements WHERE medicine_id=m.id) OR m.quantity<(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_reservations WHERE medicine_id=m.id AND status='Active'))) THEN RAISE EXCEPTION 'Stock and reservation ledgers disagree' USING ERRCODE='23514';END IF;RETURN NULL;END $$;
CREATE CONSTRAINT TRIGGER reservation_stock_balance AFTER INSERT OR UPDATE ON hospitalflow.stock_reservations DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_stock_balance();
CREATE OR REPLACE FUNCTION hospitalflow.validate_occupancy() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE ids text[];BEGIN
 IF TG_TABLE_NAME='beds' THEN ids:=ARRAY[NEW.id];ELSIF TG_OP='INSERT' THEN ids:=ARRAY[NEW.bed_id];ELSE ids:=ARRAY[NEW.bed_id,OLD.bed_id];END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.beds b WHERE b.id=ANY(ids) AND((b.status='Occupied') IS DISTINCT FROM EXISTS(SELECT 1 FROM hospitalflow.admissions a WHERE a.bed_id=b.id AND a.status='Admitted'))) THEN RAISE EXCEPTION 'Bed status and active admission disagree' USING ERRCODE='23514';END IF;RETURN NULL;END $$;
CREATE FUNCTION hospitalflow.validate_payment_reversal() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);IF(SELECT sum(amount) FROM hospitalflow.payment_reversals WHERE payment_id=NEW.payment_id)>(SELECT amount FROM hospitalflow.payments WHERE id=NEW.payment_id) THEN RAISE EXCEPTION 'Reversal exceeds original payment' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE CONSTRAINT TRIGGER payment_reversal_limit AFTER INSERT ON hospitalflow.payment_reversals DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_payment_reversal();
CREATE FUNCTION hospitalflow.validate_appointment_schedule() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE d hospitalflow.doctors%ROWTYPE;local_at timestamp;tz text;BEGIN
 IF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status AND NOT((OLD.status='Scheduled' AND NEW.status IN ('Checked in','Cancelled','No show')) OR(OLD.status='Checked in' AND NEW.status IN ('In consultation','Cancelled')) OR(OLD.status='In consultation' AND NEW.status='Completed')) THEN RAISE EXCEPTION 'Invalid appointment status transition' USING ERRCODE='23514';END IF;
 IF TG_OP='UPDATE' AND OLD.status<>'Scheduled' AND(NEW.patient_id IS DISTINCT FROM OLD.patient_id OR NEW.doctor_id IS DISTINCT FROM OLD.doctor_id OR NEW.at IS DISTINCT FROM OLD.at) THEN RAISE EXCEPTION 'An active visit cannot be rescheduled' USING ERRCODE='23514';END IF;
 IF NEW.status IN ('Cancelled','No show','Completed') THEN RETURN NEW;END IF;
 SELECT * INTO STRICT d FROM hospitalflow.doctors WHERE id=NEW.doctor_id AND active;
 SELECT value INTO tz FROM hospitalflow.system_settings WHERE key='hospital_timezone';local_at:=NEW.at AT TIME ZONE tz;
 IF local_at::time<d.start OR local_at::time+interval '30 minutes'>d."end" OR extract(minute FROM local_at)::integer%30<>0 OR extract(second FROM local_at)<>0 OR EXISTS(SELECT 1 FROM hospitalflow.provider_absences WHERE doctor_id=d.id AND cancelled_at IS NULL AND starts_at<NEW.at+interval '30 minutes' AND ends_at>NEW.at) OR(EXISTS(SELECT 1 FROM hospitalflow.provider_sessions ps WHERE ps.doctor_id=d.id AND (ps.starts_at AT TIME ZONE tz)::date=local_at::date) AND NOT EXISTS(SELECT 1 FROM hospitalflow.provider_sessions ps WHERE ps.doctor_id=d.id AND ps.starts_at<=NEW.at AND ps.ends_at>=NEW.at+interval '30 minutes')) THEN RAISE EXCEPTION 'Appointment conflicts with shift, slot boundary or approved absence' USING ERRCODE='23514';END IF;
 RETURN NEW;END $$;
CREATE TRIGGER appointment_schedule BEFORE INSERT OR UPDATE ON hospitalflow.appointments FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_appointment_schedule();
CREATE FUNCTION hospitalflow.validate_patient_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);IF NEW.dob>hf_api.hospital_today() OR NEW.phone!~'^\+?[0-9 ()-]{7,20}$' THEN RAISE EXCEPTION 'Invalid patient birth date or contact number' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.patients WHERE id<>NEW.id AND dob=NEW.dob AND(lower(name)=lower(NEW.name) OR phone=NEW.phone)) THEN RAISE EXCEPTION 'Possible duplicate patient identity' USING ERRCODE='23505';END IF;RETURN NEW;END $$;
CREATE TRIGGER patient_identity BEFORE INSERT OR UPDATE ON hospitalflow.patients FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_patient_identity();
CREATE FUNCTION hospitalflow.validate_service_price() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);
 IF TG_OP='UPDATE' AND(NEW.service_id<>OLD.service_id OR NEW.amount<>OLD.amount OR NEW.currency<>OLD.currency OR NEW.effective_from<>OLD.effective_from) THEN RAISE EXCEPTION 'Post a new effective-dated price instead of changing history' USING ERRCODE='23514';END IF;
 IF EXISTS(SELECT 1 FROM hospitalflow.service_prices WHERE id<>NEW.id AND service_id=NEW.service_id AND effective_from<COALESCE(NEW.effective_to,'infinity'::timestamptz) AND COALESCE(effective_to,'infinity'::timestamptz)>NEW.effective_from) THEN RAISE EXCEPTION 'Service price periods overlap' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER price_effectivity BEFORE INSERT OR UPDATE ON hospitalflow.service_prices FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_service_price();
CREATE FUNCTION hospitalflow.validate_dispense_trace() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF NEW.status='Dispensed' AND(TG_OP='INSERT' OR OLD.status<>'Dispensed') AND NOT EXISTS(SELECT 1 FROM hospitalflow.prescription_dispensations d JOIN hospitalflow.stock_movements m ON m.id=d.movement_id JOIN hospitalflow.bills b ON b.id=d.bill_id WHERE d.prescription_id=NEW.id AND m.medicine_id=NEW.medicine_id AND m.quantity=-NEW.quantity AND b.patient_id=NEW.patient_id) THEN RAISE EXCEPTION 'Dispense requires linked stock movement and patient invoice' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE CONSTRAINT TRIGGER dispense_trace AFTER INSERT OR UPDATE ON hospitalflow.prescriptions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION hospitalflow.validate_dispense_trace();
CREATE OR REPLACE FUNCTION hospitalflow.validate_discharge_readiness() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF NEW.status='Discharged' AND(TG_OP='INSERT' OR OLD.status<>'Discharged') AND(EXISTS(SELECT 1 FROM hospitalflow.invoice_balances WHERE patient_id=NEW.patient_id AND balance>0) OR EXISTS(SELECT 1 FROM hospitalflow.prescriptions WHERE patient_id=NEW.patient_id AND status='Pending') OR EXISTS(SELECT 1 FROM hospitalflow.discharge_tasks WHERE admission_id=NEW.id AND required AND completed_at IS NULL)) THEN RAISE EXCEPTION 'Discharge prerequisites are incomplete' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE FUNCTION hospitalflow.sync_encounter() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF TG_TABLE_NAME='appointments' THEN
 INSERT INTO hospitalflow.encounters(patient_id,kind,appointment_id,opened_at,closed_at,status) VALUES(NEW.patient_id,'Outpatient',NEW.id,NEW.at,CASE WHEN NEW.status IN ('Completed','Cancelled','No show') THEN greatest(NEW.at,now()) END,CASE WHEN NEW.status='Completed' THEN 'Completed' WHEN NEW.status IN ('Cancelled','No show') THEN 'Cancelled' ELSE 'Open' END)
 ON CONFLICT(appointment_id) DO UPDATE SET patient_id=EXCLUDED.patient_id,closed_at=EXCLUDED.closed_at,status=EXCLUDED.status;
 ELSE INSERT INTO hospitalflow.encounters(patient_id,kind,admission_id,opened_at,closed_at,status) VALUES(NEW.patient_id,'Inpatient',NEW.id,NEW.at,NEW.discharged,CASE WHEN NEW.status='Discharged' THEN 'Completed' ELSE 'Open' END)
 ON CONFLICT(admission_id) DO UPDATE SET closed_at=EXCLUDED.closed_at,status=EXCLUDED.status;END IF;RETURN NEW;END $$;
CREATE TRIGGER encounter_sync AFTER INSERT OR UPDATE ON hospitalflow.appointments FOR EACH ROW EXECUTE FUNCTION hospitalflow.sync_encounter();
CREATE TRIGGER encounter_sync AFTER INSERT OR UPDATE ON hospitalflow.admissions FOR EACH ROW EXECUTE FUNCTION hospitalflow.sync_encounter();
CREATE OR REPLACE FUNCTION hospitalflow.record_row_history() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE doc jsonb;cols text[];ref text;BEGIN
 doc:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF TG_OP='UPDATE' THEN SELECT array_agg(key ORDER BY key) INTO cols FROM jsonb_each(doc) WHERE value IS DISTINCT FROM to_jsonb(OLD)->key;
 ELSE SELECT array_agg(key ORDER BY key) INTO cols FROM jsonb_each(doc);END IF;
 IF cols IS NULL THEN RETURN NEW;END IF;
 ref:=COALESCE(doc->>'id',doc->>'line_id',doc->>'name',doc->>'key',(doc->>'notification_id')||':'||(doc->>'user_id'),(doc->>'user_id')||':'||(doc->>'department'),'record');
 INSERT INTO hospitalflow.row_history(table_name,record_id,operation,changed_columns,actor_id,correlation_id) VALUES(TG_TABLE_NAME,ref,TG_OP,cols,nullif(current_setting('hospitalflow.actor_id',true),''),nullif(current_setting('hospitalflow.correlation_id',true),''));
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;END $$;
DO $$ DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['departments','wards','system_settings','hospital_profile','staff_members','user_departments','patient_access_grants','patient_contacts','patient_consents','provider_absences','provider_sessions','encounters','service_catalog','service_prices','invoice_line_context','payment_reversals','clinical_orders','discharge_tasks','follow_ups','suppliers','purchase_orders','purchase_order_lines','goods_receipts','goods_receipt_lines','medicine_batch_holds','stock_reservations','prescription_dispensations','notification_acknowledgements','prescription_authors','admission_events'] LOOP
 EXECUTE format('CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history()',t);END LOOP;
 FOREACH t IN ARRAY ARRAY['payment_reversals','invoice_line_context','goods_receipts','goods_receipt_lines','prescription_dispensations','notification_acknowledgements','integration_outbox'] LOOP
 EXECUTE format('CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.prevent_ledger_changes()',t);END LOOP;
END $$;
CREATE FUNCTION hospitalflow.enqueue_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE e uuid;BEGIN IF TG_OP='UPDATE' AND to_jsonb(OLD)=to_jsonb(NEW) THEN RETURN NEW;END IF;
 e:=gen_random_uuid();INSERT INTO hospitalflow.integration_outbox(id,event_type,aggregate_type,aggregate_id,payload) VALUES(e,TG_TABLE_NAME||'.'||lower(TG_OP),TG_TABLE_NAME,NEW.id::text,jsonb_build_object('reference',NEW.id::text));
 INSERT INTO hospitalflow.outbox_delivery(event_id) VALUES(e);RETURN NEW;END $$;
DO $$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['patients','appointments','admissions','prescriptions','payments','payment_reversals','purchase_orders'] LOOP
 EXECUTE format('CREATE TRIGGER enqueue_integration_event AFTER INSERT OR UPDATE ON hospitalflow.%I FOR EACH ROW EXECUTE FUNCTION hospitalflow.enqueue_change()',t);END LOOP;END $$;
ALTER TABLE hospitalflow.integration_outbox ADD CONSTRAINT minimal_outbox_payload CHECK(payload-ARRAY['reference','status','kind']='{}'::jsonb);
CREATE FUNCTION hf_security.can_access_encounter(p_encounter uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$ SELECT EXISTS(SELECT 1 FROM hospitalflow.encounters WHERE id=p_encounter AND hf_security.can_access_patient(patient_id)) $$;
DO $$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['patient_contacts','patient_consents','follow_ups'] LOOP
 EXECUTE format('ALTER TABLE hospitalflow.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('ALTER TABLE hospitalflow.%I FORCE ROW LEVEL SECURITY',t);
 EXECUTE format('CREATE POLICY patient_scope ON hospitalflow.%I USING (hf_security.can_access_patient(patient_id)) WITH CHECK(hf_security.can_access_patient(patient_id))',t);END LOOP;END $$;
ALTER TABLE hospitalflow.clinical_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE hospitalflow.clinical_orders FORCE ROW LEVEL SECURITY;
CREATE POLICY encounter_scope ON hospitalflow.clinical_orders USING(hf_security.can_access_encounter(encounter_id)) WITH CHECK(hf_security.can_access_encounter(encounter_id));
CREATE VIEW hf_reporting.inventory WITH(security_invoker=true) AS
 SELECT m.id,m.name,m.batch,m.expiry,m.quantity AS on_hand,m.reorder,m.price,
 COALESCE(r.reserved,0)::bigint reserved,(m.quantity-COALESCE(r.reserved,0))::bigint available,
 EXISTS(SELECT 1 FROM hospitalflow.medicine_batch_holds h WHERE h.medicine_id=m.id AND h.released_at IS NULL) AS held,
 m.quantity<=m.reorder AS low_stock FROM hospitalflow.medicine_batches m LEFT JOIN(SELECT medicine_id,sum(quantity)reserved FROM hospitalflow.stock_reservations WHERE status='Active' GROUP BY medicine_id)r ON r.medicine_id=m.id OFFSET 0;
CREATE VIEW hf_reporting.stock_ledger WITH(security_invoker=true) AS SELECT m.id,m.medicine_id,b.name,b.batch,m.quantity,m.reason,m.at FROM hospitalflow.stock_movements m JOIN hospitalflow.medicine_batches b ON b.id=m.medicine_id OFFSET 0;
CREATE VIEW hf_reporting.bed_status WITH(security_invoker=true) AS SELECT * FROM hospitalflow.bed_occupancy OFFSET 0;
CREATE VIEW hf_reporting.open_invoices WITH(security_invoker=true) AS SELECT * FROM hospitalflow.invoice_balances WHERE balance>0 OFFSET 0;
CREATE VIEW hf_reporting.purchase_order_progress WITH(security_invoker=true) AS
 SELECT p.id,p.number,p.status,s.name supplier,l.id line_id,l.medicine_id,l.quantity ordered,COALESCE(r.received,0)::bigint received,l.quantity-COALESCE(r.received,0) outstanding
 FROM hospitalflow.purchase_orders p JOIN hospitalflow.suppliers s ON s.id=p.supplier_id JOIN hospitalflow.purchase_order_lines l ON l.purchase_order_id=p.id
 LEFT JOIN(SELECT purchase_order_line_id,sum(quantity) received FROM hospitalflow.goods_receipt_lines GROUP BY purchase_order_line_id)r ON r.purchase_order_line_id=l.id;
CREATE MATERIALIZED VIEW hf_reporting.daily_collections AS
 SELECT "day",sum(amount)::numeric(18,2) AS net_collections FROM(
 SELECT(p.at AT TIME ZONE h.timezone)::date AS "day",p.amount FROM hospitalflow.payments p CROSS JOIN hospitalflow.hospital_profile h
 UNION ALL SELECT(r.at AT TIME ZONE h.timezone)::date,-r.amount FROM hospitalflow.payment_reversals r CROSS JOIN hospitalflow.hospital_profile h)s GROUP BY "day";
CREATE UNIQUE INDEX daily_collections_day_idx ON hf_reporting.daily_collections("day");
CREATE VIEW hf_api.inventory WITH(security_invoker=true) AS SELECT * FROM hf_reporting.inventory OFFSET 0;
COMMENT ON VIEW hf_api.inventory IS 'Read-only synonym equivalent for hf_reporting.inventory. PostgreSQL schemas group APIs in place of Oracle packages.';
CREATE VIEW hf_ops.object_inventory AS
 SELECT n.nspname AS schema_name,CASE c.relkind WHEN 'r' THEN 'TABLE' WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'S' THEN 'SEQUENCE' WHEN 'i' THEN 'INDEX' END AS object_type,c.relname AS object_name
 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops') AND c.relkind IN ('r','v','m','S','i')
 UNION ALL SELECT n.nspname,CASE p.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,p.proname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops')
 UNION ALL SELECT n.nspname,'TRIGGER',c.relname||'.'||t.tgname FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN ('hospitalflow','hf_ops');
CREATE TABLE hf_ops.schema_change_events(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,occurred_at timestamptz NOT NULL DEFAULT now(),database_user text NOT NULL,command_tag text NOT NULL,object_identity text NOT NULL);
CREATE FUNCTION hf_ops.capture_ddl() RETURNS event_trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
DECLARE obj record;BEGIN FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
 IF obj.schema_name IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops') THEN INSERT INTO hf_ops.schema_change_events(database_user,command_tag,object_identity) VALUES(session_user,obj.command_tag,obj.object_identity);END IF;END LOOP;END $$;
CREATE FUNCTION hf_ops.capture_drop() RETURNS event_trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
DECLARE obj record;BEGIN FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects() LOOP IF obj.schema_name IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops') THEN INSERT INTO hf_ops.schema_change_events(database_user,command_tag,object_identity) VALUES(session_user,'DROP',obj.object_identity);END IF;END LOOP;END $$;
DO $$ BEGIN IF(SELECT rolsuper FROM pg_roles WHERE rolname=current_user) THEN
 CREATE EVENT TRIGGER hospitalflow_ddl_audit ON ddl_command_end EXECUTE FUNCTION hf_ops.capture_ddl();
 CREATE EVENT TRIGGER hospitalflow_drop_audit ON sql_drop EXECUTE FUNCTION hf_ops.capture_drop();END IF;END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hf_security,hf_api,hf_ops,hospitalflow FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA hf_api FROM PUBLIC;
CREATE VIEW hospitalflow.payment_reversal_receipts AS SELECT 'REV:'||r.id::text id,p.bill_id,-r.amount amount,'Reversal'::text method,r.at FROM hospitalflow.payment_reversals r JOIN hospitalflow.payments p ON p.id=r.payment_id;
