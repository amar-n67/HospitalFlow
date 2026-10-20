-- Existing Indian E.164 values retain their exact subscriber number.
ALTER TABLE hospitalflow.person_profiles DROP CONSTRAINT person_profiles_mobile_check;
UPDATE hospitalflow.patients SET phone=substring(phone FROM 4) WHERE phone~'^\+91[0-9]{10}$';
UPDATE hospitalflow.person_profiles SET mobile=substring(mobile FROM 4) WHERE mobile~'^\+91[0-9]{10}$';
UPDATE hospitalflow.patient_contacts SET phone=substring(phone FROM 4) WHERE phone~'^\+91[0-9]{10}$';
UPDATE hospitalflow.suppliers SET contact_phone=substring(contact_phone FROM 4) WHERE contact_phone~'^\+91[0-9]{10}$';
ALTER TABLE hospitalflow.patients ADD CONSTRAINT patient_mobile_ten_digits CHECK(phone~'^[0-9]{10}$');
ALTER TABLE hospitalflow.person_profiles ADD CONSTRAINT profile_mobile_ten_digits CHECK(mobile IS NULL OR mobile~'^[0-9]{10}$');
ALTER TABLE hospitalflow.patient_contacts ADD CONSTRAINT contact_mobile_ten_digits CHECK(phone~'^[0-9]{10}$');
ALTER TABLE hospitalflow.suppliers ADD CONSTRAINT supplier_mobile_ten_digits CHECK(contact_phone IS NULL OR contact_phone~'^[0-9]{10}$');
