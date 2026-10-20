"""Shared approved leave visibility without exposing reasons or crossing hospitals."""
import datetime as dt,json

def check_leave_calendar(base,sql,Client,password):
    anonymous=Client(base);anonymous.request('/api/leave/calendar',expected=401)
    admin=Client(base);admin.login();admin.hospital='H-0001'
    volunteer=Client(base);volunteer.request('/api/login',{'email':'support.colleague@example.test','password':'Cedar!928'});volunteer.hospital='H-0001'
    nurse=Client(base);nurse.login('nurse');nurse.hospital='H-0001'
    today=dt.datetime.now(dt.timezone(dt.timedelta(hours=5,minutes=30))).date();start=(today+dt.timedelta(days=5)).isoformat();end=(today+dt.timedelta(days=7)).isoformat()
    reason='Private medical information for reviewer only'
    def apply(client,starts,ends):
        client.request('/api/booking/leave',{'startsOn':starts,'endsOn':ends,'reason':reason})
        return next(l for l in client.request('/api/booking')['data']['leaves'] if l['starts_on']==starts and l['status']=='Pending')['id']
    leave=apply(volunteer,start,end)
    assert all(l['id']!=leave for l in nurse.request('/api/leave/calendar')['leaves'])
    admin.request('/api/booking/resolve-leave',{'id':leave,'status':'Approved'})
    calendar=nurse.request('/api/leave/calendar');entry=next(l for l in calendar['leaves'] if l['id']==leave)
    assert calendar['hospitalId']=='H-0001' and entry['endsOn']==end and entry['availability']=='Upcoming' and entry['daysRemaining'] is None
    assert entry['name'] and entry['registrationId'].startswith('V-')
    assert reason not in json.dumps(calendar) and 'reason' not in entry and 'userId' not in entry
    # Today's inclusive count and current/upcoming labels are computed in IST.
    current=apply(nurse,today.isoformat(),(today+dt.timedelta(days=2)).isoformat())
    admin.request('/api/booking/resolve-leave',{'id':current,'status':'Approved'})
    row=next(l for l in volunteer.request('/api/leave/calendar')['leaves'] if l['id']==current)
    assert row['availability']=='On leave' and row['daysRemaining']==3
    patient=Client(base);patient.request('/api/login',{'email':'patient.changed@example.test','password':'Willow!7'});patient.hospital='H-0001';patient.request('/api/leave/calendar',expected=403)
    # A different hospital's assigned administrator cannot see the original hospital calendar.
    local=Client(base);local.request('/api/login',{'email':'attendance.admin@example.test','password':'Cedar!928'});local.hospital='H-0004'
    other=local.request('/api/leave/calendar');assert other['hospitalId']=='H-0004' and not any(l['id'] in [leave,current] for l in other['leaves'])
    local.hospital='H-0001';local.request('/api/leave/calendar',expected=403);local.hospital='H-0004'
    volunteer.hospital='H-0004';second=apply(volunteer,start,end)
    local.request('/api/booking/resolve-leave',{'id':second,'status':'Approved'})
    assert any(l['id']==second for l in local.request('/api/leave/calendar')['leaves'])
    assert not any(l['id']==second for l in nurse.request('/api/leave/calendar')['leaves'])
    volunteer.hospital='H-0005';volunteer.request('/api/leave/calendar',expected=403)
    # Cancellation removes a public availability entry but retains its private record.
    admin.request('/api/booking/resolve-leave',{'id':leave,'status':'Cancelled'})
    assert all(l['id']!=leave for l in nurse.request('/api/leave/calendar')['leaves'])
    assert sql("SELECT status FROM hospitalflow.staff_leaves WHERE id='"+leave+"';")=='Cancelled'
    print('PASS: shared approved staff leave, inclusive end dates/days remaining, pending/reason privacy, patient exclusion, hospital isolation and cancellation refresh.')
