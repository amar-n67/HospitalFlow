#!/usr/bin/env python3
"""Compile SQL migrations in a disposable cluster without waiting for an application rebuild."""
import json,pathlib,socket,subprocess,tempfile
from postgres import ROOT
BIN=pathlib.Path('/opt/homebrew/opt/postgresql@17/bin')
with tempfile.TemporaryDirectory(prefix='hospitalflow-sql-') as folder:
 with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
 db=folder+'/data'
 subprocess.run([str(BIN/'initdb'),'-D',db,'-U','hospitalflow_owner','--auth=trust','--encoding=UTF8','--no-locale'],check=True,stdout=subprocess.DEVNULL)
 subprocess.run([str(BIN/'pg_ctl'),'-D',db,'-l',folder+'/server.log','-o',f'-h 127.0.0.1 -p {port} -k {folder}','-w','start'],check=True,stdout=subprocess.DEVNULL)
 try:
  def sql(text,user='hospitalflow_owner',ok=True,database='postgres'):
   r=subprocess.run([str(BIN/'psql'),'-X','-w','-h','127.0.0.1','-p',str(port),'-U',user,'-d',database,'-v','ON_ERROR_STOP=1','-Atq'],input=text,text=True,capture_output=True)
   if (r.returncode==0)!=ok:raise RuntimeError(r.stderr)
   return r.stdout.strip()
  sql('CREATE SCHEMA hospitalflow;CREATE TABLE hospitalflow.schema_versions(version text PRIMARY KEY,checksum text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now());')
  for p in sorted((ROOT/'HospitalFlow/Database/Migrations').glob('*.sql')):
   try:sql('BEGIN;'+p.read_text()+'\nCOMMIT;');print('COMPILED',p.name)
   except Exception as e:raise RuntimeError(p.name+': '+str(e))
  sql("CREATE ROLE hospitalflow_app LOGIN;")
  sql((ROOT/'HospitalFlow/Database/grant_runtime.sql').read_text())
  sql("""BEGIN;
  INSERT INTO hospitalflow.users(id,name,email,role,password_hash) SELECT name,name,lower(name)||'@hospitalflow.local',name,'fixture-hash' FROM hospitalflow.roles;
  INSERT INTO hospitalflow.users(id,name,email,role,password_hash) SELECT name,name,lower(name)||'@hospitalflow.local','User','fixture-hash' FROM unnest(ARRAY['Reception','Doctor','Nurse','Pharmacist','Billing']) name ON CONFLICT(id) DO NOTHING;
  INSERT INTO hospitalflow.user_permissions SELECT id,id FROM hospitalflow.users WHERE role='User' AND id IN ('Reception','Doctor','Nurse','Pharmacist','Billing');
  INSERT INTO hospitalflow.departments(name) VALUES('General Medicine') ON CONFLICT DO NOTHING;
  INSERT INTO hospitalflow.doctors(id,name,department,start,"end") VALUES('DR-01','Test doctor','General Medicine','08:00','18:00');
  INSERT INTO hospitalflow.patients(id,name,dob,sex,phone,created) SELECT 'HF-'||(1000+n),'Patient '||n,'1990-01-01'::date+n,'Other','900000000'||n,now() FROM generate_series(1,9)n;
  INSERT INTO hospitalflow.wards(name) VALUES('General Ward');
  INSERT INTO hospitalflow.beds(id,ward,category,status) SELECT 'B-'||lpad(n::text,2,'0'),'General Ward','General','Available' FROM generate_series(1,12)n;
  INSERT INTO hospitalflow.medicine_batches VALUES('MED-01','Medicine A','A-01',current_date+365,235,20,2.5),('MED-02','Medicine B','B-01',current_date+365,18,30,8);
  INSERT INTO hospitalflow.stock_movements VALUES('OPEN-A','MED-01',235,'Test baseline',now()),('OPEN-B','MED-02',18,'Test baseline',now());
  COMMIT;""")
  class DatabaseClient:
   def request(self,path):
    return {'bills':json.loads(sql("SELECT COALESCE(json_agg(json_build_object('id',id,'paid',paid,'balance',balance)),'[]'::json) FROM hospitalflow.invoice_balances;"))}
  from enterprise_database import check_database
  check_database(sql,DatabaseClient())
  submitted=json.loads(sql("BEGIN;SET LOCAL hospitalflow.actor_id='Reception';SELECT hf_api.booking_command('attendance','{\"status\":\"Present\"}'::jsonb,false);COMMIT;",user='hospitalflow_app'))
  assert submitted['state']=='Pending'
  outcome=sql("BEGIN;SET LOCAL hospitalflow.actor_id='Admin';SELECT hf_api.booking_command('review-attendance',jsonb_build_object('id','"+submitted['reference']+"','status','Approved'),false);COMMIT;",user='hospitalflow_app')
  assert json.loads(outcome)['state']=='Approved'
  assert sql("SELECT count(*) FROM hospitalflow.activity_log WHERE action='attendance-approved' AND reference='"+submitted['reference']+"';")=='1'
  print('PASS: native attendance approval and explicit approval-outcome audit evidence.')

 finally:subprocess.run([str(BIN/'pg_ctl'),'-D',db,'-m','fast','-w','stop'],check=True,stdout=subprocess.DEVNULL)
