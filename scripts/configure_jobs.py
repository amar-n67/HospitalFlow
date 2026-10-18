#!/usr/bin/env python3
"""Provision the narrow job login, prepare/install user launchd agents, and inspect scheduler state."""
import argparse,json,os,pathlib,plistlib,secrets,subprocess,sys
from local_database_tools import ROOT,settings,tool
parser=argparse.ArgumentParser();parser.add_argument('command',choices=['provision','prepare','install','status','uninstall']);args=parser.parse_args()
folder=ROOT/'.local/jobs';folder.mkdir(exist_ok=True,mode=0o700)
labels=['local.hospitalflow.maintenance','local.hospitalflow.backup']
def private(path,data):
 fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
 with os.fdopen(fd,'wb') as f:f.write(data)
 os.chmod(path,0o600)
def admin(query):
 c=settings();r=subprocess.run([tool('psql'),'-X','-w','-h',c['host'],'-p',str(c['port']),'-U',c.get('owner_user','postgres'),'-d',c['database'],'-v','ON_ERROR_STOP=1','-Atq'],input=query,text=True,capture_output=True,env={**os.environ,'PGPASSWORD':c['owner_password']})
 if r.returncode:raise RuntimeError(r.stderr)
 return r.stdout.strip()
if args.command=='provision':
 c=settings();path=folder/'database.json'
 if path.exists():
  stored=json.loads(path.read_text())
  if (stored['host'],stored['port'],stored['database'])!=(c['host'],c['port'],c['database']):raise SystemExit('Existing job credentials target another database; review configuration before replacing.')
 else:
  if admin("SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='hospitalflow_jobs');")!='f':raise SystemExit('Role hospitalflow_jobs already exists; no existing credentials were changed.')
  password=secrets.token_hex(32)
  admin(f"CREATE ROLE hospitalflow_jobs LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD '{password}'; GRANT hospitalflow_job_runner TO hospitalflow_jobs; GRANT CONNECT ON DATABASE hospitalflow TO hospitalflow_jobs;")
  private(path,json.dumps({'host':c['host'],'port':c['port'],'database':c['database'],'user':'hospitalflow_jobs','password':password},indent=2).encode())
 print('Restricted maintenance login provisioned; credentials remain in ignored owner-readable configuration.')
if args.command in ['prepare','install']:
 for label in labels:
  backup=label.endswith('.backup');script='backup_database.py' if backup else 'job_worker.py'
  spec={'Label':label,'ProgramArguments':[sys.executable,str(ROOT/'scripts'/script)],'WorkingDirectory':str(ROOT),'ProcessType':'Background','StandardOutPath':str(folder/(label+'.log')),'StandardErrorPath':str(folder/(label+'.error.log')),'EnvironmentVariables':{'PATH':'/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin'}}
  if backup:spec['StartCalendarInterval']={'Hour':2,'Minute':15}
  else:spec.update(StartInterval=60,RunAtLoad=True)
  private(folder/(label+'.plist'),plistlib.dumps(spec))
 print('Prepared maintenance (every 60 seconds) and backup (02:15 local system time) agent definitions.')
if args.command=='install':
 if sys.platform!='darwin':raise SystemExit('Use the prepared worker command with systemd/cron/Kubernetes on this OS; launchd installation is macOS-only.')
 dest=pathlib.Path.home()/'Library/LaunchAgents';dest.mkdir(parents=True,exist_ok=True)
 for label in labels:
  target=dest/(label+'.plist')
  if target.exists():
   previous=plistlib.loads(target.read_bytes())
   if previous.get('ProgramArguments')!=plistlib.loads((folder/(label+'.plist')).read_bytes())['ProgramArguments']:raise SystemExit('An existing agent with this label uses another command; refusing to overwrite it.')
   subprocess.run(['launchctl','bootout',f'gui/{os.getuid()}',str(target)],capture_output=True)
  private(target,(folder/(label+'.plist')).read_bytes())
  subprocess.run(['launchctl','bootstrap',f'gui/{os.getuid()}',str(target)],check=True)
 print('User launchd agents installed. They run while this user is logged in; production servers require an always-on service scheduler.')
if args.command in ['status','uninstall']:
 for label in labels:
  if args.command=='status':subprocess.run(['launchctl','print',f'gui/{os.getuid()}/{label}'],check=True)
  else:
   target=pathlib.Path.home()/'Library/LaunchAgents'/(label+'.plist')
   subprocess.run(['launchctl','bootout',f'gui/{os.getuid()}',str(target)],capture_output=True)
   if target.exists() and plistlib.loads(target.read_bytes()).get('Label')==label:target.unlink()
 print('Agent command completed.')
