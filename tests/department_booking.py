"""Network hospital booking and direct doctor department boundaries."""
import datetime as dt,uuid

def check_department_booking(base,sql,Client,password):
    admin=Client(base);admin.login();admin.hospital='H-0001'
    doctor=Client(base);doctor.request('/api/login',{'email':'booking.doctor@example.test','password':'Cedar!928'});doctor.hospital='H-0001'
    portal=Client(base);portal.request('/api/login',{'email':'patient.changed@example.test','password':'Willow!7'});portal.hospital='H-0001'
    pid=portal.request('/api/me')['patientId'];own=doctor.request('/api/me')['profile']['doctorId']
    state=admin.request('/api/state');other=next(d for d in state['doctors'] if d['department']!='General Medicine')
    day=(dt.datetime.now(dt.timezone(dt.timedelta(hours=5,minutes=30)))+dt.timedelta(days=25)).date().isoformat()
    def slots(client,doc):return client.request(f'/api/booking/slots?doctorId={doc}&day={day}')
    assert all(d['department']=='General Medicine' for d in doctor.request('/api/booking')['data']['doctors'])
    assert slots(doctor,other['id'])==[]
    at=slots(admin,other['id'])[0]
    payload={'id':str(uuid.uuid4()),'patientId':pid,'doctorId':other['id'],'at':at,'method':'Cash','type':'Consultation'}
    doctor.request('/api/booking/reserve',payload,409) # slot preview rejects foreign department
    # Native legacy booking cannot bypass the department guard either.
    sql("BEGIN;SET LOCAL hospitalflow.actor_id='"+doctor.request('/api/me')['id']+"';INSERT INTO hospitalflow.appointments(id,patient_id,doctor_id,at,type,status) VALUES('DEPARTMENT-BYPASS','"+pid+"','"+other['id']+"','"+at+"','Consultation','Scheduled');COMMIT;",user='hospitalflow_app',ok=False)
    own_at=slots(doctor,own)[0]
    reservation=doctor.request('/api/booking/reserve',{**payload,'id':str(uuid.uuid4()),'doctorId':own,'at':own_at})['reference']
    own_app=doctor.request('/api/booking/pay',{'id':reservation,'confirmed':True})['reference']
    doctor.request('/api/booking/reschedule',{'appointmentId':own_app,'doctorId':other['id'],'at':at},409)
    profile=next(p for p in admin.request('/api/people') if p['id']==doctor.request('/api/me')['id'])
    doctor.request('/api/people/update',{'id':profile['id'],'role':'Doctor','name':profile['name'],'email':profile['email'],'mobile':'9000066611','dob':'1980-01-01','sex':'Other','department':other['department'],'jobTitle':'Doctor','start':'09:00','end':'17:00'},409)
    # Same-hospital cross-department doctor referrals are allowed; no appointment or payment is fabricated.
    referral={'patientId':pid,'targetHospitalId':'H-0001','targetDoctorId':other['id'],'reason':'Specialist assessment in another department'}
    saved=doctor.request('/api/network/referrals',referral)
    assert any(r['id']==saved['reference'] for r in doctor.request('/api/network')['referrals'])
    doctor.request('/api/network/referrals',{**referral,'targetDoctorId':''},409)
    doctor.request('/api/network/referrals',{**referral,'targetDoctorId':own},409)
    # Patients select another network hospital without gaining access to anyone else's rows.
    before=sql("SELECT count(*) FROM hospitalflow.patients;")
    portal.request('/api/booking/hospital',{'hospitalId':'H-0003'});portal.hospital='H-0003'
    assert portal.request('/api/me')['hospitalId']=='H-0003'
    ownstate=portal.request('/api/state');assert [p['id'] for p in ownstate['patients']]==[pid] and not ownstate['appointments']
    providers=portal.request('/api/booking')['data']['doctors'];assert len(providers)>=2
    chosen=providers[0];at=slots(portal,chosen['id'])[0]
    b=portal.request('/api/booking/reserve',{'id':str(uuid.uuid4()),'doctorId':chosen['id'],'at':at,'method':'UPI','type':'Consultation'})['reference']
    aid=portal.request('/api/booking/pay',{'id':b,'confirmed':True})['reference']
    assert any(a['id']==aid for a in portal.request('/api/state')['appointments'])
    history=portal.request('/api/network/patients/'+pid+'/history');assert any(e['reference']==aid and e['hospitalId']=='H-0003' for e in history['events'])
    assert sql("SELECT count(*) FROM hospitalflow.patients;")==before
    doctor.request('/api/booking/hospital',{'hospitalId':'H-0003'},403)
    # Explicitly revoked hospital access cannot be restored by a patient booking request.
    account=portal.request('/api/me')['id'];admin.request('/api/network/access',{'userId':account,'hospitalId':'H-0003','active':False})
    portal.hospital='H-0001';portal.request('/api/booking/hospital',{'hospitalId':'H-0003'},403)
    portal.request('/api/booking/hospital',{'hospitalId':'H-0001'})
    print('PASS: hospital/department provider filtering, doctor department enforcement, same-hospital specialist referrals, patient network booking without duplicate identity, retained history and revoked-access protection.')
