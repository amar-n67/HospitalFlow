-- Three application roles; existing job responsibilities become explicit grants.
INSERT INTO hospitalflow.roles(name) VALUES('User'),('Admin'),('Developer') ON CONFLICT DO NOTHING;
CREATE TABLE hospitalflow.user_permissions(
 user_id text NOT NULL REFERENCES hospitalflow.users(id),
 permission text NOT NULL CHECK(permission IN ('Reception','Doctor','Nurse','Pharmacist','Billing')),
 PRIMARY KEY(user_id,permission));
INSERT INTO hospitalflow.user_permissions SELECT id,role FROM hospitalflow.users WHERE role IN ('Reception','Doctor','Nurse','Pharmacist','Billing');
UPDATE hospitalflow.users SET role=CASE WHEN role='Administrator' THEN 'Admin' ELSE 'User' END WHERE role NOT IN ('User','Admin','Developer');
DELETE FROM hospitalflow.roles WHERE name NOT IN ('User','Admin','Developer');
ALTER TABLE hospitalflow.users ADD COLUMN email_confirmed boolean NOT NULL DEFAULT true;
CREATE TABLE hospitalflow.account_tokens(
 token_hash text PRIMARY KEY CHECK(length(token_hash)=64),user_id text NOT NULL REFERENCES hospitalflow.users(id),
 purpose text NOT NULL CHECK(purpose IN ('verify','reset')),expires_at timestamptz NOT NULL,consumed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX account_tokens_user ON hospitalflow.account_tokens(user_id,purpose);
CREATE TABLE hospitalflow.account_mail(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id text NOT NULL REFERENCES hospitalflow.users(id),
 encrypted_message text NOT NULL,status text NOT NULL DEFAULT 'Pending' CHECK(status IN ('Pending','Sent','Failed')),
 attempts integer NOT NULL DEFAULT 0,next_attempt_at timestamptz NOT NULL DEFAULT now(),
 created_at timestamptz NOT NULL DEFAULT now(),sent_at timestamptz,error_code text);
CREATE INDEX account_mail_due ON hospitalflow.account_mail(next_attempt_at) WHERE status='Pending';
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.user_permissions FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE FUNCTION hf_security.protect_account() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(74192301);
 IF NEW.active AND NOT NEW.email_confirmed THEN RAISE EXCEPTION 'Verify email before account approval' USING ERRCODE='23514';END IF;
 IF TG_OP='UPDATE' AND OLD.active AND OLD.role IN ('Admin','Developer') AND (NOT NEW.active OR NEW.role='User') AND
 NOT EXISTS(SELECT 1 FROM hospitalflow.users WHERE id<>OLD.id AND active AND role IN ('Admin','Developer')) THEN
 RAISE EXCEPTION 'An active full-access account must remain' USING ERRCODE='23514';END IF;
 RETURN NEW;END $$;
CREATE TRIGGER protect_account BEFORE INSERT OR UPDATE ON hospitalflow.users FOR EACH ROW EXECUTE FUNCTION hf_security.protect_account();
CREATE OR REPLACE FUNCTION hf_security.require_actor(p_roles text[]) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE u hospitalflow.users%ROWTYPE;BEGIN
 SELECT * INTO u FROM hospitalflow.users WHERE id=nullif(current_setting('hospitalflow.actor_id',true),'') AND active AND email_confirmed;
 IF NOT FOUND OR (u.role NOT IN ('Admin','Developer') AND NOT EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id AND p.permission=ANY(p_roles))) THEN
 RAISE EXCEPTION 'Active authorized application identity required' USING ERRCODE='42501';END IF;RETURN u.id;END $$;
-- Update the two existing routines containing an administrator-specific branch.
DO $$ DECLARE definition text;signature text;BEGIN
 FOREACH signature IN ARRAY ARRAY['hf_security.can_access_patient(text)','hf_api.execute(text,jsonb,uuid,text)'] LOOP
 SELECT pg_get_functiondef(signature::regprocedure) INTO definition;
 definition:=replace(definition, 'u.role=''Administrator''','u.role IN (''Admin'',''Developer'')');
 definition:=replace(definition, 'role=''Administrator''','role IN (''Admin'',''Developer'')');
 EXECUTE definition;
 END LOOP;
END $$;
REVOKE ALL ON hospitalflow.user_permissions,hospitalflow.account_tokens,hospitalflow.account_mail FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hf_security.protect_account() FROM PUBLIC;
