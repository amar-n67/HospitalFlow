import datetime as dt
"""Attendance self-service and approval by an assigned hospital administrator, including self-approval."""
def check_attendance_approval(base,sql,Client,password):
    admin=Client(base);admin.login();admin.hospital='H-0001'
    volunteer=Client(base);volunteer.request('/api/login',{'email':'support.colleague@example.test','password':'Cedar!928'});volunteer.hospital='H-0001'
    uid=volunteer.request('/api/me')['id'];admin_id=admin.request('/api/me')['id']
    own=volunteer.request('/api/booking/attendance',{'status':'Present'});request_id=own['reference'];assert own['state']=='Pending'
    assert volunteer.request('/api/booking/attendance',{'status':'Present'})['reference']==request_id
    assert all(a['user_id']==uid for a in volunteer.request('/api/booking')['data']['attendance'])
    volunteer.request('/api/booking/attendance',{'userId':admin_id,'status':'Present'},403)
    volunteer.request('/api/booking/review-attendance',{'id':request_id,'status':'Approved'},403)
    admin.request('/api/booking/review-attendance',{'id':request_id,'status':'Rejected','note':'bad'},409)
    admin.request('/api/booking/review-attendance',{'id':request_id,'status':'Approved'})
    approved=next(a for a in volunteer.request('/api/booking')['data']['attendance'] if a['id']==request_id)
    assert approved['approval_status']=='Approved' and approved['reviewed_by']==admin_id and approved['reviewed_at']
    admin.request('/api/booking/review-attendance',{'id':request_id,'status':'Approved'},409)
    volunteer.request('/api/booking/checkout',{})
    updated=next(a for a in volunteer.request('/api/booking')['data']['attendance'] if a['id']==request_id)
    assert updated['approval_status']=='Pending' and updated['check_out'] and not updated['reviewed_by']
    admin.request('/api/booking/review-attendance',{'id':request_id,'status':'Rejected','note':'Please correct this request'})
    assert volunteer.request('/api/booking/attendance',{'status':'Present'})['state']=='Pending'
    sql("UPDATE hospitalflow.staff_attendance SET approval_status='Approved',reviewed_by=NULL,reviewed_at=NULL WHERE id='"+request_id+"';")
    assert volunteer.request('/api/booking/attendance',{'status':'Present'})['state']=='Pending'
    # An assigned administrator may approve their own request.
    mine=admin.request('/api/booking/attendance',{'status':'Present'})['reference']
    admin.request('/api/booking/review-attendance',{'id':mine,'status':'Approved'})
    admin.request('/api/booking/attendance',{'userId':uid,'status':'Present'},403)
    yesterday=(dt.datetime.now(dt.timezone(dt.timedelta(hours=5,minutes=30)))-dt.timedelta(days=1)).date().isoformat()
    correction={'userId':uid,'day':yesterday,'status':'Present','checkIn':yesterday+'T09:00:00+05:30','checkOut':yesterday+'T17:30:00+05:30','reason':'Verified daily attendance times'}
    corrected=admin.request('/api/booking/manage-attendance',correction)['reference']
    record=next(a for a in admin.request('/api/booking')['data']['attendance'] if a['id']==corrected)
    assert record['total_seconds']==30600 and record['totalHours']==8.5 and record['reviewed_by']==admin_id
    admin.request('/api/booking/manage-attendance',{**correction,'checkOut':yesterday+'T08:00:00+05:30'},409)
    admin.request('/api/booking/manage-attendance',{**correction,'reason':'bad'},409)
    volunteer.request('/api/booking/manage-attendance',correction,403)
    admin.request('/api/booking/manage-attendance',{**correction,'checkOut':yesterday+'T17:45:00+05:30'})
    record=next(a for a in admin.request('/api/booking')['data']['attendance'] if a['id']==corrected)
    assert record['total_seconds']==31500 and record['totalHours']==8.75
    admin.request('/api/booking/manage-attendance',{**correction,'status':'Absent'})
    record=next(a for a in admin.request('/api/booking')['data']['attendance'] if a['id']==corrected)
    assert record['total_seconds']==0 and record['check_in'] is None and record['check_out'] is None
    live=next(a for a in admin.request('/api/booking')['data']['attendance'] if a['id']==mine)
    assert live['total_seconds'] is None and live['totalHours'] is None and live['elapsedSeconds']>=0
    # Assign a local administrator and the same volunteer to another hospital.
    admin.hospital='H-0004'
    body={'name':'Attendance Local Administrator','email':'attendance.admin@example.test','mobile':'9000077733','dob':'1985-01-01','sex':'Other','role':'Admin','password':'Cedar!928'}
    local_id=admin.register_staff(body)['reference']
    admin.request('/api/network/access',{'userId':uid,'hospitalId':'H-0004','active':True})
    local=Client(base);local.request('/api/login',{'email':body['email'],'password':body['password']});local.hospital='H-0004'
    volunteer.hospital='H-0004';second=volunteer.request('/api/booking/attendance',{'status':'Present'})['reference']
    assert second!=request_id
    admin.request('/api/booking/manage-attendance',correction,403)
    assert not admin.request('/api/booking')['data']['canReviewAttendance'] # Network operator has no local membership here.
    admin.request('/api/booking/review-attendance',{'id':second,'status':'Approved'},403)
    assert local.request('/api/booking')['data']['canReviewAttendance']
    local.request('/api/booking/manage-attendance',{**correction,'userId':admin_id},403)
    local.request('/api/booking/review-attendance',{'id':request_id,'status':'Approved'},403)
    local.request('/api/booking/review-attendance',{'id':second,'status':'Approved'})
    admin.hospital='H-0001';admin.request('/api/booking/review-attendance',{'id':second,'status':'Approved'},403)
    # Private legacy implementation cannot bypass approvals through the runtime database identity.
    assert sql("SELECT has_function_privilege('hospitalflow_app','hf_api.booking_command_base(text,jsonb,boolean)','EXECUTE');")=='f'
    assert sql("SELECT has_function_privilege('hospitalflow_app','hf_api.booking_state_base()','EXECUTE');")=='f'
    sql("SELECT hf_api.booking_command_base('attendance','{}'::jsonb,true);",user='hospitalflow_app',ok=False)
    assert sql("SELECT count(*) FROM hospitalflow.row_history WHERE table_name='staff_attendance' AND record_id='"+request_id+"';")!='0'
    print('PASS: self attendance, pending approvals, admin self-review, review metadata, rejection/resubmission, checkout reapproval, hospital membership and row isolation, and private legacy command revocation.')
