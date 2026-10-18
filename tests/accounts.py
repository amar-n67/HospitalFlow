"""Account lifecycle and authorization checks; invoked only by the disposable DB harness."""
import concurrent.futures,json,pathlib,re,time

def check_accounts(base,sql,folder,Client,password):
    admin=Client(base);admin.login();anon=Client(base)
    # Validate through the authenticated API so public signup throttles do not mask failures.
    invalid=['Ab!12','lower!','UPPER!','Mixed12','Pass@1','Passwords-pass!','Policy!7','Policycheck!7','policycheck@example.testA!']
    for candidate in invalid:
        admin.action('user',{'name':'Policy Check','email':'policycheck@example.test','role':'User','password':candidate},409)
    admin.action('user',{'name':'Al','email':'shortname@example.test','role':'User','password':'Al!!!!'},409)
    for address in ['missing.gmail.com','person@','@gmail.com','person@gmail','person@@gmail.com','person..name@gmail.com','person@-gmail.com']:
        admin.action('user',{'name':'Email Check','email':address,'role':'User','password':'Zebra!'},409)
    short=admin.action('user',{'name':'Limited colleague','email':'shortcredential@example.test','role':'User','password':'Zebra!'})
    six=Client(base);six.request('/api/login',{'email':'shortcredential@example.test','password':'Zebra!'})
    assert six.request('/api/me')['role']=='User'
    six.request('/api/account/password',{'currentPassword':'Zebra!','newPassword':'Shortcredential!'},409)
    # Validation also applies to anonymous signup, not only administrator creation.
    anon.request('/api/signup',{'name':'Policy Check','email':'bad.gmail.com','password':'Zebra!'},409)
    anon.request('/api/signup',{'name':'Policy Check','email':'policycheck@example.test','password':'Pass@1'},409)
    email='new-staff@example.test' 
    def link(purpose):
        for _ in range(150):
            for path in pathlib.Path(folder+'/mail').glob('*.json'):
                msg=json.loads(path.read_text())
                if msg['To']==email and '#'+purpose+'?' in msg['Body']:
                    return re.search(r'token=([A-F0-9]{64})',msg['Body'])[1]
            time.sleep(.1)
        raise AssertionError('Expected private account email was not delivered')
    result=anon.request('/api/signup',{'name':'Synthetic staff','email':email,'password':password,'role':'Developer','permissions':['Billing']})
    duplicate=anon.request('/api/signup',{'name':'Synthetic duplicate','email':email,'password':password})
    assert result==duplicate and 'token' not in json.dumps(result).lower()
    account=next(u for u in admin.request('/api/state')['users'] if u['email']==email)
    assert account['role']=='User' and not account['active'] and not account['emailConfirmed'] and account['permissions']==[]
    def manage(role='User',active=True,permissions=[]):return {'id':account['id'],'role':role,'active':active,'permissions':permissions}
    admin.request('/api/admin/account',manage(),409)
    anon.request('/api/login',{'email':email,'password':password},401)
    token=link('verify')
    anon.request('/api/verify-email',{'token':token})
    anon.request('/api/verify-email',{'token':token},409)
    anon.request('/api/login',{'email':email,'password':password},401)
    admin.request('/api/admin/account',manage())
    user=Client(base);user.request('/api/login',{'email':email,'password':password})
    state=user.request('/api/state');assert all(state[k]==[] for k in ['patients','bills','notes','appointments','users','beds'])
    user.request('/api/admin/account',manage('Developer'),403)
    user.request('/api/admin/health',expected=403)
    user.request('/api/admin/operations',expected=403)
    user.action('hospital-profile',{'name':'Blocked change'},403)
    user.action('user',{'name':'Escalation','email':'escalation@example.test','role':'Admin','password':password},403)
    user.action('patient',{'name':'Blocked patient'},403)
    admin.request('/api/admin/account',manage(permissions=['Reception']))
    user.request('/api/state',expected=401)
    user.request('/api/login',{'email':email,'password':password})
    assert user.request('/api/state')['patients'] and user.request('/api/state')['bills']==[]
    user.action('bill',{'patientId':'HF-1001','description':'Forbidden','amount':1},403)
    # Unknown and existing addresses receive the same response; no token is disclosed.
    assert anon.request('/api/forgot-password',{'email':email})==anon.request('/api/forgot-password',{'email':'unknown@example.test'})
    reset=link('reset');replacement='Replacement-Strong-Cedar-2026!'
    anon.request('/api/reset-password',{'token':'0'*64,'password':replacement},409)
    anon.request('/api/reset-password',{'token':reset,'password':'short'},409)
    anon.request('/api/reset-password',{'token':reset,'password':'New-staff!'},409)
    anon.request('/api/reset-password',{'token':reset,'password':replacement})
    anon.request('/api/reset-password',{'token':reset,'password':replacement},409)
    user.request('/api/state',expected=401)
    user.request('/api/login',{'email':email,'password':password},401)
    user.request('/api/login',{'email':email,'password':replacement})
    # Developer is a real full-access role, not a browser-only special case.
    admin.request('/api/admin/account',manage('Developer'))
    user.request('/api/state',expected=401);user.request('/api/login',{'email':email,'password':replacement})
    assert user.request('/api/me')['role']=='Developer' and user.request('/api/state')['bills']
    user.request('/api/admin/health')
    operations=user.request('/api/admin/operations');assert 'suppliers' in operations and 'account_tokens' not in operations
    user.action('hospital-profile',{'name':'Synthetic developer test hospital'})
    user.action('user',{'name':'Developer created account','email':'dev-created@example.test','role':'User','password':password})
    user.request('/api/admin/account',manage('User'),409) # self-demotion blocked
    admin.request('/api/admin/account',manage(active=False))
    user.request('/api/state',expected=401)
    assert sql("SELECT count(*) FROM hospitalflow.roles;")=='3'
    assert sql("SELECT count(*) FROM hospitalflow.account_tokens WHERE token_hash !~ '^[A-F0-9]{64}$';")=='0'
    assert sql("SELECT bool_and(encrypted_message NOT LIKE '%token=%') FROM hospitalflow.account_mail;")=='t'
    print('PASS: six-character minimum, email syntax, uppercase/lowercase/symbol rules, common-password and identity rejection across account flows.')
    print('PASS: signup privilege rejection, verification/approval, three roles, permission boundaries, session revocation, private mail, generic recovery responses and single-use password reset.')
