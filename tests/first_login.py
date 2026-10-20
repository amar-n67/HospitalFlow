"""New employee registration uses the server default and requires DOB/password activation."""
import uuid,datetime

def check_first_login(base,sql,Client):
    admin=Client(base);admin.login();admin.hospital='H-0001'
    body={'name':'First Login Nurse','email':'first.login.nurse@example.test','mobile':'9000044123','dob':'1996-02-20','sex':'Other','role':'Nurse','department':'General Medicine','jobTitle':'Nurse'}
    key=str(uuid.uuid4());saved=admin.request('/api/people/register',body,key=key)
    assert admin.request('/api/people/register',body,key=key)==saved
    user=Client(base);first=user.request('/api/login',{'email':body['email'],'password':'1234'});assert first['requiresOnboarding']
    user.request('/api/me',expected=401);user.request('/api/state',expected=401)
    user.request('/api/patient/onboarding',{'challenge':first['challenge'],'dob':'1990-01-01','password':'Willow!72'},409)
    user.request('/api/patient/onboarding',{'challenge':first['challenge'],'dob':body['dob'],'password':'1234'},409)
    user.request('/api/patient/onboarding',{'challenge':first['challenge'],'dob':body['dob'],'password':'Willow!72'})
    user.request('/api/patient/onboarding',{'challenge':first['challenge'],'dob':body['dob'],'password':'Willow!73'},409)
    user.request('/api/login',{'email':body['email'],'password':'1234'},401)
    user.request('/api/login',{'email':body['email'],'password':'Willow!72'});assert user.request('/api/me')['role']=='Nurse'
    assert sql("SELECT count(*) FROM hospitalflow.staff_onboarding WHERE user_id='"+saved['reference']+"' AND NOT must_change_password AND activated_at IS NOT NULL;")=='1'
    # A supplied registration password cannot override the default or skip verification.
    second={**body,'email':'first.login.other@example.test','password':'Ignored!78'}
    result=admin.request('/api/people/register',second)
    pending=Client(base);pending.request('/api/login',{'email':second['email'],'password':'Ignored!78'},401)
    challenge=pending.request('/api/login',{'email':second['email'],'password':'1234'});assert challenge['requiresOnboarding']
    for _ in range(5):pending.request('/api/patient/onboarding',{'challenge':challenge['challenge'],'dob':'1901-01-01','password':'Willow!72'},409)
    pending.request('/api/patient/onboarding',{'challenge':challenge['challenge'],'dob':body['dob'],'password':'Willow!72'},409)
    admin.request('/api/me') # existing account has not been forced through activation
    print('PASS: password-free employee registration, default 1234, ignored caller password, DOB gate, strong replacement, no pre-activation session, single-use challenge and attempt limit.')
