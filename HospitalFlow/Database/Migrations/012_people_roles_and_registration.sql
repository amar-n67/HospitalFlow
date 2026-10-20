INSERT INTO hospitalflow.roles(name) VALUES('Doctor'),('Nurse'),('Volunteer') ON CONFLICT DO NOTHING;
CREATE SEQUENCE hospitalflow.person_number START 1000;
CREATE FUNCTION hf_api.person_id(p_prefix text) RETURNS text LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE serial text;BEGIN IF p_prefix NOT IN ('P','D','N','V','A','DEV','U') THEN RAISE EXCEPTION 'Unknown registration type' USING ERRCODE='23514';END IF;
 serial:=nextval('hospitalflow.person_number')::text;RETURN p_prefix||'-'||lpad(serial,greatest(6,length(serial)),'0');END $$;
ALTER TABLE hospitalflow.patients ADD COLUMN registration_id text UNIQUE,ADD COLUMN email text,ADD COLUMN address text,ADD COLUMN emergency_contact text;
UPDATE hospitalflow.patients SET registration_id=hf_api.person_id('P');
UPDATE hospitalflow.patients p SET email=u.email FROM hospitalflow.patient_accounts a JOIN hospitalflow.users u ON u.id=a.user_id WHERE p.id=a.patient_id;
ALTER TABLE hospitalflow.patients ALTER COLUMN registration_id SET NOT NULL;
ALTER TABLE hospitalflow.patients ADD CONSTRAINT patient_email_format CHECK(email IS NULL OR(length(email)<=150 AND email=lower(trim(email)) AND email~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'));
CREATE UNIQUE INDEX patient_email_unique ON hospitalflow.patients(lower(email)) WHERE email IS NOT NULL;
ALTER TABLE hospitalflow.patients ADD CONSTRAINT patient_contact_lengths CHECK((address IS NULL OR length(address)<=1000) AND(emergency_contact IS NULL OR length(emergency_contact)<=200));
ALTER TABLE hospitalflow.doctors ADD COLUMN registration_id text UNIQUE;
UPDATE hospitalflow.doctors SET registration_id=hf_api.person_id('D');
ALTER TABLE hospitalflow.doctors ALTER COLUMN registration_id SET NOT NULL;
UPDATE hospitalflow.users u SET role=CASE WHEN EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id AND permission='Doctor') THEN 'Doctor' ELSE 'Nurse' END
 WHERE role='User' AND NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts a WHERE a.user_id=u.id) AND EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id AND permission IN ('Doctor','Nurse'));
ALTER TABLE hospitalflow.users ADD COLUMN registration_id text UNIQUE;
UPDATE hospitalflow.users SET registration_id=hf_api.person_id(CASE role WHEN 'Admin' THEN 'A' WHEN 'Developer' THEN 'DEV' WHEN 'Doctor' THEN 'D' WHEN 'Nurse' THEN 'N' WHEN 'Volunteer' THEN 'V' ELSE 'U' END);
UPDATE hospitalflow.users u SET registration_id=p.registration_id FROM hospitalflow.patient_accounts a JOIN hospitalflow.patients p ON p.id=a.patient_id WHERE u.id=a.user_id;
ALTER TABLE hospitalflow.users ALTER COLUMN registration_id SET NOT NULL;
CREATE TABLE hospitalflow.person_profiles(
 user_id text PRIMARY KEY REFERENCES hospitalflow.users(id),doctor_id text UNIQUE REFERENCES hospitalflow.doctors(id),
 mobile text CHECK(mobile IS NULL OR mobile~'^\+[0-9]{7,15}$'),dob date CHECK(dob>=date '1900-01-01'),
 sex text CHECK(sex IN ('Male','Female','Other','Prefer not to say')),address text CHECK(length(address)<=1000),
 department text REFERENCES hospitalflow.departments(name),job_title text CHECK(length(job_title)<=100),
 occupation text CHECK(occupation IN ('Guard','Washerman','Housekeeping','Other')),created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
INSERT INTO hospitalflow.person_profiles(user_id) SELECT id FROM hospitalflow.users WHERE NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts a WHERE a.user_id=users.id);
CREATE FUNCTION hf_security.registration_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
DECLARE prefix text;expected text;BEGIN
 IF TG_TABLE_NAME='patients' THEN prefix:='P';
 ELSIF TG_TABLE_NAME='doctors' THEN prefix:='D';
 ELSE prefix:=CASE NEW.role WHEN 'Admin' THEN 'A' WHEN 'Developer' THEN 'DEV' WHEN 'Doctor' THEN 'D' WHEN 'Nurse' THEN 'N' WHEN 'Volunteer' THEN 'V' ELSE 'U' END;
  IF TG_OP='UPDATE' AND OLD.role<>NEW.role THEN NEW.registration_id:=hf_api.person_id(prefix);END IF;
  SELECT p.registration_id INTO expected FROM hospitalflow.patient_accounts a JOIN hospitalflow.patients p ON p.id=a.patient_id WHERE a.user_id=NEW.id;
  IF expected IS NOT NULL THEN IF NEW.registration_id IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Patient and account registration IDs must match' USING ERRCODE='23514';END IF;prefix:='P';END IF;
 END IF;
 IF NEW.registration_id IS NULL THEN NEW.registration_id:=hf_api.person_id(prefix);END IF;
 IF TG_OP='UPDATE' AND TG_TABLE_NAME IN ('patients','doctors') AND OLD.registration_id<>NEW.registration_id THEN RAISE EXCEPTION 'Registration ID is immutable' USING ERRCODE='23514';END IF;
 IF NEW.registration_id!~('^'||prefix||'-[0-9]+$') THEN RAISE EXCEPTION 'Invalid registration prefix' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER registration_identity BEFORE INSERT OR UPDATE ON hospitalflow.patients FOR EACH ROW EXECUTE FUNCTION hf_security.registration_identity();
