#!/usr/bin/env python3
"""One bounded maintenance tick. Scheduling belongs to launchd/systemd/Kubernetes, not a web request."""
import json,os,pathlib,subprocess,sys
from local_database_tools import ROOT,tool
path=ROOT/'.local/jobs/database.json'
if not path.exists():raise SystemExit('Job credentials are not provisioned. Run scripts/configure_jobs.py provision.')
c=json.loads(path.read_text())
def execute(query):
 return subprocess.run([tool('psql'),'-X','-w','-h',c['host'],'-p',str(c['port']),'-U',c['user'],'-d',c['database'],'-v','ON_ERROR_STOP=1','-Atq'],input=query,text=True,capture_output=True,env={**os.environ,'PGPASSWORD':c['password'],'PGAPPNAME':'HospitalFlow maintenance worker','PGCONNECT_TIMEOUT':'10'})
r=execute("CALL hf_ops.worker_heartbeat('maintenance','Started'); SET statement_timeout='45s'; CALL hf_ops.run_due_jobs(8); CALL hf_ops.worker_heartbeat('maintenance','Succeeded');")
if r.returncode:
 execute("CALL hf_ops.worker_heartbeat('maintenance','Failed');")
 print('HospitalFlow maintenance tick failed. Review database job history and connectivity; no credentials or payloads are logged.',file=sys.stderr)
 raise SystemExit(1)
print('HospitalFlow maintenance tick completed.')
