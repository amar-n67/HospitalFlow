#!/usr/bin/env python3
"""Restore a recorded local backup in a password-protected disposable cluster; record real evidence."""
import hashlib,json,math,os,pathlib,secrets,socket,subprocess,tempfile,time,uuid
from local_database_tools import ROOT,settings,tool
c=settings()
def sql(query,host=None,port=None,user=None,password=None):
 r=subprocess.run([tool('psql'),'-X','-w','-h',host or c['host'],'-p',str(port or c['port']),'-U',user or c.get('owner_user','postgres'),'-d',c['database'] if host is None else 'postgres','-v','ON_ERROR_STOP=1','-Atq'],input=query,text=True,capture_output=True,env={**os.environ,'PGPASSWORD':password or c['owner_password'],'PGCONNECT_TIMEOUT':'10'})
 if r.returncode:raise RuntimeError('Restore-drill SQL validation failed; inspect protected operational evidence.')
 return r.stdout.strip()
record=sql("SELECT row_to_json(b) FROM(SELECT id,file_reference,sha256 FROM hf_ops.backup_runs WHERE status='Succeeded' ORDER BY completed_at DESC LIMIT 1)b;")
if not record:raise SystemExit('No successful recorded backup is available. Run backup_database.py first.')
backup=json.loads(record);name=backup['file_reference'];folder=ROOT/'.local/backups';path=folder/name
if path.resolve().parent!=folder.resolve():raise SystemExit('Unsafe backup reference.')
with path.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
if digest!=backup['sha256']:raise SystemExit('Backup digest differs; no restore was attempted.')
started=time.perf_counter();success=False;report={}
try:
 with tempfile.TemporaryDirectory(prefix='hospitalflow-real-restore-') as temporary:
  owner_password=secrets.token_hex(32);pw=pathlib.Path(temporary)/'password';pw.write_text(owner_password+'\n');pw.chmod(0o600)
  cluster=pathlib.Path(temporary)/'database'
  with socket.socket() as probe:probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
  subprocess.run([tool('initdb'),'-D',str(cluster),'-U','restore_owner','--auth=scram-sha-256','--pwfile',str(pw),'--encoding=UTF8','--no-locale'],check=True,stdout=subprocess.DEVNULL)
  subprocess.run([tool('pg_ctl'),'-D',str(cluster),'-l',temporary+'/postgres.log','-o',f'-h 127.0.0.1 -p {port} -k {temporary}','-w','start'],check=True,stdout=subprocess.DEVNULL)
  try:
   def restored(query):return sql(query,'127.0.0.1',port,'restore_owner',owner_password)
   restored('CREATE ROLE hospitalflow_app NOLOGIN;CREATE ROLE hospitalflow_job_runner NOLOGIN;CREATE ROLE hospitalflow_report_reader NOLOGIN;')
   result=subprocess.run([tool('pg_restore'),'-h','127.0.0.1','-p',str(port),'-U','restore_owner','-d','postgres','--no-owner','--no-acl','--exit-on-error',str(path)],env={**os.environ,'PGPASSWORD':owner_password},capture_output=True)
   if result.returncode:raise RuntimeError('Backup restore failed; source database is unchanged.')
   restored((ROOT/'Database/grant_operations.sql').read_text()+'\n'+(ROOT/'Database/grant_runtime.sql').read_text())
   report['checks']=json.loads(restored("SELECT json_agg(c) FROM hf_ops.validate_database()c;"))
   failures=restored("SELECT count(*) FROM hf_ops.validate_database() WHERE severity='Error' AND violations>0;")
   if failures!='0':raise RuntimeError('Restored database has integrity/security errors.')
   report={'backup_id':backup['id'],'sha256':digest,'status':'Passed','checks':json.loads(restored("SELECT json_agg(c) FROM hf_ops.validate_database()c;")),
    'patients':int(restored('SELECT count(*) FROM hospitalflow.patients;')),'medicine_batches':int(restored('SELECT count(*) FROM hospitalflow.medicine_batches;'))}
   success=True
  finally:subprocess.run([tool('pg_ctl'),'-D',str(cluster),'-m','fast','-w','stop'],check=True,stdout=subprocess.DEVNULL)
finally:
 seconds=math.ceil(time.perf_counter()-started);evidence='restore-drill-'+str(uuid.uuid4())+'.json';report.update(recovery_seconds=seconds,status='Passed' if success else 'Failed')
 target=ROOT/'.local'/evidence;fd=os.open(target,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
 with os.fdopen(fd,'w') as f:json.dump(report,f,indent=2)
 sql(f"CALL hf_ops.record_restore_drill('{backup['id']}'::uuid,{'true' if success else 'false'},'{evidence}',{seconds});")
print('PASS: recorded backup restored in an isolated password-protected PostgreSQL cluster; all integrity checks passed.')
print('Restore evidence recorded. Observed local recovery seconds:',seconds)
