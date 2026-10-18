#!/usr/bin/env python3
"""Provision a dedicated, password-authenticated local PostgreSQL cluster. Existing DBs are untouched."""
import argparse, getpass, json, os, pathlib, secrets, shutil, socket, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
LOCAL=ROOT/'.local'; CLUSTER=LOCAL/'postgres'; CONFIG=LOCAL/'database.json'
parser=argparse.ArgumentParser();parser.add_argument('command',choices=['setup','start','stop','migrate','status']);parser.add_argument('--import-legacy');args=parser.parse_args()
def tool(name):
    candidate=pathlib.Path('/opt/homebrew/opt/postgresql@17/bin')/name
    value=str(candidate) if candidate.exists() else shutil.which(name)
    if not value:raise SystemExit(f'{name} is required. Install PostgreSQL 17 or newer.')
    return value
def run(argv,**kw):return subprocess.run(argv,check=True,**kw)
def private(path,content):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    with os.fdopen(fd,'w') as f:f.write(content)
    os.chmod(path,0o600)
if args.command=='setup':
    LOCAL.mkdir(exist_ok=True,mode=0o700)
    if CONFIG.exists():raise SystemExit('Local database already configured. Use start, migrate or status.')
    port=55432
    with socket.socket() as probe:probe.bind(('127.0.0.1',port))
    owner=secrets.token_hex(32);runtime=secrets.token_hex(32)
    with tempfile.NamedTemporaryFile(mode='w',dir=LOCAL) as pw:
        pw.write(owner+'\n');pw.flush()
        run([tool('initdb'),'-D',str(CLUSTER),'-U','hospitalflow_owner','--auth-local=scram-sha-256','--auth-host=scram-sha-256','--pwfile',pw.name,'--encoding=UTF8','--no-locale'],stdout=subprocess.DEVNULL)
    with open(CLUSTER/'postgresql.conf','a') as f:f.write(f"\nlisten_addresses = '127.0.0.1'\nport = {port}\npassword_encryption = 'scram-sha-256'\nunix_socket_directories = '{LOCAL}'\n")
    run([tool('pg_ctl'),'-D',str(CLUSTER),'-l',str(LOCAL/'postgres.log'),'-w','start'],stdout=subprocess.DEVNULL)
    settings={'host':'127.0.0.1','port':port,'database':'hospitalflow','owner_password':owner,'runtime_password':runtime}
    private(CONFIG,json.dumps(settings,indent=2))
    sql=f"CREATE ROLE hospitalflow_app LOGIN PASSWORD '{runtime}';\nCREATE DATABASE hospitalflow OWNER hospitalflow_owner;\nREVOKE ALL ON DATABASE hospitalflow FROM PUBLIC;\nGRANT CONNECT,TEMP ON DATABASE hospitalflow TO hospitalflow_app;\n"
    run([tool('psql'),'-X','-w','-h','127.0.0.1','-p',str(port),'-U','hospitalflow_owner','-d','postgres','-v','ON_ERROR_STOP=1'],input=sql,text=True,env={**os.environ,'PGPASSWORD':owner},stdout=subprocess.DEVNULL)
    private(ROOT/'HospitalFlow/appsettings.Local.json',json.dumps({'ConnectionStrings':{'HospitalFlow':f'Host=127.0.0.1;Port={port};Database=hospitalflow;Username=hospitalflow_app;Password={runtime};SSL Mode=Disable;Include Error Detail=false'},'Database':{'SeedDemo':False}},indent=2))
    print(f'Dedicated HospitalFlow database created on 127.0.0.1:{port}. Credentials stored in ignored, owner-readable local configuration files.')
else:
    if not CONFIG.exists():raise SystemExit('Run setup first.')
    conf=json.loads(CONFIG.read_text())
    if not conf.get('managed_cluster',True) and args.command in ('start','stop','status'):
        if args.command=='stop':raise SystemExit('This PostgreSQL server is managed externally. HospitalFlow will not stop your shared database service.')
        run([tool('pg_isready'),'-h',conf['host'],'-p',str(conf['port']),'-d',conf['database']])
        raise SystemExit(0)
    if args.command=='start':
        status=subprocess.run([tool('pg_ctl'),'-D',str(CLUSTER),'status'],stdout=subprocess.DEVNULL)
        if status.returncode!=0:run([tool('pg_ctl'),'-D',str(CLUSTER),'-l',str(LOCAL/'postgres.log'),'-w','start'])
    if args.command=='stop':run([tool('pg_ctl'),'-D',str(CLUSTER),'-m','fast','-w','stop'])
    if args.command=='status':run([tool('pg_ctl'),'-D',str(CLUSTER),'status'])
    if args.command=='migrate':
        connection=f"Host={conf['host']};Port={conf['port']};Database={conf['database']};Username={conf.get('owner_user','hospitalflow_owner')};Password={conf['owner_password']}"
        env={**os.environ,'ConnectionStrings__HospitalFlow':connection,'ASPNETCORE_ENVIRONMENT':'Development'}
        command=['dotnet','run','--project',str(ROOT/'HospitalFlow'),'--no-build','--no-restore','--no-launch-profile','--','--migrate']
        if args.import_legacy:command+=['--import-legacy',str(pathlib.Path(args.import_legacy).resolve())]
        run(command,env=env)
        # The application cannot create/alter schema or change ledgers. Trigger functions are narrowly scoped SECURITY DEFINER.
        sql=(ROOT/'HospitalFlow/Database/grant_operations.sql').read_text()+'\n'+(ROOT/'HospitalFlow/Database/grant_runtime.sql').read_text()
        run([tool('psql'),'-X','-w','-h',conf['host'],'-p',str(conf['port']),'-U',conf.get('owner_user','hospitalflow_owner'),'-d',conf['database'],'-v','ON_ERROR_STOP=1'],input=sql,text=True,env={**os.environ,'PGPASSWORD':conf['owner_password']},stdout=subprocess.DEVNULL)
        print('Migration complete. Runtime account has no schema ownership or ledger update/delete privileges.')
