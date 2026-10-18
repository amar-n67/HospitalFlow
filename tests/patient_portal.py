"""Patient invitation, first-login and isolation tests in the disposable integration database."""
import concurrent.futures,json,pathlib,re,time,uuid

def check_patient_portal(base,sql,folder,Client,password):
    admin=Client(base);admin.login();anon=Client(base)
    email='synthetic.patient@example.test'
    patient=next(p for p in admin.request('/api/state')['patients'] if p.get('email')==email)
    pid=patient['id']
    def invitation(address,kind='mail'):
        for _ in range(200):
            messages=[]
            for path in pathlib.Path(folder+'/'+kind).glob('*.json'):
                body=json.loads(path.read_text());text=body.get('Body','')
                if 'Email: '+address in text and 'Temporary password:' in text:messages.append((path.stat().st_mtime_ns,path,body))
            if messages:
                _,path,message=max(messages,key=lambda item:item[0]);assert path.stat().st_mode&0o077==0
                return message,re.search(r'Temporary password: ([^\s]+)',message['Body'])[1]
            time.sleep(.1)
        raise AssertionError('Patient invitation not delivered to private '+kind+' pickup')
    mail,temporary=invitation(email);sms,sms_password=invitation(email,'sms')
    assert sms_password==temporary and sms['To']=='+919000012345' and pid in sms['Body'] and 'localhost:5136' in mail['Body']
    assert sql("SELECT count(*) FROM hospitalflow.patient_accounts WHERE patient_id='"+pid+"';")=='1'
    sql("UPDATE hospitalflow.patient_accounts SET temporary_expires_at=now()-interval '1 minute' WHERE patient_id='"+pid+"';")
    anon.request('/api/login',{'email':pid,'password':temporary},401)
    sql("UPDATE hospitalflow.patient_accounts SET temporary_expires_at=now()+interval '1 day' WHERE patient_id='"+pid+"';")
    first=anon.request('/api/login',{'email':pid.lower(),'password':temporary})
    assert first['requiresOnboarding'] and len(first['challenge'])==64
    anon.request('/api/state',expected=401)
    anon.request('/api/me',expected=401)
    payload={'challenge':first['challenge'],'dob':'1900-01-01','password':'Willow!7'}
    anon.request('/api/patient/onboarding',payload,409)
    payload['dob']=patient['dob'];payload['password']='Pass@1'
    anon.request('/api/patient/onboarding',payload,409)
    payload['password']=temporary;anon.request('/api/patient/onboarding',payload,409)
    payload['password']='Willow!7';anon.request('/api/patient/onboarding',payload)
    anon.request('/api/patient/onboarding',payload,409)
    anon.request('/api/login',{'email':pid,'password':temporary},401)
    portal=Client(base);portal.request('/api/login',{'email':email,'password':'Willow!7'})
    assert portal.request('/api/me')['patientId']==pid
    own=portal.request('/api/state');assert len(own['patients'])==1 and own['patients'][0]['id']==pid
    assert not own['users'] and not own['notes'] and not own['movements']
    assert all(p['patientId']==pid for key in ['appointments','admissions','prescriptions','bills'] for p in own[key])
    portal.request('/api/admin/operations',expected=403)
    portal.request('/api/admin/health',expected=403)
    portal.action('patient',{'name':'Forbidden'},403)
    other=next(p for p in admin.request('/api/state')['patients'] if p['id']!=pid)
    portal.request('/api/activity',{'event':'record-view','entity':'patient','reference':other['id']},403)
    portal.request('/api/activity',{'event':'record-view','entity':'patient','reference':pid})
    another_bill=next(b for b in admin.request('/api/state')['bills'] if b['patientId']!=pid)
    portal.request('/api/activity',{'event':'record-view','entity':'invoice','reference':another_bill['id']},403)
    patient_user=next(u for u in admin.request('/api/state')['users'] if u['email']==email)
    admin.request('/api/admin/account',{'id':patient_user['id'],'role':'Admin','active':True,'permissions':[]},409)
    sql("UPDATE hospitalflow.users SET role='Admin' WHERE id='"+patient_user['id']+"';",ok=False)
    sql("INSERT INTO hospitalflow.user_permissions VALUES('"+patient_user['id']+"','Doctor');",ok=False)
    portal.request('/api/account/theme',{'theme':'Dark'});assert portal.request('/api/me')['theme']=='Dark'
    portal.request('/api/account/theme',{'theme':'Unsupported'},409)
    by_id=Client(base);by_id.request('/api/login',{'email':pid,'password':'Willow!7'});assert by_id.request('/api/me')['patientId']==pid
    # A doctor can register a new patient; retries do not create duplicate accounts/messages.
    doctor=Client(base);doctor.login('doctor')
    new={'name':'Synthetic Portal Recipient','dob':'1991-06-15','sex':'Other','phone':'+919000033333','email':'portal.recipient@example.test'}
    key=str(uuid.uuid4());saved=doctor.action('patient',new,key=key);assert doctor.action('patient',new,key=key)==saved
    second=next(p for p in admin.request('/api/state')['patients'] if p.get('email')==new['email'])
    assert sql("SELECT count(*) FROM hospitalflow.account_mail m JOIN hospitalflow.users u ON u.id=m.user_id WHERE u.email='portal.recipient@example.test';")=='1'
    second_mail,second_temp=invitation(new['email']);invitation(new['email'],'sms')
    before=sql('SELECT count(*) FROM hospitalflow.patients;')
    doctor.action('patient',{**new,'name':'Different identity','dob':'1994-06-15','phone':'9000044444'},409)
    assert sql('SELECT count(*) FROM hospitalflow.patients;')==before # Email collision rolls back registration too.
    # Recovery can change a credential but cannot bypass first-time DOB verification.
    anon.request('/api/forgot-password',{'email':new['email']})
    reset=None
    for _ in range(200):
        for path in pathlib.Path(folder+'/mail').glob('*.json'):
            message=json.loads(path.read_text())
            if message['To']==new['email'] and '#reset?' in message['Body']:reset=re.search(r'token=([A-F0-9]{64})',message['Body'])[1]
        if reset:break
        time.sleep(.1)
    assert reset
    anon.request('/api/reset-password',{'token':reset,'password':'Maple!92'})
    still_pending=anon.request('/api/login',{'email':second['id'],'password':'Maple!92'});assert still_pending['requiresOnboarding']
    anon.request('/api/state',expected=401)
    sql("UPDATE hospitalflow.patient_accounts SET invited_at=now()-interval '2 minutes' WHERE patient_id='"+second['id']+"';")
    doctor.request('/api/patient/invitation',{'patientId':second['id']})
    anon.request('/api/login',{'email':second['id'],'password':'Maple!92'},401)
    anon.request('/api/patient/onboarding',{'challenge':still_pending['challenge'],'dob':new['dob'],'password':'Spruce!7'},409)
    assert sql("SELECT count(*) FROM hospitalflow.patient_sms s JOIN hospitalflow.users u ON u.id=s.user_id WHERE u.email='portal.recipient@example.test';")=='2'
    print('PASS: patient ID/email login, atomic email/SMS invitations, private pickups, temporary-password expiry, DOB and password-change gate, invitation reissue, recovery bypass prevention, doctor registration, retry idempotency, patient isolation and stored theme.')
