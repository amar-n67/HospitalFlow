#!/usr/bin/env python3
"""Generate a password-free, schema-only SQL installer for a NEW empty database."""
import hashlib
from local_database_tools import ROOT
files=sorted((ROOT/'HospitalFlow/Database/Migrations').glob('*.sql'))
text='''-- HospitalFlow schema-only installer. Generated; edit numbered migrations, then regenerate.
-- Run only in a NEW EMPTY PostgreSQL 17 database as its migration owner.
-- This does not contain passwords, patient data, or application bootstrap accounts.
-- After installing, run the application's --migrate bootstrap job to create its random
-- request-fingerprint key and initial administrator, then apply grant_runtime.sql.
BEGIN;
DO $$ BEGIN IF to_regclass('hospitalflow.users') IS NOT NULL THEN RAISE EXCEPTION 'Refusing to install over an existing HospitalFlow database. Apply numbered migrations instead.';END IF;END $$;
CREATE SCHEMA IF NOT EXISTS hospitalflow;
CREATE TABLE hospitalflow.schema_versions(version text PRIMARY KEY,checksum text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now());
'''
for file in files:
 text+='\n-- '+file.name+'\n'+file.read_text()+'\n'
 name='HospitalFlow.Database.Migrations.'+file.name
 text+="INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES('"+name+"','"+hashlib.sha256(file.read_bytes()).hexdigest().upper()+"');\n"
text+='COMMIT;\n-- Provision the restricted application login separately; no password is embedded here.\n'
path=ROOT/'HospitalFlow/Database/hospitalflow_schema.sql';path.write_text(text)
print('Schema-only installer generated:',path)
