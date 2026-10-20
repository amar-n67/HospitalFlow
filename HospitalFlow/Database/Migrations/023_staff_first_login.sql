-- New staff registrations require DOB verification and a replacement password before sessions.
-- Existing accounts keep their credentials and activation status.
CREATE TABLE hospitalflow.staff_onboarding(
 user_id text PRIMARY KEY REFERENCES hospitalflow.users(id),must_change_password boolean NOT NULL DEFAULT true,
 expires_at timestamptz NOT NULL DEFAULT now()+interval '24 hours',activated_at timestamptz,
 CHECK(must_change_password OR activated_at IS NOT NULL));
REVOKE ALL ON hospitalflow.staff_onboarding FROM PUBLIC;
ALTER TABLE hospitalflow.patient_login_challenges DROP CONSTRAINT patient_login_challenges_user_id_fkey;
ALTER TABLE hospitalflow.patient_login_challenges ADD CONSTRAINT first_login_challenge_user_fkey FOREIGN KEY(user_id) REFERENCES hospitalflow.users(id);
