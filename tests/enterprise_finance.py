"""Database-backed tariffs, patient settlement, medication prices and yearly calendars."""
import datetime as dt,uuid,concurrent.futures

def check_enterprise_finance(base,sql,Client):
    admin=Client(base);admin.login();admin.hospital='H-0001'
    doctor=Client(base);doctor.request('/api/login',{'email':'booking.doctor@example.test','password':'Cedar!928'});doctor.hospital='H-0001'
    nurse=Client(base);nurse.login('nurse');nurse.hospital='H-0001'
    patient=Client(base);patient.request('/api/login',{'email':'care.flow.recipient@example.test','password':'Spruce!928'});patient.hospital='H-0001'
    def command(client,action,data,expected=200,key=None):return client.request('/api/enterprise/'+action,data,expected,key=key)
    pid=patient.request('/api/me')['patientId'];bill=admin.action('bill',{'patientId':pid,'description':'Synthetic portal settlement','amount':1000})['reference']
    data={'invoiceId':bill,'amount':100,'reason':'Synthetic approved concession'}
    command(nurse,'discount',data,403);command(patient,'discount',data,403)
    key=str(uuid.uuid4());discount=command(admin,'discount',data,key=key)['reference'];assert command(admin,'discount',data,key=key)['reference']==discount
    command(admin,'discount',{**data,'amount':101},409,key=key)
    command(admin,'discount',{**data,'amount':1000},409)
    for client in [admin,doctor,nurse,patient]:
        row=next(x for x in client.request('/api/finance')['data']['invoices'] if x['id']==bill)
        assert row['gross']==1000 and row['discount']==100 and row['total']==900 and row['balance']==900,row
    pay={'invoiceId':bill,'amount':400,'method':'QR','confirmed':True}
    command(admin,'portal-pay',pay,403);command(doctor,'portal-pay',pay,403)
    command(patient,'portal-pay',{**pay,'confirmed':False},409)
    command(patient,'portal-pay',{**pay,'method':'Cash'},409)
    key=str(uuid.uuid4());receipt=command(patient,'portal-pay',pay,key=key)['reference'];assert command(patient,'portal-pay',pay,key=key)['reference']==receipt
    assert sql("SELECT count(*) FROM hospitalflow.portal_payments WHERE bill_id='"+bill+"';")=='1'
    row=next(x for x in nurse.request('/api/finance')['data']['invoices'] if x['id']==bill)
    assert row['paid']==400 and row['balance']==500 and row['receipts'][0]['mode']=='Test',row
    # Two concurrent settlement attempts cannot overpay the same bill.
    def final_payment(_):
        try:command(patient,'portal-pay',{**pay,'amount':500});return True
        except AssertionError as e:
            assert 'got 409' in str(e);return False
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:assert sum(pool.map(final_payment,range(2)))==1
    # Another patient's invoice and all staff calendars remain inaccessible to this patient.
    other=next(x for x in admin.request('/api/finance')['data']['invoices'] if x['patient_id']!=pid)
    command(patient,'portal-pay',{**pay,'invoiceId':other['id'],'amount':1},403)
    assert all(x['patient_id']==pid for x in patient.request('/api/finance')['data']['invoices'])
    patient.request('/api/calendar/2026',expected=403);patient.request('/api/admin/versions',expected=403);doctor.request('/api/admin/versions',expected=403)
    versions=admin.request('/api/admin/versions');assert versions['current']=='1.0.0' and versions['releases']
    build=Client(base).request('/api/health')
    assert build['version']==versions['current'] and build['commit'] and build['workingTree'] in ('modified','clean','unknown')
    for client in [admin,doctor,nurse,patient]:
        identity=client.request('/api/me');assert identity['version']==build['version'] and identity['commit']==build['commit'] and identity['workingTree']==build['workingTree']
    # A price change must not rewrite previous dispensing invoices.
    med=admin.request('/api/finance')['data']['prices'][0];historical=sql('SELECT COALESCE(sum(unit_price),0) FROM hospitalflow.invoice_line_context;')
    price={'medicineId':med['id'],'price':12.34,'reason':'Synthetic selling tariff update'}
    command(nurse,'medicine-price',price,403);command(patient,'medicine-price',price,403);command(admin,'medicine-price',price)
    assert next(x for x in doctor.request('/api/finance')['data']['prices'] if x['id']==med['id'])['price']==12.34
    assert sql('SELECT COALESCE(sum(unit_price),0) FROM hospitalflow.invoice_line_context;')==historical
    # Authorized Doctors and Pharmacy can discount their scope, without enabling nursing credits.
    doctor_bill=admin.action('bill',{'patientId':pid,'description':'Synthetic Doctor discount','amount':100})['reference']
    command(doctor,'discount',{'invoiceId':doctor_bill,'amount':10,'reason':'Synthetic treating Doctor approval'})
    pharmacy=Client(base);pharmacy.request('/api/login',{'email':'visit.pharmacy@example.test','password':'Cedar!928'});pharmacy.hospital='H-0001'
    command(pharmacy,'discount',{'invoiceId':doctor_bill,'amount':1,'reason':'Wrong invoice category'},403)
    rx=doctor.action('prescription',{'patientId':pid,'medicineId':med['id'],'quantity':1,'instructions':'Synthetic medicine invoice fixture'})['reference']
    pharmacy.action('dispense',{'id':rx})
    medicine_bill=next(m['invoice'] for m in patient.request('/api/finance')['data']['medicines'] if m['prescription_id']==rx)
    command(pharmacy,'discount',{'invoiceId':medicine_bill,'amount':1,'reason':'Synthetic pharmacy concession'})
    invoices=patient.request('/api/finance')['data']['invoices'];due=sum(x['balance'] for x in invoices)
    total={'amount':due,'method':'UPI','confirmed':True}
    command(patient,'portal-pay-total',{**total,'amount':due+1},409)
    key=str(uuid.uuid4());group=command(patient,'portal-pay-total',total,key=key)['reference'];assert command(patient,'portal-pay-total',total,key=key)['reference']==group
    assert all(x['balance']==0 for x in patient.request('/api/finance')['data']['invoices'])
    command(nurse,'portal-pay-total',total,403)
    # Same-date rate revisions are append-only and visible to the clinical team.
    rate=admin.request('/api/care/flow')['rates'][0]
    payload={'ward':rate['ward'],'effectiveFrom':rate['effective_from'],'bedDaily':333,'wardDaily':0,'icuDaily':0,'nursingDaily':0}
    admin.request('/api/care/flow/rate',payload)
    assert any(r['bed_daily']==333 for r in nurse.request('/api/care/flow')['rates'])
    # Legacy/native admissions accrue immediately when the patient loads finance, without a manual bill.
    free_bed=next(b for b in admin.request('/api/state')['beds'] if b['status']=='Available' and b['ward']==rate['ward'])
    stay=nurse.action('admit',{'patientId':pid,'bedId':free_bed['id'],'reason':'Synthetic automatic charge refresh'})['reference']
    assert sql("SELECT count(*) FROM hospitalflow.care_charge_entries WHERE admission_id='"+stay+"';")=='0'
    patient.request('/api/finance')
    assert sql("SELECT sum(amount) FROM hospitalflow.care_charge_entries WHERE admission_id='"+stay+"';")=='333.00'
    patient.request('/api/finance')
    assert sql("SELECT count(*) FROM hospitalflow.care_charge_entries WHERE admission_id='"+stay+"';")=='4'
    bill_id=sql("SELECT bill_id FROM hospitalflow.care_invoices WHERE admission_id='"+stay+"';")
    admin.action('payment',{'id':bill_id,'amount':333,'method':'Cash'})
    nurse.action('discharge',{'id':stay,'summary':'Synthetic completed automatic billing fixture'})
    patient.request('/api/finance')
    assert sql("SELECT sum(amount) FROM hospitalflow.care_charge_entries WHERE admission_id='"+stay+"';")=='333.00'
    # A managed yearly calendar carries fixed national dates without guessing movable festivals.
    calendar=nurse.request('/api/calendar/2030');assert len(calendar['holidays'])==3
    holiday={'name':'Synthetic regional observance','day':'2030-06-12','kind':'Regional','annual':False,'isLeave':True,'active':True,'notes':'Synthetic Admin policy'}
    command(nurse,'holiday',holiday,403)
    hid=command(admin,'holiday',holiday)['reference']
    assert any(h['id']==hid and h['is_leave'] for h in nurse.request('/api/calendar/2030')['holidays'])
    assert not any(h['id']==hid for h in nurse.request('/api/calendar/2031')['holidays'])
    command(admin,'holiday',{**holiday,'id':hid,'active':False});assert not any(h['id']==hid for h in nurse.request('/api/calendar/2030')['holidays'])
    recurring={**holiday,'name':'Synthetic leap-day observance','day':'2028-02-29','annual':True}
    hid=command(admin,'holiday',recurring)['reference']
    assert any(h['id']==hid for h in nurse.request('/api/calendar/2028')['holidays'])
    assert not any(h['id']==hid for h in nurse.request('/api/calendar/2029')['holidays'])
    nurse.request('/api/calendar/10000',expected=409)
    sql("UPDATE hospitalflow.invoice_discounts SET amount=1 WHERE line_id='"+discount+"';",ok=False)
    sql("DELETE FROM hospitalflow.portal_payments WHERE id='"+receipt+"';",ok=False)
    print('PASS: scoped invoice totals/discounts, concurrent idempotent TEST settlement, historical medicine price snapshots, same-date tariff revisions, year/leap-day holiday policies, patient isolation and Admin-only releases.')
