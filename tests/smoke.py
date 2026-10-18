#!/usr/bin/env python3
"""End-to-end API checks using isolated synthetic data and a temporary local server."""
import uuid, concurrent.futures, datetime as dt, http.cookiejar, json, os, pathlib, socket, subprocess, tempfile, time, urllib.request, urllib.error
ROOT=pathlib.Path(__file__).resolve().parents[1]
PASSWORD='HospitalFlow-Automated-Test-2026!'
class Client:
    def __init__(self, base,tls_context=None):
        self.base=base
        self.jar=http.cookiejar.CookieJar()
        handlers=[urllib.request.HTTPCookieProcessor(self.jar)]
        if tls_context is not None:handlers.append(urllib.request.HTTPSHandler(context=tls_context))
        self.http=urllib.request.build_opener(*handlers)
    def request(self,path,data=None,expected=200,header=True,key=None):
        headers={'Content-Type':'application/json'}
        if header:headers['X-HospitalFlow']='1'
        if path.startswith('/api/actions/'):headers['Idempotency-Key']=key or str(uuid.uuid4())
        req=urllib.request.Request(self.base+path,data=None if data is None else json.dumps(data).encode(),headers=headers)
        try:
            with self.http.open(req) as r: status=r.status; raw=r.read()
        except urllib.error.HTTPError as e:status=e.code;raw=e.read()
        assert status==expected, f'{path}: expected {expected}, got {status}: {raw.decode()}'
        return json.loads(raw) if raw else None
    def login(self,role='administrator'):
        return self.request('/api/login',{'email':role+'@hospitalflow.local','password':PASSWORD})
    def action(self,action,data,expected=200,key=None):return self.request('/api/actions/'+action,data,expected,key=key)

def run(base):
    c=Client(base)
    c.request('/api/state',expected=401)
    c.request('/api/login',{'email':'administrator@hospitalflow.local','password':'bad'},401)
    c.request('/api/login',{'email':'administrator@hospitalflow.local','password':PASSWORD},400,False)
    c.request('/api/login',{'email':None,'password':None},401)
    c.login();s=c.request('/api/state');assert len(s['patients'])==8
    p={'name':'Synthetic Test Patient','dob':'1993-03-08','sex':'Female','phone':'9000012345','email':'synthetic.patient@example.test'}
    c.action('patient',p);c.action('patient',p,409)
    c.action('patient',{**p,'name':'Invalid','dob':'2999-01-01'},409)
    pid=next(p['id'] for p in c.request('/api/state')['patients'] if p['name']=='Synthetic Test Patient')
    slot=(dt.datetime.now().astimezone()+dt.timedelta(days=2)).replace(hour=10,minute=0,second=0,microsecond=0)
    appt={'patientId':pid,'doctorId':'DR-01','at':slot.isoformat(),'type':'Consultation'}
    c.action('appointment',appt);c.action('appointment',appt,409)
    c.action('appointment',{**appt,'at':slot.replace(hour=6).isoformat()},409)
    aid=next(a['id'] for a in c.request('/api/state')['appointments'] if a['patientId']==pid)
    c.action('appointment-status',{'id':aid,'status':'Completed'},409)
    for status in ['Checked in','In consultation','Completed']:c.action('appointment-status',{'id':aid,'status':status})
    nurse=Client(base);nurse.login('nurse');nurse.action('bill',{'patientId':pid,'description':'Unauthorised','amount':10},403)
    assert not nurse.request('/api/state')['bills']
    receptionist=Client(base);receptionist.login('reception');receptionist.action('medicine',{},403)
    assert not receptionist.request('/api/state')['prescriptions']
    assert not receptionist.request('/api/state')['users']
    # Two independently authenticated callers race for the same bed.
    c2=Client(base);c2.login()
    def admit(client,pid):
        try: client.action('admit',{'patientId':pid,'bedId':'B-05','reason':'Synthetic admission'});return 200
        except AssertionError as e:
            if 'got 409' in str(e):return 409
            raise
    with concurrent.futures.ThreadPoolExecutor() as pool:
        results=list(pool.map(lambda args:admit(*args),[(c,pid),(c2,'HF-1008')]))
    assert sorted(results)==[200,409],results
    # Use a separate patient for the complete discharge pathway.
    c.action('admit',{'patientId':'HF-1007','bedId':'B-06','reason':'Synthetic observation'})
    admission=next(a for a in c.request('/api/state')['admissions'] if a['patientId']=='HF-1007')
    c.action('transfer',{'id':admission['id'],'bedId':'B-07','reason':'Synthetic transfer'})
    assert next(b for b in c.request('/api/state')['beds'] if b['id']=='B-06')['status']=='Cleaning'
    c.action('bed-status',{'id':'B-07','status':'Available'},409)
    c.action('prescription',{'patientId':'HF-1007','medicineId':'MED-01','quantity':5,'instructions':'Synthetic clinician-entered instructions'})
    rx=next(r for r in c.request('/api/state')['prescriptions'] if r['patientId']=='HF-1007')
    c.action('discharge',{'id':admission['id'],'summary':'Synthetic discharge'},409)
    c.action('dispense',{'id':rx['id']});c.action('dispense',{'id':rx['id']},409)
    s=c.request('/api/state');assert next(m for m in s['medicines'] if m['id']=='MED-01')['quantity']==235
    bill=next(b for b in s['bills'] if b['patientId']=='HF-1007')
    c.action('payment',{'id':bill['id'],'amount':bill['balance']+1,'method':'Cash'},409)
    c.action('discharge',{'id':admission['id'],'summary':'Synthetic discharge'},409)
    c.action('payment',{'id':bill['id'],'amount':bill['balance'],'method':'UPI'})
    c.action('discharge',{'id':admission['id'],'summary':'Follow up in clinic as instructed.'})
    c.action('discharge',{'id':admission['id'],'summary':'Duplicate'},409)
    s=c.request('/api/state');assert next(b for b in s['beds'] if b['id']=='B-07')['status']=='Cleaning'
    c.action('bed-status',{'id':'B-07','status':'Available'})
    c.action('prescription',{'patientId':pid,'medicineId':'MED-02','quantity':999,'instructions':'Stock rejection test'})
    rx2=next(r for r in c.request('/api/state')['prescriptions'] if r['patientId']==pid)
    c.action('dispense',{'id':rx2['id']},409)
    before=len([a for a in c.request('/api/state')['audit'] if a['action'] in ['bill','adjustment']])
    c.action('bill',{'patientId':pid,'description':'Synthetic service','amount':100})
    bill2=next(b for b in c.request('/api/state')['bills'] if b['patientId']==pid)
    c.action('adjustment',{'id':bill2['id'],'amount':25,'reason':'Synthetic correction'})
    updated=next(b for b in c.request('/api/state')['bills'] if b['id']==bill2['id'])
    assert updated['total']==75 and len(updated['lines'])==2
    assert len([a for a in c.request('/api/state')['audit'] if a['action'] in ['bill','adjustment']])==before+2
    c.action('user',{'name':'Synthetic receptionist','email':'staffmember@hospitalflow.local','role':'User','password':PASSWORD})
    c.request('/api/logout',{});c.request('/api/state',expected=401)
    print('PASS: authentication, CSRF header, role restrictions, registration, duplicate detection, scheduling, status transitions, concurrent bed allocation, transfer, stock, dispensing, charges, overpayment rejection, adjustments, discharge, audit and user creation.')

if __name__=='__main__':
    import runpy
    runpy.run_path(str(ROOT/'tests/postgres.py'),run_name='__main__')
