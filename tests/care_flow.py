"""Complete managed admission, per-dose nursing, configured charges and staged discharge."""
import datetime as dt,uuid

def check_care_flow(base,sql,Client):
    admin=Client(base);admin.login();admin.hospital='H-0001'
    doctor=Client(base);doctor.request('/api/login',{'email':'booking.doctor@example.test','password':'Cedar!928'});doctor.hospital='H-0001'
    nurse=Client(base);nurse.login('nurse');nurse.hospital='H-0001'
    other_nurse=Client(base);other_nurse.request('/api/login',{'email':'registered.nurse@example.test','password':'Cedar!928'});other_nurse.hospital='H-0001'
    pharmacy=Client(base);pharmacy.request('/api/login',{'email':'visit.pharmacy@example.test','password':'Cedar!928'});pharmacy.hospital='H-0001'
    patient_data={'name':'Managed Flow Recipient','email':'care.flow.recipient@example.test','phone':'9000044890','dob':'1998-03-04','sex':'Other'}
    pid=admin.action('patient',patient_data)['reference']
    patient=Client(base);challenge=patient.request('/api/login',{'email':patient_data['email'],'password':'1234'})
    patient.request('/api/patient/onboarding',{'challenge':challenge['challenge'],'dob':patient_data['dob'],'password':'Spruce!928'})
    patient.request('/api/login',{'email':patient_data['email'],'password':'Spruce!928'});patient.hospital='H-0001'
    expires=(dt.datetime.now(dt.timezone.utc)+dt.timedelta(days=30)).isoformat()
    for client in [doctor,nurse]:admin.action('grant-patient-access',{'userId':client.request('/api/me')['id'],'patientId':pid,'purpose':'Managed synthetic care','expiresAt':expires})
    def flow(client,action,data,expected=200,key=None):return client.request('/api/care/flow/'+action,data,expected,key=key)
    state=admin.request('/api/state');bed=next(b for b in state['beds'] if b['status']=='Available');today=dt.datetime.now(dt.timezone(dt.timedelta(hours=5,minutes=30))).date()
    rate={'ward':bed['ward'],'effectiveFrom':today.isoformat(),'bedDaily':100,'wardDaily':20,'icuDaily':0,'nursingDaily':30}
    flow(doctor,'rate',rate,403);flow(patient,'rate',rate,403);flow(admin,'rate',rate)
    request={'patientId':pid,'days':5,'ward':bed['ward'],'nurseId':nurse.request('/api/me')['id'],'diagnosis':'Synthetic admission reason','instructions':'Synthetic treatment plan; no clinical advice'}
    flow(admin,'admission-request',request,403)
    key=str(uuid.uuid4());plan=flow(doctor,'admission-request',request,key=key)['reference'];assert flow(doctor,'admission-request',request,key=key)['reference']==plan
    flow(doctor,'admission-request',{**request,'days':6},409,key=key)
    flow(other_nurse,'accept-admission',{'id':plan,'comments':'Wrong assigned nurse'},403)
    flow(nurse,'accept-admission',{'id':plan,'comments':'Accepted synthetic care'})
    flow(nurse,'assign-bed',{'id':plan,'bedId':bed['id'],'confirmedDays':5,'nursingNotes':'Synthetic ward intake'})
    nursing=nurse.request('/api/care/flow');p=next(p for p in nursing['plans'] if p['id']==plan);admission=p['admission_id'];assert p['nurse_name'] and p['status']=='Admitted'
    nurse.action('discharge',{'id':admission,'summary':'Skip approval'},409)
    observation={'admissionId':admission,'healthStatus':'Synthetic stable status','vitals':{'temperatureC':36.7,'pulseBpm':70},'progress':'Synthetic progress','notes':'Synthetic nursing note'}
    flow(patient,'monitor',observation,403);flow(nurse,'monitor',observation)
    flow(nurse,'monitor',{**observation,'vitals':{'pulseBpm':'invalid'}},409)
    flow(nurse,'extend-plan',{'id':plan,'days':7,'instructions':'Bad role'},403)
    flow(doctor,'extend-plan',{'id':plan,'days':7,'instructions':'Updated synthetic plan','comments':'Extend test stay'})
    flow(nurse,'accrue-charges',{'admissionId':admission,'comments':'Recalculate test invoice'})
    sql('SELECT hf_api.accrue_due_care_charges();',user='hospitalflow_app')
    assert sql("SELECT count(*) FROM hospitalflow.care_charge_entries WHERE admission_id='"+admission+"';")=='4'
    assert sql("SELECT sum(amount) FROM hospitalflow.care_charge_entries WHERE admission_id='"+admission+"';")=='150.00'
    encounter=next(e for e in nurse.request('/api/care/flow')['encounters'] if e.get('admission_id')==admission)
    service=admin.action('service',{'code':'CARE-FLOW-LAB','name':'Synthetic laboratory service','category':'Laboratory','department':'General Medicine'})['reference']
    order=flow(doctor,'lab-order',{'encounterId':encounter['id'],'serviceId':service,'comments':'Synthetic test recommendation'})['reference']
    flow(nurse,'complete-lab',{'id':order,'comments':'No configured price'},409)
    admin.action('service-price',{'serviceId':service,'amount':50})
    flow(nurse,'complete-lab',{'id':order,'comments':'Synthetic laboratory test completed'})
    flow(nurse,'complete-lab',{'id':order,'comments':'Duplicate completion'},409)
    assert sql("SELECT count(*) FROM hospitalflow.care_lab_charges WHERE order_id='"+order+"';")=='1'
    own=doctor.request('/api/me')['profile']['doctorId'];day=(today+dt.timedelta(days=60)).isoformat();slot=admin.request('/api/booking/slots?doctorId='+own+'&day='+day)[0]
    hold=admin.request('/api/booking/reserve',{'id':str(uuid.uuid4()),'patientId':pid,'doctorId':own,'at':slot,'method':'QR','type':'Consultation'})['reference']
    appointment=admin.request('/api/booking/pay',{'id':hold,'confirmed':True})['reference']
    admin.action('appointment-status',{'id':appointment,'status':'Checked in'});doctor.action('appointment-status',{'id':appointment,'status':'In consultation'})
    outpatient=next(e for e in nurse.request('/api/care/flow')['encounters'] if e.get('appointment_id')==appointment)
    outpatient_order=flow(doctor,'lab-order',{'encounterId':outpatient['id'],'serviceId':service,'comments':'Synthetic outpatient laboratory recommendation'})['reference']
    flow(doctor,'complete-lab',{'id':outpatient_order,'comments':'Synthetic outpatient test completed'})
    extra=flow(admin,'extra-charge',{'patientId':pid,'category':'Consumables','description':'Synthetic consumable test item','amount':25,'comments':'Synthetic charge'})['reference']
    assert extra
    medicines=[m for m in admin.request('/api/state')['medicines'] if m['quantity']>5][:2]
    batch={'appointmentId':appointment,'items':[{'medicineId':m['id'],'quantity':3,'instructions':'Synthetic medicine instructions '+str(i)} for i,m in enumerate(medicines)],'comments':'Synthetic multi-medicine prescription'}
    key=str(uuid.uuid4());flow(doctor,'prescription-set',batch,key=key);flow(doctor,'prescription-set',batch,key=key)
    rx=[r for r in patient.request('/api/care/medications')['prescriptions'] if r['appointmentId']==appointment];assert len(rx)==2
    for r in rx:
        key=str(uuid.uuid4());flow(patient,'send-pharmacy',{'prescriptionId':r['id'],'comments':'Please fulfill synthetic prescription'},key=key);flow(patient,'send-pharmacy',{'prescriptionId':r['id'],'comments':'Please fulfill synthetic prescription'},key=key)
        pharmacy.action('dispense',{'id':r['id']})
    doses=[]
    for i,r in enumerate(rx):
        d=flow(doctor,'schedule-dose',{'prescriptionId':r['id'],'dose':'Synthetic dose label '+str(i),'quantity':1,'scheduledAt':dt.datetime.now(dt.timezone.utc).isoformat(),'comments':'Synthetic schedule'})['reference'];doses.append(d)
        flow(nurse,'record-dose',{'id':d,'status':'Given' if i==0 else 'Not given','remarks':'Synthetic outcome - no real treatment'})
    patient_flow=patient.request('/api/care/flow');assert all(x['patient_id']==pid for x in patient_flow['events']);assert {d['status'] for d in patient_flow['doses']}=={'Given','Not given'}
    assert any(x['category']=='Laboratory' for x in patient_flow['charges'])
    assert not pharmacy.request('/api/care/flow')['observations'];assert not pharmacy.request('/api/care/flow')['discharges']
    assert any(x['category']=='Consumables' for x in patient.request('/api/care/flow')['charges'])
    prep={'admissionId':admission,'finalCondition':'Synthetic final condition','nurseRemarks':'Synthetic final nursing review'}
    flow(nurse,'prepare-discharge',prep)
    approval={'admissionId':admission,'diagnosis':'Synthetic diagnosis','treatment':'Synthetic treatment description','dischargeMedications':'Synthetic discharge instructions','followUp':'Synthetic follow-up plan','doctorRemarks':'Synthetic approval <script>unsafe</script>'}
    flow(nurse,'approve-discharge',approval,403);flow(admin,'approve-discharge',approval,403);flow(doctor,'approve-discharge',approval)
    flow(nurse,'monitor',{**observation,'notes':'Changed after approval - must require review again'})
    assert next(d for d in nurse.request('/api/care/flow')['discharges'] if d['admission_id']==admission)['approved_at'] is None
    flow(nurse,'finalize-discharge',{'admissionId':admission,'comments':'Must fail without new review'},403)
    flow(doctor,'approve-discharge',approval)
    flow(nurse,'finalize-discharge',{'admissionId':admission,'comments':'Unpaid invoice must block'},409)
    for bill in admin.request('/api/state')['bills']:
        if bill['patientId']==pid and bill['balance']>0:admin.action('payment',{'id':bill['id'],'amount':bill['balance'],'method':'Cash'})
    nurse.action('discharge',{'id':admission,'summary':'Attempt legacy bypass'},409)
    key=str(uuid.uuid4());flow(nurse,'finalize-discharge',{'admissionId':admission,'comments':'Synthetic formalities complete'},key=key);flow(nurse,'finalize-discharge',{'admissionId':admission,'comments':'Synthetic formalities complete'},key=key)
    final=patient.request('/api/care/flow');assert next(a for a in final['admissions'] if a['id']==admission)['status']=='Discharged'
    summary=patient.request('/api/documents/discharge-summary/'+admission+'?mode=download')['html'];assert '&lt;script&gt;' in summary and '<script>unsafe' not in summary and 'Medication administration record' in summary
    pharmacy.request('/api/documents/discharge-summary/'+admission+'?mode=download',expected=403)
    assert next(p for p in final['plans'] if p['id']==plan)['status']=='Discharged'
    assert any(e['activity']=='Discharged' and e['actor_name'] for e in final['events'])
    sql("UPDATE hospitalflow.care_events SET comments='changed' WHERE patient_id='"+pid+"';",ok=False)
    sql("UPDATE hospitalflow.medication_doses SET remarks='changed' WHERE id='"+doses[0]+"';",ok=False)
    doctor_id=doctor.request('/api/me')['id']
    denied=sql("BEGIN;UPDATE hospitalflow.hospital_memberships SET active=false WHERE user_id='"+doctor_id+"' AND hospital_id='H-0001';SET LOCAL ROLE hospitalflow_app;SELECT set_config('hospitalflow.actor_id','"+doctor_id+"',true);SELECT json_build_object('read',hf_security.can_read_care('"+pid+"'),'rows',(SELECT count(*) FROM hospitalflow.care_observations WHERE patient_id='"+pid+"'));ROLLBACK;")
    assert '\"read\" : false' in denied and '\"rows\" : 0' in denied
    print('PASS: managed Doctor/Nurse admission, assignment, monitoring, multi-medicine prescriptions, patient fulfillment requests, per-dose outcomes, idempotent configured daily/lab billing, timeline isolation, approval reopening, staged discharge and authorised summary export.')
