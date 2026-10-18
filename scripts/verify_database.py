#!/usr/bin/env python3
"""Validate installed database contracts and migration checksums with no credential/record disclosure."""
import hashlib,json,os,subprocess
from local_database_tools import ROOT,settings,tool
c=settings()
def query(statement):
 r=subprocess.run([tool('psql'),'-X','-w','-h',c['host'],'-p',str(c['port']),'-U',c.get('runtime_user','hospitalflow_app'),'-d',c['database'],'-v','ON_ERROR_STOP=1','-Atq'],input=statement,text=True,capture_output=True,env={**os.environ,'PGPASSWORD':c['runtime_password']})
 if r.returncode:raise RuntimeError(r.stderr)
 return r.stdout.strip()
versions=json.loads(query("SELECT json_object_agg(version,checksum) FROM hospitalflow.schema_versions;"))
for path in sorted((ROOT/'HospitalFlow/Database/Migrations').glob('*.sql')):
 matches=[value for name,value in versions.items() if name.endswith('.'+path.name)]
 if matches!=[hashlib.sha256(path.read_bytes()).hexdigest().upper()]:raise RuntimeError('Migration missing or checksum differs: '+path.name)
checks=json.loads(query("SELECT json_agg(c) FROM hf_ops.validate_database()c;"))
objects=json.loads(query("SELECT json_object_agg(object_type,n) FROM(SELECT object_type,count(*)n FROM hf_ops.object_inventory GROUP BY object_type)c;"))
for check in checks:
 print(check['severity'],check['check_name'],check['violations'])
errors=[x for x in checks if x['severity']=='Error' and x['violations']]
print('Installed objects:',json.dumps(objects,sort_keys=True))
print('Migration checksums verified:',len(versions))
if errors:raise SystemExit('Database integrity/security checks failed.')
result={'database':c['database'],'host':c['host'],'port':c['port'],'objects':objects,'checks':checks,'migration_count':len(versions)}
p=ROOT/'.local/database-validation.json';fd=os.open(p,os.O_CREAT|os.O_TRUNC|os.O_WRONLY,0o600)
with os.fdopen(fd,'w') as f:json.dump(result,f,indent=2)
print('All integrity/security error checks passed. Warnings require environment-specific operational evidence.')
