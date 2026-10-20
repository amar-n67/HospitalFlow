#!/usr/bin/env python3
"""Production-storage integration suite in a disposable PostgreSQL cluster; never reads existing DBs."""
import sys, ssl, json, os, pathlib, shutil, socket, subprocess, tempfile, time, uuid
from smoke import Client, PASSWORD, ROOT, run

def port():
    with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]

if __name__=='__main__':
    bindir=pathlib.Path('/opt/homebrew/opt/postgresql@17/bin')
    def tool(name):return str(bindir/name) if (bindir/name).exists() else shutil.which(name) or name
    with tempfile.TemporaryDirectory(prefix='hospitalflow-pg-') as folder:
        db=folder+'/db';dbport=port();webport=port();base=f'http://127.0.0.1:{webport}'
        subprocess.run([tool('initdb'),'-D',db,'-U','hospitalflow_owner','--auth=trust','--no-locale','--encoding=UTF8'],check=True,stdout=subprocess.DEVNULL)
        subprocess.run([tool('pg_ctl'),'-D',db,'-l',folder+'/postgres.log','-o',f'-h 127.0.0.1 -p {dbport} -k {folder}','-w','start'],check=True,stdout=subprocess.DEVNULL)
        processes=[]
        def sql(text,user='hospitalflow_owner',ok=True,database='postgres'):
            result=subprocess.run([tool('psql'),'-X','-w','-h','127.0.0.1','-p',str(dbport),'-U',user,'-d',database,'-v','ON_ERROR_STOP=1','-At'],input=text,text=True,capture_output=True)
            assert (result.returncode==0)==ok,result.stderr
            return result.stdout.strip()
        dll=str(ROOT/'HospitalFlow/bin/Debug/net10.0/HospitalFlow.dll')
        owner=f'Host=127.0.0.1;Port={dbport};Database=postgres;Username=hospitalflow_owner;Pooling=false'
        env={**os.environ,'HOSPITALFLOW_ADMIN_PASSWORD':PASSWORD,'ASPNETCORE_ENVIRONMENT':'Development','ConnectionStrings__HospitalFlow':owner,'Database__SeedDemo':'true','Mail__PickupDirectory':folder+'/mail','Sms__PickupDirectory':folder+'/sms'}
        def launch(url,environment,tls_context=None):
            log=open(folder+f'/app-{len(processes)}.log','w+')
            p=subprocess.Popen(['dotnet',dll,'--urls',url,'--contentRoot',str(ROOT/'HospitalFlow')],env=environment,stdout=log,stderr=subprocess.STDOUT);processes.append((p,log))
            for _ in range(200):
                try:Client(url,tls_context).request('/api/health');return p
                except Exception:
                    if p.poll() is not None:
                        log.flush();log.seek(0);raise RuntimeError(log.read())
                    time.sleep(.1)
            raise RuntimeError('Timed out starting application')
        try:
            if '--schema-installer' in sys.argv:
                sql((ROOT/'HospitalFlow/Database/hospitalflow_schema.sql').read_text())
            for _ in range(2):
                migrate=subprocess.run(['dotnet',dll,'--contentRoot',str(ROOT/'HospitalFlow'),'--migrate'],env=env,text=True,capture_output=True)
                assert migrate.returncode==0,migrate.stdout+migrate.stderr
            sql('CREATE ROLE hospitalflow_app LOGIN;')
            sql((ROOT/'HospitalFlow/Database/grant_runtime.sql').read_text())
            runtime=owner.replace('Username=hospitalflow_owner','Username=hospitalflow_app')
            runtime_env={**env,'ConnectionStrings__HospitalFlow':runtime,'Database__SeedDemo':'false'}
            p=launch(base,runtime_env)
            run(base)
            c=Client(base);c.login()
            assert c.request('/api/health')['storage']=='PostgreSQL · relational'
            tables=sql("SELECT count(*) FROM information_schema.tables WHERE table_schema='hospitalflow' AND table_type='BASE TABLE';")
            assert int(tables)>=24,tables
            assert sql('SELECT count(*) FROM hospitalflow.patients;')=='9'
            assert int(sql('SELECT count(*) FROM hospitalflow.schema_versions;'))==len(list((ROOT/'HospitalFlow/Database/Migrations').glob('*.sql')))
            assert int(sql('SELECT count(*) FROM hospitalflow.bed_assignments;'))>=6
            assert sql("SELECT count(*) FROM hospitalflow.medicine_batches m WHERE quantity<>(SELECT sum(quantity) FROM hospitalflow.stock_movements WHERE medicine_id=m.id);")=='0'
            # Runtime cannot alter schemas, logs, posted charges or payments.
            sql('CREATE TABLE hospitalflow.not_allowed(id integer);',user='hospitalflow_app',ok=False)
            for ledger in ['activity_log','row_history','stock_movements','bill_lines','payments']:
                sql(f'DELETE FROM hospitalflow.{ledger};',user='hospitalflow_app',ok=False)
            sql("UPDATE hospitalflow.activity_log SET actor='tampered';",ok=False)
            sql("INSERT INTO hospitalflow.payments(id,bill_id,amount,method,at) VALUES('BAD','missing',10,'Cash',now());",ok=False)
            sql("INSERT INTO hospitalflow.payments(id,bill_id,amount,method,at) VALUES('OVER','INV-1002',999999,'Cash',now());",ok=False)
            sql("UPDATE hospitalflow.medicine_batches SET quantity=-1 WHERE id='MED-01';",ok=False)
            sql("UPDATE hospitalflow.medicine_batches SET quantity=999 WHERE id='MED-01';",ok=False)
            sql("UPDATE hospitalflow.beds SET status='Available' WHERE id='B-01';",ok=False)
            # Repeated payment with one key is committed once, including across instances.
            key=str(uuid.uuid4());body={'id':'INV-1002','amount':10,'method':'Cash'}
            c.action('payment',body,key=key)
            second_base=f'http://127.0.0.1:{port()}';second=launch(second_base,runtime_env)
            c2=Client(second_base);c2.login();c2.action('payment',body,key=key)
            assert sql("SELECT sum(amount) FROM hospitalflow.payments WHERE bill_id='INV-1002';")=='10.00'
            c2.action('payment',{**body,'amount':11},expected=409,key=key)
            # Database sessions and keys survive a process restart.
            p.terminate();p.wait(timeout=10);p=launch(base,runtime_env)
            assert c.request('/api/me')['role']=='Admin'
            assert int(sql('SELECT count(*) FROM hospitalflow.sessions;'))>0
            assert int(sql('SELECT count(*) FROM hospitalflow.data_protection_keys;'))>0
            # Page activity and exports are stored; rejected operations retain correlation IDs.
            c.request('/api/activity',{'event':'page-view','reference':'beds'})
            c.request('/api/activity',{'event':'report-export','reference':'beds'})
            c.request('/api/activity',{'event':'record-view','entity':'patient','reference':'HF-1001'})
            unauthorized=Client(base);unauthorized.login('reception');unauthorized.request('/api/activity',{'event':'record-view','entity':'invoice','reference':'INV-1002'},403)
            c.request('/api/notifications')
            assert int(sql("SELECT count(*) FROM hospitalflow.notifications WHERE resolved_at IS NULL;"))>0
            log=c.request('/api/activity?limit=500')
            assert any(e['action']=='page-view' for e in log)
            assert any(e['action']=='request-complete' and e['statusCode']==409 and e['correlationId'] for e in log)
            assert any(e['action']=='login' and e['outcome']=='Rejected' for e in log)
            assert PASSWORD not in json.dumps(log)
            # Master data and patient edits are relational and audited.
            pat=next(x for x in c.request('/api/state')['patients'] if x['name']=='Synthetic Test Patient')
            c.action('patient-update',{'id':pat['id'],'name':pat['name'],'dob':pat['dob'],'sex':pat['sex'],'phone':'9000098765'})
            assert sql("SELECT phone FROM hospitalflow.patients WHERE name='Synthetic Test Patient';")=='9000098765'
            c.action('bed',{'id':'TEST-BED','ward':'Test ward','category':'General'})
            assert sql("SELECT status FROM hospitalflow.beds WHERE id='TEST-BED';")=='Available'
            from enterprise_database import check_database
            check_database(sql,c)
            # Backup/restore uses an empty disposable recovery database.
            dump=folder+'/recovery.dump'
            subprocess.run([tool('pg_dump'),'-h','127.0.0.1','-p',str(dbport),'-U','hospitalflow_owner','-d','postgres','-Fc','--no-owner','--no-acl','-f',dump],check=True)
            sql('CREATE DATABASE hospitalflow_recovery;')
            subprocess.run([tool('pg_restore'),'-h','127.0.0.1','-p',str(dbport),'-U','hospitalflow_owner','-d','hospitalflow_recovery','--no-owner','--no-acl','--exit-on-error',dump],check=True)
            sql((ROOT/'HospitalFlow/Database/grant_operations.sql').read_text()+'\n'+(ROOT/'HospitalFlow/Database/grant_runtime.sql').read_text(),database='hospitalflow_recovery')
            assert sql('SELECT count(*) FROM hospitalflow.patients;',database='hospitalflow_recovery')=='9'
            assert sql("SELECT count(*) FROM hf_ops.validate_database() WHERE severity='Error' AND violations>0;",database='hospitalflow_recovery')=='0'
            assert sql("SELECT count(*) FROM hospitalflow.medicine_batches m WHERE quantity<>(SELECT sum(quantity) FROM hospitalflow.stock_movements WHERE medicine_id=m.id);",database='hospitalflow_recovery')=='0'
            from accounts import check_accounts
            check_accounts(base,sql,folder,Client,PASSWORD)
            from patient_portal import check_patient_portal
            check_patient_portal(base,sql,folder,Client,PASSWORD)
            from people import check_people
            check_people(base,sql,Client,PASSWORD)
            from workspaces import check_workspaces
            check_workspaces(base,sql,folder,Client,PASSWORD)
            from documents_and_validation import check_documents_and_validation
            check_documents_and_validation(base,sql,Client,PASSWORD)
            from hospital_network import check_hospital_network
            check_hospital_network(base,sql,Client,PASSWORD)
            from booking import check_booking
            check_booking(base,sql,Client,PASSWORD)
            from department_booking import check_department_booking
            check_department_booking(base,sql,Client,PASSWORD)
            from attendance_approval import check_attendance_approval
            check_attendance_approval(base,sql,Client,PASSWORD)
            from leave_calendar import check_leave_calendar
            check_leave_calendar(base,sql,Client,PASSWORD)
            from role_separation import check_role_separation
            check_role_separation(base,sql,Client,PASSWORD)
            from medication_care import check_medication_care
            check_medication_care(base,sql,Client)
            from first_login import check_first_login
            check_first_login(base,sql,Client)
            from visit_prescriptions import check_visit_prescriptions
            check_visit_prescriptions(base,sql,Client)
            # Disable user invalidates existing database session immediately.
            receptionist=Client(base);receptionist.login('reception')
            rid=next(u['id'] for u in c.request('/api/state')['users'] if 'Reception' in u['permissions'] and u['name']=='Reception Demo')
            c.action('user-status',{'id':rid,'active':False})
            receptionist.request('/api/state',expected=401)
            # Password change invalidates every existing session for that user.
            new_password='Changed-Cedar-2026-For-Test!'
            c.request('/api/account/password',{'currentPassword':PASSWORD,'newPassword':new_password})
            c2.request('/api/state',expected=401)
            c.request('/api/login',{'email':'administrator@hospitalflow.local','password':PASSWORD},401)
            c.request('/api/login',{'email':'administrator@hospitalflow.local','password':new_password})
            # Fresh Production deployment: no demo rows, HTTPS-only cookies and encrypted DB key material.
            cert=folder+'/tls.crt';private_key=folder+'/tls.key';pfx=folder+'/tls.pfx'
            subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=localhost','-addext','subjectAltName=IP:127.0.0.1,DNS:localhost','-keyout',private_key,'-out',cert],check=True,capture_output=True)
            cert_env={**os.environ,'HF_TEST_PFX_PASSWORD':'Temporary-PFX-Test-Password!'}
            subprocess.run(['openssl','pkcs12','-export','-out',pfx,'-inkey',private_key,'-in',cert,'-passout','env:HF_TEST_PFX_PASSWORD'],env=cert_env,check=True,capture_output=True)
            sql('CREATE DATABASE hospitalflow_production_test;')
            prod_owner=owner.replace('Database=postgres','Database=hospitalflow_production_test')
            prod_env={**env,'ASPNETCORE_ENVIRONMENT':'Production','ConnectionStrings__HospitalFlow':prod_owner,'Database__SeedDemo':'false','Bootstrap__Email':'administrator@hospitalflow.local','Bootstrap__Password':PASSWORD,'Accounts__PublicOrigin':'https://localhost','Mail__Smtp__Host':'127.0.0.1','Mail__From':'noreply@example.test'}
            migration=subprocess.run(['dotnet',dll,'--contentRoot',str(ROOT/'HospitalFlow'),'--migrate'],env=prod_env,capture_output=True,text=True)
            assert migration.returncode==0,migration.stderr
            sql((ROOT/'HospitalFlow/Database/grant_runtime.sql').read_text(),database='hospitalflow_production_test')
            prod_runtime=prod_owner.replace('Username=hospitalflow_owner','Username=hospitalflow_app')
            runtime_prod={**prod_env,'Payments__Mode':'Test','ConnectionStrings__HospitalFlow':prod_runtime,'Security__KeyEncryptionCertificate':pfx,'Security__KeyEncryptionCertificatePassword':cert_env['HF_TEST_PFX_PASSWORD'],'Kestrel__Certificates__Default__Path':pfx,'Kestrel__Certificates__Default__Password':cert_env['HF_TEST_PFX_PASSWORD']}
            prod_url=f'https://127.0.0.1:{port()}';tls_context=ssl.create_default_context(cafile=cert)
            launch(prod_url,runtime_prod,tls_context)
            prod=Client(prod_url,tls_context);prod.login()
            assert all(cookie.secure for cookie in prod.jar)
            assert prod.request('/api/state')['patients']==[]
            assert prod.request('/api/booking')['paymentMode']=='Disabled'
            assert len(prod.request('/api/state')['users'])==1
            assert sql("SELECT bool_and(xml LIKE '%encryptedSecret%') FROM hospitalflow.data_protection_keys;",database='hospitalflow_production_test')=='t'
            without_certificate={**prod_env,'ConnectionStrings__HospitalFlow':prod_runtime}
            refused=subprocess.run(['dotnet',dll,'--contentRoot',str(ROOT/'HospitalFlow')],env=without_certificate,capture_output=True,text=True)
            assert refused.returncode!=0 and 'Production requires' in refused.stderr
            print('PASS: fresh Production bootstrap, HTTPS with validated test certificate, Secure session cookie, encrypted database-held keys, no demo data and missing-certificate startup refusal.')
            print('PASS: normalized tables, repeatable migrations, limited runtime grants, immutable ledgers, FK/check/deferred constraints, stock reconciliation, durable bed history, cross-instance payment idempotency, persisted sessions, notifications, access/rejection logging, user revocation password changes, patient updates, bed creation and backup/restore.')
        except Exception:
            for process,log in processes:
                log.flush();log.seek(0);print(log.read()[-6000:])
            raise
        finally:
            for process,log in processes:
                if process.poll() is None:process.terminate();process.wait(timeout=10)
                log.close()
            subprocess.run([tool('pg_ctl'),'-D',db,'-m','fast','-w','stop'],check=True,stdout=subprocess.DEVNULL)
