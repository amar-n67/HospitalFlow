#!/usr/bin/env python3
"""Create a protected custom-format backup and retain success/failure evidence in hf_ops."""
import datetime,hashlib,os,pathlib,re,subprocess
from local_database_tools import ROOT,settings,tool
c=settings();folder=ROOT/'.local/backups';folder.mkdir(exist_ok=True,mode=0o700)
target=folder/('hospitalflow-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')+'.dump')
env={**os.environ,'PGPASSWORD':c['owner_password'],'PGAPPNAME':'HospitalFlow backup worker'}
def sql(query):
 r=subprocess.run([tool('psql'),'-X','-w','-h',c['host'],'-p',str(c['port']),'-U',c.get('owner_user','postgres'),'-d',c['database'],'-v','ON_ERROR_STOP=1','-Atq'],input=query,text=True,capture_output=True,env=env)
 if r.returncode:raise RuntimeError('Backup metadata operation failed; inspect database permissions/connectivity.')
 return r.stdout.strip()
recorded=sql("SELECT to_regprocedure('hf_ops.start_backup(uuid)') IS NOT NULL;")=='t';run=None
if recorded:
 run=sql('CALL hf_ops.start_backup(NULL);').splitlines()[0]
 if not re.fullmatch('[a-f0-9-]{36}',run):raise RuntimeError('Invalid backup run identifier')
fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600);os.close(fd)
try:
 r=subprocess.run([tool('pg_dump'),'-h',c['host'],'-p',str(c['port']),'-U',c.get('owner_user','postgres'),'-d',c['database'],'-Fc','--no-owner','--no-acl','-f',str(target)],env=env,capture_output=True)
 if r.returncode:raise RuntimeError('PostgreSQL backup failed; no credentials or SQL payloads are logged.')
 with target.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
 if recorded:sql(f"CALL hf_ops.finish_backup('{run}'::uuid,true,'{target.name}',{target.stat().st_size},'{digest}');")
except Exception:
 target.unlink(missing_ok=True)
 if recorded:sql(f"CALL hf_ops.finish_backup('{run}'::uuid,false,NULL,NULL,NULL);")
 raise
print('Backup saved:',target)
