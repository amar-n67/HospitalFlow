"""Assigned consultation -> prescription -> pharmacy invoice -> nursing -> patient history."""
import uuid,datetime as dt

def check_visit_prescriptions(base,sql,Client):
    admin=Client(base);admin.login();admin.hospital='H-0001'
    doctor=Client(base);doctor.request('/api/login',{'email':'booking.doctor@example.test','password':'Cedar!928'});doctor.hospital='H-0001'
    nurse=Client(base);nurse.login('nurse');nurse.hospital='H-0001'
    patient=Client(base);patient.request('/api/login',{'email':'patient.changed@example.test','password':'Willow!7'});patient.hospital='H-0001'
    pid=patient.request('/api/me')['patientId'];doc=doctor.request('/api/me')['profile']['doctorId']
    day=(dt.datetime.now(dt.timezone(dt.timedelta(hours=5,minutes=30)))+dt.timedelta(days=45)).date().isoformat()
    at=admin.request('/api/booking/slots?doctorId='+doc+'&day='+day)[0]
    hold=admin.request('/api/booking/reserve',{'id':str(uuid.uuid4()),'patientId':pid,'doctorId':doc,'at':at,'method':'Cash','type':'Consultation'})['reference']
    appointment=admin.request('/api/booking/pay',{'id':hold,'confirmed':True})['reference']
    medicine=next(m for m in admin.request('/api/state')['medicines'] if m['quantity']>=4)
    payload={'appointmentId':appointment,'patientId':pid,'medicineId':medicine['id'],'quantity':2,'instructions':'Synthetic visit-linked instructions'}
    doctor.request('/api/care/prescribe-visit',payload,409)
    admin.action('appointment-status',{'id':appointment,'status':'Checked in'})
    other=Client(base);other.login('doctor');other.hospital='H-0001'
    other.action('appointment-status',{'id':appointment,'status':'In consultation'},403)
    doctor.action('appointment-status',{'id':appointment,'status':'In consultation'})
    assert appointment in doctor.request('/api/care/medications')['visits']
    for client in [admin,nurse,patient]:client.request('/api/care/prescribe-visit',payload,403)
    other.request('/api/care/prescribe-visit',payload,403)
    doctor.request('/api/care/prescribe-visit',{**payload,'patientId':'WRONG-PATIENT'},409)
    key=str(uuid.uuid4());rx=doctor.request('/api/care/prescribe-visit',payload,key=key)['reference']
    assert doctor.request('/api/care/prescribe-visit',payload,key=key)['reference']==rx
    assert sql("SELECT appointment_id FROM hospitalflow.prescription_visits WHERE prescription_id='"+rx+"';")==appointment
    # Existing limited employee identity can be granted pharmacy operations without admin privileges.
    uid=admin.action('user',{'name':'Synthetic Pharmacy Operator','email':'visit.pharmacy@example.test','role':'User','password':'Cedar!928'})['reference']
    admin.request('/api/admin/account',{'id':uid,'role':'User','active':True,'permissions':['Pharmacist']})
    pharmacy=Client(base);pharmacy.request('/api/login',{'email':'visit.pharmacy@example.test','password':'Cedar!928'});pharmacy.hospital='H-0001'
    assert any(r['id']==rx for r in pharmacy.request('/api/care/medications')['prescriptions'])
    dispense_key=str(uuid.uuid4());pharmacy.action('dispense',{'id':rx},key=dispense_key);pharmacy.action('dispense',{'id':rx},key=dispense_key)
    row=next(r for r in pharmacy.request('/api/care/medications')['prescriptions'] if r['id']==rx)
    bill=row['billId'];assert bill and row['dispensedAt'] and row['prescriber']
    assert pharmacy.request('/api/documents/invoice/'+bill+'?mode=download')['reference']==bill
    assert patient.request('/api/documents/invoice/'+bill+'?mode=download')['reference']==bill
    unrelated=admin.action('bill',{'patientId':pid,'description':'Unrelated service charge','amount':10})['reference']
    pharmacy.request('/api/documents/invoice/'+unrelated+'?mode=download',expected=403)
    nurse.request('/api/care/medications/provide',{'prescriptionId':rx,'quantity':1,'note':'Synthetic visit medication provided'})
    care=patient.request('/api/care/medications');saved=next(r for r in care['prescriptions'] if r['id']==rx)
    assert saved['appointmentId']==appointment and saved['billId']==bill and saved['provided']==1
    assert any(a['prescriptionId']==rx for a in care['administrations'])
    doctor.action('appointment-status',{'id':appointment,'status':'Completed'})
    doctor.request('/api/care/prescribe-visit',{**payload,'quantity':1},key=str(uuid.uuid4()))
    assert len([r for r in patient.request('/api/care/medications')['prescriptions'] if r['appointmentId']==appointment])==2
    assert sql("SELECT count(*) FROM hospitalflow.prescription_dispensations WHERE prescription_id='"+rx+"';")=='1'
    print('PASS: assigned-doctor visit transitions, fixed patient prescription linkage, multiple medicines/history, pharmacy dispensing/invoice idempotency, pharmacy document boundaries, nursing timestamps and patient visibility.')
