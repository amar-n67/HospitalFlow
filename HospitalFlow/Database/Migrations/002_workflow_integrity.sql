SET search_path TO hospitalflow,public;
CREATE FUNCTION validate_stock_balance() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN
 IF EXISTS(SELECT 1 FROM hospitalflow.medicine_batches m WHERE m.quantity<>(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_movements WHERE medicine_id=m.id)) THEN
 RAISE EXCEPTION 'Stock balance must match its movement ledger' USING ERRCODE='23514';END IF;
 RETURN NULL;END $$;
CREATE CONSTRAINT TRIGGER stock_batch_balance AFTER INSERT OR UPDATE ON medicine_batches DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_stock_balance();
CREATE CONSTRAINT TRIGGER stock_movement_balance AFTER INSERT ON stock_movements DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_stock_balance();
CREATE FUNCTION validate_dispense_expiry() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN
 IF NEW.status='Dispensed' AND (TG_OP='INSERT' OR OLD.status<>'Dispensed') AND EXISTS(SELECT 1 FROM hospitalflow.medicine_batches WHERE id=NEW.medicine_id AND expiry<=current_date) THEN
 RAISE EXCEPTION 'Expired medicine cannot be dispensed' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER dispense_expiry BEFORE INSERT OR UPDATE ON prescriptions FOR EACH ROW EXECUTE FUNCTION validate_dispense_expiry();
CREATE FUNCTION validate_discharge_readiness() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN
 IF NEW.status='Discharged' AND (TG_OP='INSERT' OR OLD.status<>'Discharged') AND
 (EXISTS(SELECT 1 FROM hospitalflow.invoice_balances WHERE patient_id=NEW.patient_id AND balance>0) OR
 EXISTS(SELECT 1 FROM hospitalflow.prescriptions WHERE patient_id=NEW.patient_id AND status='Pending')) THEN
 RAISE EXCEPTION 'Discharge requires settled invoices and completed prescriptions' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE CONSTRAINT TRIGGER discharge_readiness AFTER INSERT OR UPDATE ON admissions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_discharge_readiness();
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hospitalflow FROM PUBLIC;
