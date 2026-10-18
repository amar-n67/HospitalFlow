#!/usr/bin/env python3
"""Print installed objects and aggregate record counts; no credentials or patient details."""
import argparse,os,subprocess
from local_database_tools import tool,settings
parser=argparse.ArgumentParser();parser.add_argument('--objects',action='store_true');args=parser.parse_args();c=settings()
query="SELECT object_type,count(*) FROM hf_ops.object_inventory GROUP BY object_type ORDER BY object_type;"
if args.objects:query+="SELECT schema_name,object_type,object_name FROM hf_ops.object_inventory ORDER BY schema_name,object_type,object_name;"
query+="""
SELECT 'patients',count(*) FROM hospitalflow.patients;
SELECT 'users',count(*) FROM hospitalflow.users;
SELECT 'admissions',count(*) FROM hospitalflow.admissions;
SELECT 'bills',count(*) FROM hospitalflow.bills;
SELECT 'inventory_batches',count(*),sum(quantity) FROM hospitalflow.medicine_batches;
SELECT 'activity_events',count(*) FROM hospitalflow.activity_log;
SELECT 'row_history',count(*) FROM hospitalflow.row_history;
SELECT 'migrations',count(*) FROM hospitalflow.schema_versions;
SELECT name,enabled,health,last_status FROM hf_ops.job_health ORDER BY name;
"""
subprocess.run([tool('psql'),'-X','-w','-h',c['host'],'-p',str(c['port']),'-U',c.get('runtime_user','hospitalflow_app'),'-d',c['database'],'-v','ON_ERROR_STOP=1','-Atq'],input=query,text=True,env={**os.environ,'PGPASSWORD':c['runtime_password']},check=True)