CREATE TRIGGER registration_identity BEFORE INSERT OR UPDATE ON hospitalflow.doctors FOR EACH ROW EXECUTE FUNCTION hf_security.registration_identity();
CREATE TRIGGER registration_identity BEFORE INSERT OR UPDATE ON hospitalflow.users FOR EACH ROW EXECUTE FUNCTION hf_security.registration_identity();
CREATE FUNCTION hospitalflow.sync_patient_registration() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN UPDATE hospitalflow.users SET registration_id=(SELECT registration_id FROM hospitalflow.patients WHERE id=NEW.patient_id) WHERE id=NEW.user_id;RETURN NEW;END $$;
CREATE TRIGGER sync_registration AFTER INSERT ON hospitalflow.patient_accounts FOR EACH ROW EXECUTE FUNCTION hospitalflow.sync_patient_registration();
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.person_profiles FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE FUNCTION hf_security.validate_person_profile() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF NEW.dob>current_date THEN RAISE EXCEPTION 'Date of birth cannot be in the future' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER validate_profile BEFORE INSERT OR UPDATE ON hospitalflow.person_profiles FOR EACH ROW EXECUTE FUNCTION hf_security.validate_person_profile();
CREATE OR REPLACE FUNCTION hf_security.require_actor(p_roles text[]) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
DECLARE u hospitalflow.users%ROWTYPE;BEGIN
 SELECT * INTO u FROM hospitalflow.users WHERE id=nullif(current_setting('hospitalflow.actor_id',true),'') AND active AND email_confirmed;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=u.id) OR u.role='Volunteer' OR
 (u.role NOT IN ('Admin','Developer') AND NOT(u.role=ANY(p_roles)) AND NOT EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id AND p.permission=ANY(p_roles))) THEN
 RAISE EXCEPTION 'Active authorized staff identity required' USING ERRCODE='42501';END IF;RETURN u.id;END $$;
CREATE OR REPLACE FUNCTION hf_security.protect_account() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(74192301);
 IF NEW.active AND NOT NEW.email_confirmed THEN RAISE EXCEPTION 'Verify email before account approval' USING ERRCODE='23514';END IF;
 IF TG_OP='UPDATE' AND OLD.active AND OLD.role IN ('Admin','Developer') AND (NOT NEW.active OR NEW.role NOT IN ('Admin','Developer')) AND NOT EXISTS(SELECT 1 FROM hospitalflow.users WHERE id<>OLD.id AND active AND role IN ('Admin','Developer')) THEN RAISE EXCEPTION 'An active full-access account must remain' USING ERRCODE='23514';END IF;
 RETURN NEW;END $$;
-- Name/contact updates cannot silently move a linked login to another email.
CREATE FUNCTION hf_security.patient_email_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN IF EXISTS(SELECT 1 FROM hospitalflow.patient_accounts a JOIN hospitalflow.users u ON u.id=a.user_id WHERE a.patient_id=NEW.id AND u.email IS DISTINCT FROM NEW.email) THEN RAISE EXCEPTION 'Linked patient email requires identity-reviewed account change' USING ERRCODE='23514';END IF;RETURN NEW;END $$;
CREATE TRIGGER linked_email BEFORE UPDATE OF email ON hospitalflow.patients FOR EACH ROW EXECUTE FUNCTION hf_security.patient_email_guard();
DO $$ DECLARE definition text;BEGIN
 SELECT pg_get_functiondef('hf_api.save_patient(text,text,date,text,text)'::regprocedure) INTO definition;
 definition:=replace(definition,'INSERT INTO hospitalflow.patients VALUES(', 'INSERT INTO hospitalflow.patients(id,name,dob,sex,phone,created) VALUES(');EXECUTE definition;
 SELECT pg_get_functiondef('hf_api.execute(text,jsonb,uuid,text)'::regprocedure) INTO definition;
 definition:=replace(definition,' WHEN ''doctor'' THEN',' UPDATE hospitalflow.patients SET email=COALESCE(p_payload->>''email'',email),address=COALESCE(p_payload->>''address'',address),emergency_contact=COALESCE(p_payload->>''emergencyContact'',emergency_contact) WHERE id=result; WHEN ''doctor'' THEN');
 EXECUTE definition;
END $$;
REVOKE EXECUTE ON FUNCTION hf_api.person_id(text),hf_security.registration_identity(),hf_security.validate_person_profile(),hf_security.patient_email_guard(),hospitalflow.sync_patient_registration() FROM PUBLIC;
REVOKE ALL ON hospitalflow.person_profiles FROM PUBLIC;
