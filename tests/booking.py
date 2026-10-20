"""Booking concurrency, payment honesty, original-source refunds, and staff leave isolation."""
import datetime as dt,uuid,concurrent.futures

def check_booking(base,sql,Client,password):
    admin=Client(base);admin.login();admin.hospital='H-0001'
    portal=Client(base);portal.request('/api/login',{'email':'patient.changed@example.test','password':'Willow!7'});portal.hospital='H-0001'
    patient=portal.request('/api/state')['patients'][0];pid=patient['id']
    for invalid in [199,751,0]:admin.request('/api/booking/fee',{'fee':invalid},409)
    admin.request('/api/booking/fee',{'fee':350})
    portal.request('/api/booking/fee',{'fee':200},403)
    portal.request('/api/booking/attendance',{'status':'Present'},403)
    portal.request('/api/booking/leave',{'startsOn':'2026-10-20','endsOn':'2026-10-21','reason':'Should be blocked'},403)
    person={'name':'Booking Test Clinician','email':'booking.doctor@example.test','mobile':'9000066611','dob':'1980-01-01','sex':'Other','role':'Doctor','department':'General Medicine','password':'Cedar!928','start':'09:00','end':'17:00','jobTitle':'Doctor'}
    uid=admin.register_staff(person)['reference']
    doc=next(p for p in admin.request('/api/people') if p['id']==uid)['doctorId']
    doctor=Client(base);doctor.request('/api/login',{'email':person['email'],'password':person['password']})
    day=(dt.datetime.now(dt.timezone(dt.timedelta(hours=5,minutes=30)))+dt.timedelta(days=10)).date().isoformat()
    path=f'/api/booking/slots?doctorId={doc}&day={day}'
    slots=portal.request(path);assert len(slots)==48
    assert (dt.datetime.fromisoformat(slots[1])-dt.datetime.fromisoformat(slots[0])).seconds==600
    portal.request('/api/booking/reserve',{'id':str(uuid.uuid4()),'doctorId':doc,'at':(dt.datetime.fromisoformat(slots[0])+dt.timedelta(minutes=1)).isoformat(),'method':'UPI','type':'Consultation'},409)
    def reservation(method='UPI',at=None):return {'id':str(uuid.uuid4()),'patientId':'IGNORED_OTHER_ID','doctorId':doc,'at':at or slots[0],'method':method,'type':'Consultation'}
    data=reservation();portal.request('/api/booking/reserve',{**data,'method':'Cash'},409)
    def compete(i):
        c=Client(base);c.login();c.hospital='H-0001'
        return c.request('/api/booking/reserve',{**data,'id':str(uuid.uuid4()),'patientId':pid,'method':'QR'},409)
    # Same idempotent request is safe; another reservation cannot take its held slot.
    saved=portal.request('/api/booking/reserve',data);assert portal.request('/api/booking/reserve',data)==saved
    assert slots[0] not in portal.request(path)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(compete,range(4)))
    bid=saved['reference'];b=next(b for b in portal.request('/api/booking')['data']['bookings'] if b['id']==bid)
    assert b['patient_id']==pid and b['amount']==350 and b['state']=='Pending' and b['appointment_id'] is None
    portal.request('/api/booking/pay',{'id':bid,'confirmed':False},409)
    paid=portal.request('/api/booking/pay',{'id':bid,'confirmed':True});aid=paid['reference']
    assert portal.request('/api/booking/pay',{'id':bid,'confirmed':True})==paid
    assert aid in [a['id'] for a in portal.request('/api/state')['appointments']]
    receipt=portal.request('/api/documents/appointment/'+aid+'?mode=download')['html'];assert 'TEST PAYMENT' in receipt and '350.00' in receipt
    assert next(b for b in doctor.request('/api/booking')['data']['bookings'] if b['id']==bid)['state']=='Paid'
    # Rescheduling retains the appointment and payment; old slot becomes free.
    portal.request('/api/booking/reschedule',{'appointmentId':aid,'doctorId':doc,'at':slots[1]})
    assert slots[0] in portal.request(path) and slots[1] not in portal.request(path)
    assert sql("SELECT appointment_id FROM hospitalflow.appointment_bookings WHERE id='"+bid+"';")==aid
    # Leave request remains private; approval affects patient availability without deleting bookings.
    doctor.request('/api/booking/attendance',{'status':'Present'})
    doctor.request('/api/booking/checkout',{})
    attendance=next(a for a in doctor.request('/api/booking')['data']['attendance'] if a['user_id']==uid)
    assert attendance['approval_status']=='Pending'
    doctor.request('/api/booking/review-attendance',{'id':attendance['id'],'status':'Approved'},403)
    admin.request('/api/booking/review-attendance',{'id':attendance['id'],'status':'Rejected','note':'Please correct this attendance'})
    doctor.request('/api/booking/attendance',{'status':'Absent'})
    today=dt.datetime.now(dt.timezone(dt.timedelta(hours=5,minutes=30))).date().isoformat()
    assert sql("SELECT hf_api.doctor_unavailable('"+doc+"',now());")=='f'
    admin.request('/api/booking/review-attendance',{'id':attendance['id'],'status':'Approved'})
    assert portal.request(f'/api/booking/slots?doctorId={doc}&day={today}')==[]
    assert sql("SELECT hf_api.doctor_unavailable('"+doc+"',now());")=='t'
    admin.request('/api/booking/attendance',{'userId':uid,'status':'Present'},403)
    doctor.request('/api/booking/leave',{'startsOn':day,'endsOn':day,'reason':'Clinical training day'})
    leave=next(l for l in doctor.request('/api/booking')['data']['leaves'] if l['starts_on']==day)
    doctor.request('/api/booking/resolve-leave',{'id':leave['id'],'status':'Approved'},403)
    admin.request('/api/booking/resolve-leave',{'id':leave['id'],'status':'Approved'})
    assert aid in portal.request('/api/booking')['data']['unavailable'] and portal.request(path)==[]
    assert portal.request('/api/booking')['data']['leaves']==[]
    admin.request('/api/booking/resolve-leave',{'id':leave['id'],'status':'Cancelled'})
    assert aid not in portal.request('/api/booking')['data']['unavailable']
    # Patient cancellation refunds only the test source and retains appointment and event evidence.
    portal.request('/api/booking/cancel',{'appointmentId':aid});portal.request('/api/booking/cancel',{'appointmentId':aid})
    b=next(b for b in portal.request('/api/booking')['data']['bookings'] if b['id']==bid);assert b['state']=='Refunded' and b['refunded_at']
    assert next(a for a in portal.request('/api/state')['appointments'] if a['id']==aid)['status']=='Cancelled'
    # Staff cash is recorded as real cash, and never silently marked refunded.
    cash={**reservation('Cash',slots[2]),'patientId':pid}
    doctor.request('/api/booking/reserve',{**cash,'method':'Card'},409)
    cb=doctor.request('/api/booking/reserve',cash)['reference']
    ca=doctor.request('/api/booking/pay',{'id':cb,'confirmed':True})['reference']
    # Legacy status cancellation must also enqueue refund state.
    admin.action('appointment-status',{'id':ca,'status':'Cancelled'})
    assert next(b for b in admin.request('/api/booking')['data']['bookings'] if b['id']==cb)['state']=='Refund pending'
    doctor.request('/api/booking/cash-refund',{'id':cb},403)
    admin.request('/api/booking/cash-refund',{'id':cb})
    assert next(b for b in admin.request('/api/booking')['data']['bookings'] if b['id']==cb)['state']=='Refunded'
    sql("UPDATE hospitalflow.booking_events SET event='tampered' WHERE booking_id='"+cb+"';",ok=False)
    # Expired holds release availability and cannot create appointments.
    exp=portal.request('/api/booking/reserve',reservation(at=slots[3]))['reference']
    sql("UPDATE hospitalflow.appointment_bookings SET expires_at=now()-interval '1 second' WHERE id='"+exp+"';")
    portal.request('/api/booking/pay',{'id':exp,'confirmed':True},409);assert slots[3] in portal.request(path)
    # Two simultaneous first reservations: exactly one wins the same unheld slot.
    competitors=[Client(base),Client(base)]
    for competitor in competitors:competitor.login();competitor.hospital='H-0001'
    def race(c):
        try:c.request('/api/booking/reserve',{**reservation('QR',slots[4]),'patientId':pid});return 200
        except AssertionError as error:
            assert 'got 409:' in str(error),str(error)
            return 409
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:assert sorted(pool.map(race,competitors))==[200,409]
    # Other hospitals and volunteers cannot inspect clinical payment records or modify bookings.
    admin.hospital='H-0002';assert not admin.request('/api/booking')['data']['bookings'];admin.request('/api/booking/cancel',{'appointmentId':aid},403)
    admin.hospital='H-0001'
    volunteer=Client(base);volunteer.request('/api/login',{'email':'support.colleague@example.test','password':'Cedar!928'})
    bd=volunteer.request('/api/booking')['data'];assert not bd['bookings'] and not bd['unavailable'] and not bd['leaves']
    volunteer.request('/api/booking/reserve',reservation(),403)
    print('PASS: 10-minute slots, held-slot concurrency, payment confirmation/idempotency, fee bounds, patient isolation, rescheduling, leave/absence warnings, test-source refunds, cash refund evidence, legacy cancellation and expired holds.')
