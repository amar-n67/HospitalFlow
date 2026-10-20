"""Prescription administration evidence, nurse navigation restrictions and patient isolation."""
import datetime,uuid

def check_medication_care(base,sql,Client):
    admin=Client(base);admin.login();admin.hospital='H-0001'
    doctor=Client(base);doctor.login('doctor');doctor.hospital='H-0001'
    nurse=Client(base);nurse.login('nurse');nurse.hospital='H-0001'
    patient=Client(base);patient.request('/api/login',{'email':'patient.changed@example.test','password':'Willow!7'});patient.hospital='H-0001'
    pid=patient.request('/api/me')['patientId']
    nurse.request('/api/network',expected=403)
    workspaces=nurse.request('/api/network/workspaces');assert not workspaces['providers'] and not workspaces['referrals']
    assert set(h['id'] for h in workspaces['hospitals'])<=set(workspaces['access'])
    for client in [doctor,nurse]:
        admin.action('grant-patient-access',{'userId':client.request('/api/me')['id'],'patientId':pid,'purpose':'Synthetic medication care test','expiresAt':(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=1)).isoformat()})
    medicine=next(m for m in admin.request('/api/state')['medicines'] if m['quantity']>3)
    rx=doctor.action('prescription',{'patientId':pid,'medicineId':medicine['id'],'quantity':3,'instructions':'Synthetic clinician instructions'})['reference']
    assert any(r['id']==rx for r in nurse.request('/api/care/medications')['prescriptions'])
    payload={'prescriptionId':rx,'quantity':1,'note':'Provided in hospital; synthetic test only'}
    nurse.request('/api/care/medications/provide',payload,409) # pharmacy handover is mandatory
    admin.action('dispense',{'id':rx})
    for client in [doctor,admin,patient]:client.request('/api/care/medications/provide',payload,403)
    key=str(uuid.uuid4());saved=nurse.request('/api/care/medications/provide',payload,key=key)
    assert nurse.request('/api/care/medications/provide',payload,key=key)==saved
    nurse.request('/api/care/medications/provide',{**payload,'quantity':2},409,key=key)
    nurse.request('/api/care/medications/provide',{**payload,'quantity':3},409)
    nurse.request('/api/care/medications/provide',{**payload,'quantity':0},409)
    for client in [doctor,nurse,patient]:
        care=client.request('/api/care/medications');record=next(a for a in care['administrations'] if a['id']==saved['reference'])
        assert record['providedAt'] and record['staffId'] and record['providedBy'] and record['quantity']==1
        assert next(r for r in care['prescriptions'] if r['id']==rx)['provided']==1
    assert all(r['patientId']==pid for r in patient.request('/api/care/medications')['prescriptions'])
    nurse.hospital='H-0002';nurse.request('/api/care/medications',expected=403);nurse.hospital='H-0001'
    aid=nurse.request('/api/me')['id']
    sql("UPDATE hospitalflow.medication_administrations SET note='altered' WHERE id='"+saved['reference']+"';",ok=False)
    sql("DELETE FROM hospitalflow.medication_administrations WHERE id='"+saved['reference']+"';",user='hospitalflow_app',ok=False)
    assert sql("SELECT count(*) FROM hospitalflow.activity_log WHERE action='medication-provided' AND reference='"+saved['reference']+"';")!='0'
    print('PASS: nurse network restrictions, scoped prescriptions, pharmacy handover, nurse-only administration, timestamp/staff evidence, idempotency, quantity limits, patient visibility and immutable records.')
