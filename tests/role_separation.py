"""Admin management and Doctor clinical authoring are independent roles; Developer has both."""
def check_role_separation(base,sql,Client,password):
    admin=Client(base);admin.login();admin.hospital='H-0001'
    doctor=Client(base);doctor.login('doctor');doctor.hospital='H-0001'
    nurse=Client(base);nurse.login('nurse');nurse.hospital='H-0001'
    developer=Client(base);developer.request('/api/login',{'email':'registered.developer@example.test','password':'Cedar!928'});developer.hospital='H-0001'
    assert admin.request('/api/me')['role']=='Admin' and doctor.request('/api/me')['role']=='Doctor'
    snapshot=admin.request('/api/state');pid=snapshot['patients'][0]['id'];medicine=snapshot['medicines'][0]['id']
    for action in ['prescription','note','cancel-prescription','follow-up','clinical-order','clinical-order-status','complete-clinical-order']:
        admin.action(action,{},403)
    prescription={'patientId':pid,'medicineId':medicine,'quantity':1,'instructions':'Role separation test prescription'}
    rx=doctor.action('prescription',prescription)['reference']
    doctor.action('note',{'patientId':pid,'text':'Doctor clinical note'})
    nurse.action('note',{'patientId':pid,'text':'Nursing clinical note'})
    nurse.action('prescription',prescription,403)
    developer.action('prescription',{**prescription,'instructions':'Developer access regression test'})
    assert any(p['id']==rx for p in admin.request('/api/state')['prescriptions']) # management keeps read access
    doctor.request('/api/admin/operations',expected=403)
    doctor.action('user-status',{'id':admin.request('/api/me')['id'],'active':False},403)
    records=doctor.request('/api/clinical/operations');assert set(records)=={'encounters','clinical_orders','follow_ups','service_catalog'}
    if records['encounters'] and records['service_catalog']:
        payload={'encounterId':records['encounters'][0]['id'],'serviceId':records['service_catalog'][0]['id']}
        order=doctor.action('clinical-order',payload)['reference'];doctor.action('complete-clinical-order',{'id':order})
    # Native inserts/commands and extra permission grants cannot turn an Admin into a prescriber.
    aid=admin.request('/api/me')['id']
    sql("BEGIN;SET LOCAL hospitalflow.actor_id='"+aid+"';INSERT INTO hospitalflow.notes(id,patient_id,text,kind,at) VALUES('FORBIDDEN-ADMIN-NOTE','"+pid+"','Forbidden','Operational note',now());COMMIT;",user='hospitalflow_app',ok=False)
    sql("INSERT INTO hospitalflow.user_permissions(user_id,permission) VALUES('"+aid+"','Doctor');",ok=False)
    account=next(u for u in snapshot['users'] if u['id']!=aid and u['role']=='Volunteer')
    admin.request('/api/admin/account',{'id':account['id'],'role':'User','active':True,'permissions':['Doctor']},409)
    assert sql("SELECT count(*) FROM hospitalflow.users WHERE active AND role='Admin';")!='0'
    print('PASS: distinct Admin/Doctor identities, Admin clinical-write rejection, Doctor/Nurse clinical access, Developer combined access, clinical operations routing, native SQL guards and mixed-permission rejection.')
