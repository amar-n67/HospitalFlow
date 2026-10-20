"""Hospital isolation, referral ownership and retained cross-hospital patient history."""
import datetime as dt,uuid,concurrent.futures

def check_hospital_network(base,sql,Client,password):
    admin=Client(base);admin.login();admin.hospital='H-0001'
    directory=admin.request('/api/network')
    assert len(directory['hospitals'])>=21 and sum(h['isDemo'] for h in directory['hospitals'])==20
    assert all(h['address'] and h['city'] and h['postalCode'] for h in directory['hospitals'])
    assert len([d for d in directory['providers'] if d['hospitalId']!='H-0001'])>=40
    doctor=Client(base);doctor.login('doctor');doctor.hospital='H-0001'
    doctor.hospital='H-0002';doctor.request('/api/state',expected=403);doctor.hospital='H-0001'
    doctor.request('/api/network/access',expected=403)
    source=admin.request('/api/state');patient=next(p for p in source['patients'] if p.get('email')=='patient.changed@example.test');pid=patient['id']
    old_appointments=[a['id'] for a in source['appointments'] if a['patientId']==pid];assert old_appointments
    # Register a Doctor at a different hospital through the normal registration route.
    admin.hospital='H-0002';assert admin.request('/api/state')['patients']==[]
    person={'name':'Boundary Clinician','email':'boundary.clinician@example.test','mobile':'9000055522','dob':'1985-02-01','sex':'Other','role':'Doctor','department':'General Medicine','password':'Cedar!928','start':'09:00','end':'17:00','jobTitle':'Hospital doctor'}
    result=admin.register_staff(person)
    target=Client(base);target.request('/api/login',{'email':person['email'],'password':person['password']});assert target.request('/api/me')['hospitalId']=='H-0002'
    target.request('/api/network/access',expected=403)
    assert all(p['id']==result['reference'] for p in target.request('/api/people'))
    # A local hospital admin cannot promote somebody into global Developer access.
    local_admin={**person,'name':'Boundary Administrator','email':'boundary.admin@example.test','role':'Admin'}
    local=admin.register_staff(local_admin)
    local_client=Client(base);local_client.request('/api/login',{'email':local_admin['email'],'password':person['password']})
    local_client.register_staff({**person,'role':'Developer','email':'blocked.network@example.test'},409)
    assert not local_client.request('/api/me')['canManageNetwork']
    source_doctor=next(u for u in source['users'] if u['email']=='doctor@hospitalflow.local')
    admin.request('/api/network/access',{'userId':source_doctor['id'],'hospitalId':'H-0002','active':True})
    local_client.request('/api/admin/account',{'id':source_doctor['id'],'role':'Admin','active':True,'permissions':[]},409)
    local_client.action('user-status',{'id':source_doctor['id'],'active':False},409)
    target.hospital='H-0001';target.request('/api/state',expected=403);target.hospital='H-0002'
    destination=next(d for d in directory['providers'] if d['hospitalId']=='H-0002')
    body={'patientId':pid,'targetHospitalId':'H-0002','targetDoctorId':destination['id'],'reason':'Synthetic continuity of care handover'}
    key=str(uuid.uuid4());created=doctor.request('/api/network/referrals',body,key=key)
    assert doctor.request('/api/network/referrals',body,key=key)==created
    doctor.request('/api/network/referrals',{**body,'reason':'Different handover'},409,key=key)
    doctor.request('/api/network/referrals',body,409)
    assert target.request('/api/state')['patients']==[]
    incoming=target.request('/api/network')['referrals'];assert len(incoming)==1 and incoming[0]['patientId']==pid
    doctor.request('/api/network/referrals/resolve',{'id':created['reference'],'status':'Accepted','note':'Wrong side'},409)
    target.request('/api/network/referrals/resolve',{'id':created['reference'],'status':'Accepted','note':'Receiving team accepted'})
    target.request('/api/network/referrals/resolve',{'id':created['reference'],'status':'Accepted','note':'Repeated'},409)
    received=target.request('/api/state');assert [p['id'] for p in received['patients']]==[pid]
    assert received['appointments']==[] and received['bills']==[] and received['prescriptions']==[]
    # A new visit belongs to the receiving hospital, while source visits remain unchanged.
    day=dt.datetime.now(dt.timezone(dt.timedelta(hours=5,minutes=30)))+dt.timedelta(days=3)
    at=day.replace(hour=11,minute=0,second=0,microsecond=0).isoformat()
    booked=admin.action('appointment',{'patientId':pid,'doctorId':destination['id'],'at':at,'type':'Follow-up'})
    assert [a['id'] for a in target.request('/api/state')['appointments']]==[booked['reference']]
    assert booked['reference'] not in [a['id'] for a in doctor.request('/api/state')['appointments']]
    def verify_scope(pair):
        client,expected=pair
        for _ in range(6):assert (booked['reference'] in {a['id'] for a in client.request('/api/state')['appointments']})==expected
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(verify_scope,[(doctor,False),(target,True)]))
    target.request('/api/documents/appointment/'+old_appointments[0]+'?mode=download',expected=404)
    doctor.request('/api/documents/appointment/'+booked['reference']+'?mode=download',expected=404)
    target.action('prescription',{'patientId':pid,'medicineId':source['medicines'][0]['id'],'quantity':1,'instructions':'Cross-hospital stock attempt'},403)
    # The patient sees their own retained records across both hospitals, not another patient's referral.
    portal=Client(base);portal.request('/api/login',{'email':patient['email'],'password':'Willow!7'})
    own=portal.request('/api/state');assert set(old_appointments).issubset({a['id'] for a in own['appointments']}) and booked['reference'] not in {a['id'] for a in own['appointments']}
    portal.hospital='H-0002';assert [a['id'] for a in portal.request('/api/state')['appointments']]==[booked['reference']]
    portal.hospital='H-0001'
    history=portal.request('/api/network/patients/'+pid+'/history')
    assert {'H-0001','H-0002'}.issubset({e['hospitalId'] for e in history['events']})
    assert {r['hospitalId'] for r in history['registrations']}=={'H-0001','H-0002'}
    target_history=target.request('/api/network/patients/'+pid+'/history');assert all(e['hospitalId']=='H-0002' for e in target_history['events'])
    other=next(p for p in source['patients'] if p['id']!=pid)
    doctor.request('/api/network/referrals',{**body,'patientId':other['id'],'reason':'Another patient handover'})
    assert all(r['patientId']==pid for r in portal.request('/api/network')['referrals'])
    volunteer=Client(base);volunteer.request('/api/login',{'email':'support.colleague@example.test','password':'Cedar!928'})
    assert volunteer.request('/api/network')['referrals']==[]
    volunteer.request('/api/network/referrals',body,403)
    portal.request('/api/network/referrals',body,403)
    portal.request('/api/network/patients/'+other['id']+'/history',expected=409)
    # Membership revocation takes effect immediately, with history retained.
    admin.request('/api/network/access',{'userId':result['reference'],'hospitalId':'H-0002','active':False})
    target.request('/api/state',expected=403)
    assert sql("SELECT count(*) FROM hospitalflow.appointments WHERE id='"+old_appointments[0]+"';")=='1'
    assert sql("SELECT count(*) FROM hospitalflow.referrals WHERE id='"+created['reference']+"' AND status='Accepted';")=='1'
    assert sql("BEGIN;SET LOCAL hospitalflow.hospital_id='H-0002';SELECT count(*) FROM hospitalflow.appointments WHERE hospital_id='H-0001';ROLLBACK;",user='hospitalflow_app').splitlines()[-2]=='0'
    # First-time portal verification also works for a patient first created outside the original hospital.
    new=admin.action('patient',{'name':'Boundary Recipient','dob':'2000-02-01','sex':'Other','phone':'9000055533','email':'boundary.recipient@example.test','initialPassword':'Cedar!928'})
    first=Client(base);challenge=first.request('/api/login',{'email':'boundary.recipient@example.test','password':'1234'})
    assert challenge['requiresOnboarding']
    first.request('/api/patient/onboarding',{'challenge':challenge['challenge'],'dob':'2000-02-01','password':'Willow!7'})
    first.request('/api/login',{'email':'boundary.recipient@example.test','password':'Willow!7'})
    assert first.request('/api/me')['hospitalId']=='H-0002' and first.request('/api/state')['patients'][0]['id']==new['reference']
    # Restore the original administrator's selection for subsequent existing regression checks.
    admin.hospital='H-0001';admin.request('/api/network/select',{'hospitalId':'H-0001'})
    print('PASS: 21 hospitals/40 demonstration providers, hospital membership isolation, scoped accounts/documents/stock, referral idempotency and recipient acceptance, retained source records, own cross-hospital history, volunteer isolation, immediate revocation and second-hospital patient onboarding.')
