#!/usr/bin/env python3
"""Generate a reviewable database catalogue from installed metadata; no record values are exported."""
import json,os,subprocess
from local_database_tools import ROOT,settings,tool
c=settings()
def rows(statement):
 wrapped='SELECT COALESCE(json_agg(x),\'[]\'::json) FROM('+statement+')x;'
 result=subprocess.run([tool('psql'),'-X','-w','-h',c['host'],'-p',str(c['port']),'-U',c.get('owner_user','postgres'),'-d',c['database'],'-v','ON_ERROR_STOP=1','-Atq'],input=wrapped,text=True,capture_output=True,env={**os.environ,'PGPASSWORD':c['owner_password']})
 if result.returncode:raise RuntimeError('Database metadata export failed.')
 return json.loads(result.stdout)
def esc(value):return str(value if value is not None else '').replace('|','\\|').replace('\n',' ')
def table(headers,data):return '\n| '+' | '.join(headers)+' |\n| '+' | '.join('---' for _ in headers)+' |\n'+''.join('| '+' | '.join(esc(x) for x in row)+' |\n' for row in data)+'\n'
schemas="('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops')"
counts=rows('SELECT object_type,count(*) n FROM hf_ops.object_inventory GROUP BY object_type ORDER BY object_type')
text='# Installed HospitalFlow database catalogue\n\nGenerated from the installed PostgreSQL metadata on `localhost:5432/hospitalflow`. No patient records, password hashes or credentials are included. Regenerate with `python3 scripts/export_database_catalog.py`.\n'
text+=table(['Object type','Count'],[(x['object_type'],x['n']) for x in counts])
text+='## Tables and columns\n\nThe `hospitalflow` schema contains business/security data. `hf_ops` contains schedules, operational evidence and recovery metadata. New financial and inventory ledgers use append-only records; see the enterprise database guide for privilege and retention boundaries.\n'
columns=rows("SELECT c.table_schema,c.table_name,c.column_name,c.data_type,c.is_nullable,c.column_default FROM information_schema.columns c JOIN information_schema.tables t ON t.table_schema=c.table_schema AND t.table_name=c.table_name WHERE c.table_schema IN ('hospitalflow','hf_ops') AND t.table_type='BASE TABLE' ORDER BY c.table_schema,c.table_name,c.ordinal_position")
for name in sorted({x['table_schema']+'.'+x['table_name'] for x in columns}):
 text+='\n### '+name+'\n'
 text+=table(['Column','Type','Nullable','Default'],[(x['column_name'],x['data_type'],x['is_nullable'],x['column_default']) for x in columns if x['table_schema']+'.'+x['table_name']==name])
text+='## Stored procedures and functions\n'
routines=rows("SELECT n.nspname,p.proname,CASE p.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END kind,pg_get_function_identity_arguments(p.oid) arguments,p.prosecdef security_definer FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN "+schemas+" ORDER BY n.nspname,p.proname")
text+=table(['Schema','Routine','Kind','Arguments','Security definer'],[(x['nspname'],x['proname'],x['kind'],x['arguments'],x['security_definer']) for x in routines])
text+='## Views, aliases and materialized reports\n'
objects=rows("SELECT schema_name,object_type,object_name FROM hf_ops.object_inventory WHERE object_type IN('VIEW','MATERIALIZED VIEW','TYPE','SEQUENCE','POLICY','EVENT TRIGGER') ORDER BY object_type,schema_name,object_name")
text+=table(['Schema','Type','Object'],[(x['schema_name'],x['object_type'],x['object_name']) for x in objects])
text+='## Trigger inventory\n'
triggers=rows("SELECT schema_name,object_name FROM hf_ops.object_inventory WHERE object_type='TRIGGER' ORDER BY schema_name,object_name")
text+=table(['Schema','Table and trigger'],[(x['schema_name'],x['object_name']) for x in triggers])
text+='## Constraint inventory\n'
constraints=rows("SELECT n.nspname,c.relname,k.conname,pg_get_constraintdef(k.oid) definition FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('hospitalflow','hf_ops') ORDER BY n.nspname,c.relname,k.conname")
text+=table(['Schema','Table','Constraint','Definition'],[(x['nspname'],x['relname'],x['conname'],x['definition']) for x in constraints])
text+='## Database job definitions\n\nIntervals are enforced by the database dispatcher. A separately installed scheduler must invoke it; a row in this table alone does not prove execution.\n'
jobs=rows('SELECT name,task,interval_seconds,enabled FROM hf_ops.job_definitions ORDER BY name')
text+=table(['Job','Task','Interval seconds','Enabled definition'],[(x['name'],x['task'],x['interval_seconds'],x['enabled']) for x in jobs])
path=ROOT/'docs/DATABASE_OBJECTS.md';path.write_text(text);print('Installed database catalogue exported:',path)
