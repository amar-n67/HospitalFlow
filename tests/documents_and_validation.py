"""Record-copy permissions and ten-digit validation through API and PostgreSQL."""
def check_documents_and_validation(base,sql,Client,password):
    admin=Client(base);admin.login();snapshot=admin.request('/api/state')
    patient=Client(base);patient.request('/api/login',{'email':'patient.changed@example.test','password':'Willow!7'})
    own=patient.request('/api/state');pid=own['patients'][0]['id']
    profile={'email':'patient.changed@example.test','mobile':'9000077123','address':'Validated address'}
    for bad in ['123456789','12345678901','+919000077123','90000 77123','90000a7123',' 9000077123 ','１２３４５６７８９０']:
        patient.request('/api/account/profile',{**profile,'mobile':bad},409)
        admin.action('patient',{'name':'Invalid mobile test','dob':'1990-01-01','sex':'Other','phone':bad,'email':'bad.mobile@example.test'},409)
    sql("UPDATE hospitalflow.patients SET phone='123456789' WHERE id='"+pid+"';",ok=False)
    sql("UPDATE hospitalflow.person_profiles SET mobile='+919000077123' WHERE user_id=(SELECT id FROM hospitalflow.users WHERE email='nurse@hospitalflow.local');",ok=False)
    volunteer=Client(base);volunteer.request('/api/login',{'email':'support.colleague@example.test','password':'Cedar!928'})
    nurse=Client(base);nurse.login('nurse')
    for kind,key in [('appointment','appointments'),('prescription','prescriptions'),('invoice','bills'),('admission','admissions')]:
        assert snapshot[key],kind+' fixture missing'
        record=snapshot[key][0]
        for mode in ['print','download']:
            doc=admin.request('/api/documents/'+kind+'/'+record['id']+'?mode='+mode)
            assert doc['reference']==record['id'] and '<article' in doc['html'] and 'Patient ID' in doc['html']
            assert 'password' not in doc['html'].lower()
        volunteer.request('/api/documents/'+kind+'/'+record['id']+'?mode=download',expected=403)
        other=next((x for x in snapshot[key] if x['patientId']!=pid),None)
        if other:patient.request('/api/documents/'+kind+'/'+other['id']+'?mode=print',expected=404)
        for item in own[key]:
            assert patient.request('/api/documents/'+kind+'/'+item['id']+'?mode=download')['reference']==item['id']
    nurse.request('/api/documents/invoice/'+snapshot['bills'][0]['id']+'?mode=download',expected=403)
    billing=Client(base);billing.login('billing')
    masked=billing.request('/api/documents/invoice/'+snapshot['bills'][0]['id']+'?mode=download')
    assert 'Restricted' in masked['html']
    admin.request('/api/documents/invoice/missing?mode=download',expected=404)
    admin.request('/api/documents/invoice/missing?mode=invalid',expected=400)
    admin.request('/api/documents/unknown/missing?mode=download',expected=404)
    # Clinician-provided content must remain text in saved/printable documents.
    clinician=Client(base);clinician.login('doctor')
    rx=clinician.action('prescription',{'patientId':pid,'medicineId':snapshot['medicines'][0]['id'],'quantity':1,'instructions':'<script>alert("test")</script> & follow-up'})
    doc=patient.request('/api/documents/prescription/'+rx['reference']+'?mode=download')
    assert '<script>' not in doc['html'] and '&lt;script&gt;' in doc['html']
    assert sql("SELECT count(*) FROM hospitalflow.activity_log WHERE action IN ('document-print','document-download');")!='0'
    print('PASS: ten-digit ASCII mobile validation at API/database, role and patient-owned document access, print/download audit, missing records and HTML escaping.')
