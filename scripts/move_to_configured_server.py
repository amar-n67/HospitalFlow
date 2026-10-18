#!/usr/bin/env python3
"""Move HospitalFlow into a NEW database on the user's configured PostgreSQL server.
Stop the application first. Existing destination databases and roles are never overwritten.
Credentials are read from ignored, owner-readable .local files, never printed.
"""
import datetime,json,os,pathlib,secrets,subprocess
from local_database_tools import ROOT,tool,settings
local=ROOT/'.local';source=settings();target=json.loads((local/'server5432-admin.json').read_text())
def private(path,text):
 fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
 with os.fdopen(fd,'w') as f:f.write(text)
 os.chmod(path,0o600)
def sql(c,query,database=None,user=None,password=None):
 result=subprocess.run([tool('psql'),'-X','-w','-h',c['host'],'-p',str(c['port']),'-U',user or c.get('owner_user','hospitalflow_owner'),'-d',database or c['database'],'-v','ON_ERROR_STOP=1','-At'],input=query,text=True,capture_output=True,env={**os.environ,'PGPASSWORD':password or c['owner_password'],'PGGSSENCMODE':'disable'})
 if result.returncode:raise RuntimeError(result.stderr)
 return result.stdout.strip()
name=target['database']
if name!='hospitalflow':raise SystemExit('This migration only creates the dedicated hospitalflow database.')
if sql(target,"SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname='hospitalflow');",'postgres')!='f':raise SystemExit('Destination hospitalflow already exists; nothing was overwritten.')
if sql(target,"SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='hospitalflow_app');",'postgres')!='f':raise SystemExit('Destination runtime role already exists; nothing was overwritten.')
# Record a consistent snapshot and retain rollback configuration before modifying the destination.
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup=local/'backups'/f'hospitalflow-before-5432-{stamp}.dump';backup.parent.mkdir(exist_ok=True,mode=0o700)
private(backup,'')
subprocess.run([tool('pg_dump'),'-h',source['host'],'-p',str(source['port']),'-U',source.get('owner_user','hospitalflow_owner'),'-d',source['database'],'-Fc','--schema=hospitalflow','--no-owner','--no-acl','-f',str(backup)],check=True,env={**os.environ,'PGPASSWORD':source['owner_password']})
private(local/'database-55432.json',json.dumps(source,indent=2))
private(local/'appsettings-55432.json',(ROOT/'HospitalFlow/appsettings.Local.json').read_text())
runtime=secrets.token_hex(32)
sql(target,f"CREATE ROLE hospitalflow_app LOGIN PASSWORD '{runtime}'; CREATE DATABASE hospitalflow OWNER postgres;",'postgres')
subprocess.run([tool('pg_restore'),'-h',target['host'],'-p',str(target['port']),'-U',target['owner_user'],'-d',name,'--single-transaction','--no-owner','--no-acl','--exit-on-error',str(backup)],check=True,env={**os.environ,'PGPASSWORD':target['owner_password'],'PGGSSENCMODE':'disable'})
sql(target,'REVOKE ALL ON DATABASE hospitalflow FROM PUBLIC; GRANT CONNECT,TEMP ON DATABASE hospitalflow TO hospitalflow_app;',name)
sql(target,(ROOT/'HospitalFlow/Database/grant_runtime.sql').read_text())
# Compare every table, including sessions, keys, history and inventory, before switching connections.
tables=sql(source,"SELECT tablename FROM pg_tables WHERE schemaname='hospitalflow' ORDER BY tablename;").splitlines()
report={}
for table in tables:
 if not table.replace('_','').isalnum():raise RuntimeError('Unexpected identifier')
 query=f"SET TIME ZONE 'UTC'; SELECT count(*)||'|'||md5(COALESCE(string_agg(md5(to_jsonb(t)::text),'' ORDER BY md5(to_jsonb(t)::text)),'')) FROM hospitalflow.\"{table}\" t;"
 before=sql(source,query).splitlines()[-1];after=sql(target,query).splitlines()[-1]
 if before!=after:raise RuntimeError('Record verification failed for '+table+'; application configuration is unchanged.')
 report[table]={'rows':int(after.split('|')[0]),'verified':True}
# Check least-privilege runtime connectivity before publishing credentials.
sql(target,'SELECT count(*) FROM hospitalflow.medicine_batches;',user='hospitalflow_app',password=runtime)
target.update(runtime_user='hospitalflow_app',runtime_password=runtime,managed_cluster=False)
config={'ConnectionStrings':{'HospitalFlow':f"Host={target['host']};Port={target['port']};Database={name};Username=hospitalflow_app;Password={runtime};SSL Mode=Disable;Include Error Detail=false"},'Database':{'SeedDemo':False}}
private(ROOT/'HospitalFlow/appsettings.Local.json',json.dumps(config,indent=2))
private(local/'database.json',json.dumps(target,indent=2))
private(local/'migration-to-5432-report.json',json.dumps({'host':target['host'],'port':target['port'],'database':name,'tables':report,'backup':str(backup)},indent=2))
print('HospitalFlow migrated to localhost:5432/hospitalflow.')
print(f'All {len(tables)} tables verified row-for-row. Inventory batches: {report["medicine_batches"]["rows"]}; activity events: {report["activity_log"]["rows"]}.')
print('Runtime configuration switched. Previous database and rollback configuration retained.')
