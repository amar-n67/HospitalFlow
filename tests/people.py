"""Typed registrations, prefixed IDs, complete fields and role boundaries in isolated DBs."""
import uuid

def check_people(base,sql,Client,password):
    admin=Client(base);admin.login();doctor=Client(base);doctor.login('doctor');nurse=Client(base);nurse.login('nurse')
    assert doctor.request('/api/me')['role']=='Doctor' and nurse.request('/api/me')['role']=='Nurse'
    assert doctor.request('/api/me')['registrationId'].startswith('D-') and nurse.request('/api/me')['registrationId'].startswith('N-')
    nurse.request('/api/people',expected=403)
    payload={'name':'Synthetic Support Colleague','email':'support.colleague@example.test','mobile':'9000088123','dob':'1992-02-12','sex':'Other','address':'Synthetic campus','jobTitle':'Laundry support','occupation':'Washerman','role':'Volunteer','password':'Cedar!928'}
    def post(c,body,key=None,expected=200,operation='register'):
        # Explicit key: the general HTTP helper also covers this registration namespace.
        return c.register_staff(body,expected,key=key or str(uuid.uuid4())) if operation=='register' else c.request('/api/people/'+operation,body,expected,key=key or str(uuid.uuid4()))
    key=str(uuid.uuid4());saved=post(doctor,payload,key);assert post(doctor,payload,key)==saved
    entry=next(p for p in admin.request('/api/people') if p['id']==saved['reference'])
    assert entry['registrationId'].startswith('V-') and entry['mobile']=='9000088123' and entry['dob']==payload['dob'] and entry['occupation']=='Washerman' and entry['address']=='Synthetic campus'
    volunteer=Client(base);volunteer.request('/api/login',{'email':entry['registrationId'],'password':payload['password']})
    assert volunteer.request('/api/me')['role']=='Volunteer' and volunteer.request('/api/me')['permissions']==[]
    assert volunteer.request('/api/me')['profile']['mobile']==entry['mobile']
    own=volunteer.request('/api/state');assert all(own[k]==[] for k in ['patients','appointments','admissions','bills','notes','users'])
    volunteer.request('/api/people',expected=403);post(volunteer,payload,expected=403)
    volunteer.action('patient',{'name':'Blocked'},403)
    post(nurse,payload,expected=403)
    post(doctor,{**payload,'role':'Admin','email':'blocked.admin@example.test'},expected=403)
    post(doctor,{**payload,'role':'Developer','email':'blocked.dev@example.test'},expected=403)
    post(admin,{**payload,'email':'future@example.test','dob':'2999-01-01'},expected=409)
    post(admin,{**payload,'email':'invalidmobile@example.test','mobile':'abc9000088123'},expected=409)
    before=sql('SELECT count(*) FROM hospitalflow.users;');post(admin,{**payload,'email':'wrong-email'},expected=409);assert sql('SELECT count(*) FROM hospitalflow.users;')==before
    for role,prefix in [('Doctor','D-'),('Nurse','N-'),('Admin','A-'),('Developer','DEV-')]:
        body={**payload,'name':'Synthetic Registered '+role,'email':'registered.'+role.lower()+'@example.test','role':role,'department':'General Medicine','start':'08:00','end':'18:00'}
        result=post(admin,body);person=next(p for p in admin.request('/api/people') if p['id']==result['reference']);assert person['registrationId'].startswith(prefix)
        if role=='Doctor':
            provider=next(d for d in admin.request('/api/state')['doctors'] if d['id']==person['doctorId']);assert provider['registrationId']==person['registrationId']
        if role=='Developer':
            developer=Client(base);developer.request('/api/login',{'email':person['registrationId'],'password':payload['password']});developer.request('/api/admin/health');assert developer.request('/api/state')['patients'];post(developer,{**payload,'email':'developer.added@example.test'})
    edited={**payload,'id':entry['id'],'mobile':'9000088124','address':'Updated synthetic campus'}
    post(doctor,edited,operation='update');updated=next(p for p in admin.request('/api/people') if p['id']==entry['id']);assert updated['registrationId']==entry['registrationId'] and updated['mobile']=='9000088124'
    admin_entry=next(p for p in admin.request('/api/people') if p['email']=='administrator@hospitalflow.local')
    post(doctor,{**payload,'id':admin_entry['id'],'role':'Admin','email':admin_entry['email']},operation='update',expected=403)
    patient=next(p for p in admin.request('/api/state')['patients'] if p.get('email'))
    assert patient['registrationId'].startswith('P-') and patient['email']
    assert sql("SELECT count(*) FROM hospitalflow.patients p JOIN hospitalflow.patient_accounts a ON a.patient_id=p.id JOIN hospitalflow.users u ON u.id=a.user_id WHERE p.registration_id<>u.registration_id OR p.email IS DISTINCT FROM u.email;")=='0'
    # New fields are persisted on the actual patient table; not frontend-only columns.
    assert sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='hospitalflow' AND table_name='patients' AND column_name IN ('registration_id','email','address','emergency_contact');")=='4'
    print('PASS: six roles, A/D/N/P/V/DEV IDs, typed registration, doctor/nurse profiles, volunteer occupation/isolation, registration retries, HR contact editing, patient ID/email consistency and Developer full access.')
