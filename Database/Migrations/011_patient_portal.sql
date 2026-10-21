CREATE TABLE hospitalflow.patient_accounts(
 user_id text PRIMARY KEY REFERENCES hospitalflow.users(id),patient_id text NOT NULL UNIQUE REFERENCES hospitalflow.patients(id),
 must_change_password boolean NOT NULL DEFAULT true,temporary_expires_at timestamptz NOT NULL,
 invited_at timestamptz NOT NULL DEFAULT now(),activated_at timestamptz,
 CHECK((must_change_password AND activated_at IS NULL) OR (NOT must_change_password AND activated_at IS NOT NULL)));
CREATE TABLE hospitalflow.patient_login_challenges(
 token_hash text PRIMARY KEY CHECK(length(token_hash)=64),user_id text NOT NULL REFERENCES hospitalflow.patient_accounts(user_id),
 expires_at timestamptz NOT NULL,attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),consumed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX patient_challenge_user ON hospitalflow.patient_login_challenges(user_id);
CREATE TABLE hospitalflow.patient_sms(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id text NOT NULL REFERENCES hospitalflow.patient_accounts(user_id),
 encrypted_message text NOT NULL,status text NOT NULL DEFAULT 'Pending' CHECK(status IN ('Pending','Local pickup','Failed')),
 created_at timestamptz NOT NULL DEFAULT now(),completed_at timestamptz);
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.patient_accounts FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE FUNCTION hf_security.guard_patient_account() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN
 IF TG_TABLE_NAME='users' THEN
  IF EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=NEW.id) AND NEW.role<>'User' THEN RAISE EXCEPTION 'Patient accounts cannot become staff accounts' USING ERRCODE='23514';END IF;
 ELSIF TG_TABLE_NAME='user_permissions' THEN
  IF EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=NEW.user_id) THEN RAISE EXCEPTION 'Patient accounts cannot receive staff permissions' USING ERRCODE='23514';END IF;
 ELSE
  IF NOT EXISTS(SELECT 1 FROM hospitalflow.users u WHERE u.id=NEW.user_id AND u.role='User' AND NOT EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id)) THEN RAISE EXCEPTION 'Patient identity requires a dedicated limited User account' USING ERRCODE='23514';END IF;
 END IF;
 RETURN NEW;END $$;
CREATE TRIGGER patient_role_guard BEFORE UPDATE ON hospitalflow.users FOR EACH ROW EXECUTE FUNCTION hf_security.guard_patient_account();
CREATE TRIGGER patient_grant_guard BEFORE INSERT OR UPDATE ON hospitalflow.user_permissions FOR EACH ROW EXECUTE FUNCTION hf_security.guard_patient_account();
CREATE TRIGGER patient_link_guard BEFORE INSERT OR UPDATE ON hospitalflow.patient_accounts FOR EACH ROW EXECUTE FUNCTION hf_security.guard_patient_account();
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.save_patient(text,text,date,text,text)'::regprocedure) INTO definition;
 EXECUTE replace(definition,'ARRAY[''Reception'']','ARRAY[''Reception'',''Doctor'']');
 SELECT pg_get_functiondef('hf_api.execute(text,jsonb,uuid,text)'::regprocedure) INTO definition;
 EXECUTE replace(definition,'WHEN p_action IN (''patient'',''patient-update'',''appointment'',''appointment-status'',''book-follow-up'') THEN ARRAY[''Reception'']',
 'WHEN p_action IN (''patient'',''patient-update'') THEN ARRAY[''Reception'',''Doctor''] WHEN p_action IN (''appointment'',''appointment-status'',''book-follow-up'') THEN ARRAY[''Reception'']');
END $$;
REVOKE ALL ON hospitalflow.patient_accounts,hospitalflow.patient_login_challenges,hospitalflow.patient_sms FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hf_security.guard_patient_account() FROM PUBLIC;
CREATE TABLE hospitalflow.user_preferences(user_id text PRIMARY KEY REFERENCES hospitalflow.users(id),theme text NOT NULL CHECK(theme IN ('Default','Dark')),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.user_preferences FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
REVOKE ALL ON hospitalflow.user_preferences FROM PUBLIC;
