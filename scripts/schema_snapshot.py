#!/usr/bin/env python3
"""Verify that an additive schema deployment preserves pre-existing records without printing their values."""
import argparse,json,os,re,subprocess
from local_database_tools import ROOT,settings,tool
parser=argparse.ArgumentParser();parser.add_argument('command',choices=['capture','verify']);args=parser.parse_args()
c=settings();path=ROOT/'.local/pre-enterprise-snapshot.json'
def query(statement):
 r=subprocess.run([tool('psql'),'-X','-w','-h',c['host'],'-p',str(c['port']),'-U',c.get('owner_user','postgres'),'-d',c['database'],'-v','ON_ERROR_STOP=1','-Atq'],input=statement,text=True,capture_output=True,env={**os.environ,'PGPASSWORD':c['owner_password']})
 if r.returncode:raise RuntimeError(r.stderr)
 return r.stdout.strip()
def snapshot(table,columns):
 if not all(re.fullmatch('[a-z_]+',x) for x in [table]+columns):raise RuntimeError('Unexpected identifier')
 cols=','.join('"'+x+'"' for x in columns)
 return query("SET TIME ZONE 'UTC';SELECT count(*)||'|'||md5(COALESCE(string_agg(md5(to_jsonb(r)::text),'' ORDER BY md5(to_jsonb(r)::text)),'')) FROM(SELECT "+cols+' FROM hospitalflow."'+table+'")r;')
if args.command=='capture':
 if path.exists():raise SystemExit('Pre-deployment snapshot already exists; it was not overwritten.')
 result={}
 for table in query("SELECT tablename FROM pg_tables WHERE schemaname='hospitalflow' ORDER BY tablename;").splitlines():
  if table=='schema_versions':continue
  cols=query("SELECT column_name FROM information_schema.columns WHERE table_schema='hospitalflow' AND table_name='"+table+"' ORDER BY ordinal_position;").splitlines()
  result[table]={'columns':cols,'snapshot':snapshot(table,cols)}
 fd=os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
 with os.fdopen(fd,'w') as f:json.dump(result,f,indent=2)
 print('Captured preservation fingerprints for',len(result),'existing tables. No record values were printed.')
else:
 data=json.loads(path.read_text())
 for table,item in data.items():
  if snapshot(table,item['columns'])!=item['snapshot']:raise RuntimeError('Preservation check differs for '+table+'; review before restarting writers.')
 print('VERIFIED:',len(data),'pre-existing tables retain exactly the same records and original column values.')
