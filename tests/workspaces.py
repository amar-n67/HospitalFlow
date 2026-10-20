"""Role workspaces: own-profile boundaries, staged email changes and task ownership."""
import pathlib,json,time,re

def check_workspaces(base,sql,folder,Client,password):
    admin=Client(base);admin.login()
    patient=Client(base);patient.request('/api/login',{'email':'synthetic.patient@example.test','password':'Willow!7'})
    me=patient.request('/api/me');pid=me['patientId'];before=patient.request('/api/state')['patients'][0]
    body={'email':me['email'],'mobile':'9000077123','address':'Updated patient address','emergencyContact':'Family: 9000077124','role':'Admin','dob':'1900-01-01','id':'someone-else'}
    patient.request('/api/account/profile',body)
    after=patient.request('/api/state')['patients'][0]
    assert after['phone']=='9000077123' and after['address']==body['address'] and after['dob']==before['dob']
    assert patient.request('/api/me')['role']=='User'
    patient.request('/api/account/profile',{**body,'mobile':'not-a-mobile'},409)
    changed='patient.changed@example.test'
    patient.request('/api/account/profile',{**body,'email':changed,'currentPassword':'wrong'},409)
    patient.request('/api/account/profile',{**body,'email':changed,'currentPassword':'Willow!7'})
    assert patient.request('/api/me')['email']==me['email']
    token=None
    for _ in range(150):
        for path in pathlib.Path(folder+'/mail').glob('*.json'):
            mail=json.loads(path.read_text())
            if mail.get('To')==changed and 'email-change?token=' in mail.get('Body',''):
                token=re.search(r'email-change\?token=([A-F0-9]{64})',mail['Body'])[1]
        if token:break
        time.sleep(.1)
    assert token,'Email confirmation was not delivered to private local outbox'
    anon=Client(base);anon.request('/api/account/confirm-email-change',{'token':token})
    patient.request('/api/me',expected=401)
    anon.request('/api/account/confirm-email-change',{'token':token},409)
    patient.request('/api/login',{'email':changed,'password':'Willow!7'})
    assert patient.request('/api/state')['patients'][0]['email']==changed
    assert patient.request('/api/me')['registrationId']==me['registrationId']
    nurse=Client(base);nurse.login('nurse')
    nurseme=nurse.request('/api/me')
    nurse.request('/api/account/profile',{'email':nurseme['email'],'mobile':'9000077125','address':'Staff contact address'})
    assert nurse.request('/api/me')['profile']['mobile']=='9000077125'
    directory=admin.request('/api/people');vol=next(p for p in directory if p['email']=='support.colleague@example.test')
    volunteer=Client(base);volunteer.request('/api/login',{'email':vol['email'],'password':'Cedar!928'})
    admin.request('/api/work/tasks',{'assignedTo':vol['id'],'title':'Prepare linen trolley','location':'Service room','dueAt':'2027-01-01T10:00:00Z'})
    tasks=volunteer.request('/api/work/tasks');assert len(tasks)==1
    task=tasks[0];assert task['title']=='Prepare linen trolley'
    assert nurse.request('/api/work/tasks')==[] and patient.request('/api/work/tasks')==[]
    nurse.request('/api/work/tasks',{'id':task['id'],'status':'In progress'},409)
    volunteer.request('/api/work/tasks',{'id':task['id'],'status':'Completed'},409)
    volunteer.request('/api/work/tasks',{'id':task['id'],'status':'In progress'})
    volunteer.request('/api/work/tasks',{'id':task['id'],'status':'Completed'})
    volunteer.request('/api/work/tasks',{'assignedTo':vol['id']},403)
    volunteer.request('/api/admin/health',expected=403)
    assert volunteer.request('/api/state')['patients']==[]
    assert sql("SELECT count(*) FROM hospitalflow.activity_log WHERE action IN ('profile-updated','profile-email-confirmed','work-task-updated');")!='0'
    print('PASS: own contact editing, protected DOB/role/identity, invalid mobile/current password rejection, verified email switch with patient consistency and session revocation, task ownership/status transitions and volunteer clinical isolation.')
