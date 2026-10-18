"""Database-native acceptance scenarios, executed only through the disposable integration harness."""
import concurrent.futures,datetime,hashlib,json,uuid

def check_database(sql,client):
    def quoted(v):return "'"+str(v).replace("'","''")+"'"
    def actor_id(role='Admin'):
        return sql("SELECT id FROM hospitalflow.users u WHERE active AND (role="+quoted(role)+" OR EXISTS(SELECT 1 FROM hospitalflow.user_permissions p WHERE p.user_id=u.id AND p.permission="+quoted(role)+")) ORDER BY created_at,id LIMIT 1;")
    def context(statement,role='Admin',ok=True):
        return sql("BEGIN;SELECT set_config('hospitalflow.actor_id',"+quoted(actor_id(role))+",true),set_config('hospitalflow.correlation_id','enterprise-database-test',true);"+statement+";COMMIT;",user='hospitalflow_app',ok=ok)
    def command(action,payload,role='Admin',ok=True,key=None):
        body=json.dumps(payload,separators=(',',':'));fingerprint=hashlib.sha256(body.encode()).hexdigest()
        out=context("SELECT json_build_object('reference',hf_api.execute("+quoted(action)+","+quoted(body)+"::jsonb,"+quoted(key or uuid.uuid4())+"::uuid,"+quoted(fingerprint)+"))",role,ok)
        if not ok:return None
        return next(json.loads(line)['reference'] for line in out.splitlines() if line.startswith('{'))
    sql("SELECT hf_api.execute('bill','{}'::jsonb,gen_random_uuid(),repeat('a',64));",user='hospitalflow_app',ok=False)
    command('reverse-payment',{'id':'PAY-1','amount':1,'reason':'Rejected non-supervisor request'},role='Billing',ok=False)
    supplier=command('supplier',{'code':'TEST-SUPPLIER','name':'Synthetic supplier'})
    order=command('purchase-order',{'supplierId':supplier,'lines':[{'medicineId':'MED-02','quantity':10,'unitCost':3}]},role='Pharmacist')
    command('approve-purchase-order',{'id':order})
    line=sql('SELECT id FROM hospitalflow.purchase_order_lines WHERE purchase_order_id='+quoted(order)+'::uuid;')
    command('receive-purchase-order',{'id':order,'reference':'TEST-RECEIPT-A','lines':[{'lineId':line,'quantity':4}]},role='Pharmacist')
    assert sql('SELECT status FROM hospitalflow.purchase_orders WHERE id='+quoted(order)+'::uuid;')=='Partially received'
    command('receive-purchase-order',{'id':order,'reference':'TEST-OVERRECEIPT','lines':[{'lineId':line,'quantity':7}]},role='Pharmacist',ok=False)
    command('receive-purchase-order',{'id':order,'reference':'TEST-RECEIPT-B','lines':[{'lineId':line,'quantity':6}]},role='Pharmacist')
    assert sql('SELECT status FROM hospitalflow.purchase_orders WHERE id='+quoted(order)+'::uuid;')=='Received'
    assert sql("SELECT quantity FROM hospitalflow.medicine_batches WHERE id='MED-02';")=='28'
    rx=command('prescription',{'patientId':'HF-1006','medicineId':'MED-01','quantity':3,'instructions':'Synthetic clinician-entered test instructions'},role='Doctor')
    command('reserve-prescription',{'id':rx},role='Pharmacist')
    hold=command('hold-batch',{'medicineId':'MED-01','reason':'Test quarantine'},role='Pharmacist')
    command('dispense',{'id':rx},role='Pharmacist',ok=False)
    command('release-batch',{'id':hold},role='Pharmacist')
    command('dispense',{'id':rx},role='Pharmacist')
    assert sql('SELECT status FROM hospitalflow.stock_reservations WHERE prescription_id='+quoted(rx)+';')=='Consumed'
    assert sql('SELECT count(*) FROM hospitalflow.prescription_dispensations WHERE prescription_id='+quoted(rx)+';')=='1'
    service=command('service',{'code':'TEST-CONSULT','name':'Test consultation','department':'General Medicine','category':'Consultation'})
    price=command('service-price',{'serviceId':service,'amount':100})
    bill=command('bill',{'patientId':'HF-1006','description':'Test service','amount':40},role='Billing')
    charge=command('service-charge',{'id':bill,'serviceId':service,'quantity':1},role='Billing')
    payment=command('payment',{'id':bill,'amount':20,'method':'Cash'},role='Billing')
    command('reverse-payment',{'id':payment,'amount':5,'reason':'Test partial reversal'})
    command('reverse-payment',{'id':payment,'amount':16,'reason':'Must reject over-reversal'},ok=False)
    assert sql('SELECT paid FROM hospitalflow.invoice_balances WHERE id='+quoted(bill)+';')=='15.00'
    current=next(b for b in client.request('/api/state')['bills'] if b['id']==bill)
    assert current['paid']==15 and current['balance']==125
    command('service-price',{'serviceId':service,'amount':120})
    assert sql('SELECT unit_price FROM hospitalflow.invoice_line_context WHERE line_id='+quoted(charge)+';')=='100.00'
    sql('UPDATE hospitalflow.service_prices SET amount=999 WHERE id='+quoted(price)+'::uuid;',ok=False)
    admission=command('admit',{'patientId':'HF-1005','bedId':'B-09','reason':'Test discharge checklist'},role='Nurse')
    task=command('discharge-task',{'admissionId':admission,'code':'CLINICAL-REVIEW'},role='Nurse')
    command('discharge',{'id':admission,'summary':'Synthetic summary'},role='Nurse',ok=False)
    command('complete-discharge-task',{'id':task},role='Nurse')
    command('discharge',{'id':admission,'summary':'Synthetic summary'},role='Nurse')
    assert sql('SELECT count(*) FROM hospitalflow.admission_events WHERE admission_id='+quoted(admission)+';')=='2'
    due=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=7)).isoformat()
    follow={'patientId':'HF-1005','admissionId':admission,'dueAt':due,'doctorId':'DR-01','instructions':'Test follow-up'}
    command('follow-up',follow,role='Doctor',ok=False)
    command('grant-patient-access',{'userId':actor_id('Doctor'),'patientId':'HF-1005','purpose':'Test care relationship','expiresAt':due})
    follow_id=command('follow-up',follow,role='Doctor')
    assert sql('SELECT count(*) FROM hospitalflow.follow_ups;',user='hospitalflow_app')=='0'
    assert '1' in context('SELECT count(*) FROM hospitalflow.follow_ups',role='Doctor').splitlines()
    encounter=sql('SELECT id FROM hospitalflow.encounters WHERE admission_id='+quoted(admission)+';')
    clinical=command('clinical-order',{'encounterId':encounter,'serviceId':service},role='Doctor')
    command('complete-clinical-order',{'id':clinical},role='Doctor')
    contact=command('patient-contact',{'patientId':'HF-1005','name':'Synthetic contact','relationship':'Attendant','phone':'9000022222'},role='Doctor')
    consent=command('patient-consent',{'patientId':'HF-1005','purpose':'Operational follow-up','evidenceReference':'TEST-CONSENT'},role='Doctor')
    command('revoke-consent',{'id':consent},role='Doctor')
    assert sql('SELECT count(*) FROM hospitalflow.patient_contacts;',user='hospitalflow_app')=='0'
    command('staff-member',{'userId':actor_id('Doctor'),'doctorId':'DR-01','employeeNumber':'TEST-EMP-1','department':'General Medicine','jobTitle':'Doctor'})
    command('grant-department',{'userId':actor_id('Doctor'),'department':'General Medicine'})
    command('hospital-profile',{'name':'HospitalFlow isolated test'})
    from zoneinfo import ZoneInfo
    local=(datetime.datetime.now(ZoneInfo('Asia/Kolkata'))+datetime.timedelta(days=9)).replace(hour=9,minute=0,second=0,microsecond=0)
    command('provider-session',{'doctorId':'DR-01','startsAt':local.isoformat(),'endsAt':local.replace(hour=12).isoformat()})
    absence=command('provider-absence',{'doctorId':'DR-01','startsAt':local.replace(hour=10,minute=30).isoformat(),'endsAt':local.replace(hour=11).isoformat(),'reasonCode':'TEST-LEAVE'})
    command('appointment',{'patientId':'HF-1005','doctorId':'DR-01','at':local.replace(hour=13).isoformat(),'type':'Consultation'},role='Reception',ok=False)
    command('appointment',{'patientId':'HF-1005','doctorId':'DR-01','at':local.replace(hour=10,minute=30).isoformat(),'type':'Consultation'},role='Reception',ok=False)
    command('cancel-absence',{'id':absence})
    command('appointment',{'patientId':'HF-1005','doctorId':'DR-01','at':local.replace(hour=10,minute=30).isoformat(),'type':'Consultation'},role='Reception')
    command('grant-patient-access',{'userId':actor_id('Reception'),'patientId':'HF-1005','purpose':'Test follow-up booking','expiresAt':(local+datetime.timedelta(days=1)).isoformat()})
    follow_appointment=command('book-follow-up',{'id':follow_id,'doctorId':'DR-01','at':local.replace(hour=11,minute=30).isoformat()},role='Reception')
    for status in ['Checked in','In consultation','Completed']:command('appointment-status',{'id':follow_appointment,'status':status},role='Reception')
    assert sql('SELECT status FROM hospitalflow.follow_ups WHERE id='+quoted(follow_id)+'::uuid;')=='Completed'
    cancel_rx=command('prescription',{'patientId':'HF-1005','medicineId':'MED-01','quantity':1,'instructions':'Test cancellation'},role='Doctor')
    command('reserve-prescription',{'id':cancel_rx},role='Pharmacist')
    command('cancel-prescription',{'id':cancel_rx},role='Doctor')
    assert sql('SELECT status FROM hospitalflow.stock_reservations WHERE prescription_id='+quoted(cancel_rx)+';')=='Released'
    sql('CALL hf_ops.run_due_jobs(8);',user='hospitalflow_app',ok=False)
    sql('CREATE ROLE test_hospitalflow_job LOGIN IN ROLE hospitalflow_job_runner;')
    # Concurrent scheduler ticks cannot run the same due job twice.
    with concurrent.futures.ThreadPoolExecutor() as pool:
        list(pool.map(lambda _:sql('CALL hf_ops.run_due_jobs(8);',user='test_hospitalflow_job'),range(2)))
    assert sql('SELECT count(*) FROM hf_ops.job_runs;')=='8'
    assert sql("SELECT count(*) FROM hf_ops.job_runs WHERE status='Failed';")=='0'
    assert sql("SELECT count(*) FROM hf_ops.latest_integrity_findings WHERE check_name<>'backup-freshness' AND violations<>0;")=='0'
    sql("UPDATE hf_ops.job_definitions SET next_run_at=now()-interval '1 minute' WHERE name='report-cache';")
    output=sql("BEGIN;DROP MATERIALIZED VIEW hf_reporting.daily_collections;CALL hf_ops.run_due_jobs(1);SELECT status,error_code FROM hf_ops.job_runs ORDER BY started_at DESC LIMIT 1;ROLLBACK;")
    assert 'Failed|42P01' in output,output
    # Lease token validation, retry and crash recovery do not send external messages.
    claim=context("SELECT row_to_json(c) FROM hf_api.claim_outbox(1,30)c")
    event=next(json.loads(line) for line in claim.splitlines() if line.startswith('{'))
    context('CALL hf_api.complete_outbox('+quoted(event['event_id'])+'::uuid,gen_random_uuid(),false,\'TIMEOUT\')',ok=False)
    context('CALL hf_api.complete_outbox('+quoted(event['event_id'])+'::uuid,'+quoted(event['lease_token'])+'::uuid,false,\'TIMEOUT\')')
    assert sql('SELECT status FROM hospitalflow.outbox_delivery WHERE event_id='+quoted(event['event_id'])+'::uuid;')=='Pending'
    sql('UPDATE hospitalflow.outbox_delivery SET status=\'Leased\',lease_token=gen_random_uuid(),lease_until=now()-interval \'1 second\' WHERE event_id='+quoted(event['event_id'])+'::uuid;')
    sql("UPDATE hf_ops.job_definitions SET next_run_at=now()-interval '1 minute' WHERE name='outbox-lease-recovery';CALL hf_ops.run_due_jobs(8);",user='hospitalflow_owner')
    assert sql('SELECT status FROM hospitalflow.outbox_delivery WHERE event_id='+quoted(event['event_id'])+'::uuid;')=='Pending'
    assert sql("SELECT count(*) FROM hf_ops.validate_database() WHERE severity='Error' AND violations>0;")=='0'
    backup=sql('CALL hf_ops.start_backup(NULL);',user='test_hospitalflow_job').splitlines()[0]
    sql("CALL hf_ops.finish_backup("+quoted(backup)+"::uuid,true,'synthetic-test.dump',123,repeat('a',64));",user='test_hospitalflow_job')
    sql('UPDATE hf_ops.backup_runs SET bytes=999 WHERE id='+quoted(backup)+'::uuid;',ok=False)
    sql("CALL hf_ops.record_restore_drill("+quoted(backup)+"::uuid,true,'synthetic procedure test only',1);")
    assert int(sql("SELECT count(*) FROM hf_ops.schema_change_events;"))>0
    assert sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('hf_api','hf_security','hf_ops') AND has_function_privilege('public',p.oid,'EXECUTE');")=='0'
    print('PASS: database-native procurement, over-receipt rejection, reservations/holds, dispense linkage, historical prices, reversals, discharge checklist, scoped RLS, clinical orders, contacts/consents, staff/calendar/follow-up workflows, concurrent jobs, failure/retry evidence and outbox leases.')
