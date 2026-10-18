'use strict';
function renderPatient(){
 const menus=[['patient-home','◫','My profile'],['patient-appointments','▦','My appointments'],['patient-billing','▧','My invoices']];
 page=location.hash.slice(1);if(!menus.some(m=>m[0]===page))page='patient-home';
 $('#nav').innerHTML=menus.map(m=>`<a href="#${m[0]}" class="${page===m[0]?'active':''}"><span>${m[1]}</span>${m[2]}</a>`).join('');$('#breadcrumb').textContent=menus.find(m=>m[0]===page)[2];$('.aside-bottom p').textContent='Your private patient workspace';$('#alert-count').textContent='0';
 if(page!==lastLoggedPage){lastLoggedPage=page;api('/api/activity',{event:'page-view',reference:page}).catch(e=>toast(e.message));}
 const p=state.patients[0];let html=heading('My patient workspace','Your records, appointments and invoices.');
 if(page==='patient-home')html+=panel('Patient profile','Registered details · contact the hospital for corrections',`<div class="info"><h3>${esc(p.name)}</h3><p><b>Patient ID:</b> ${esc(p.id)}</p><p><b>Email:</b> ${esc(me.email)}</p><p><b>Date of birth:</b> ${date(p.dob)}</p><p><b>Mobile:</b> ${esc(p.phone)}</p><button class="secondary" data-action="password-change">Change password</button></div>`)+panel('My admissions','Your recorded inpatient stays',table(['Admission','Admitted','Status','Bed'],state.admissions.map(a=>[esc(a.id),date(a.at),badge(a.status),esc(a.bedId)])));
 if(page==='patient-appointments')html=heading('My appointments','Visits registered under your patient ID.')+panel('Appointment history','Contact the hospital to book or change an appointment',table(['Reference','Doctor','Date and time','Status'],state.appointments.map(a=>[esc(a.id),esc(doctor(a.doctorId).name),date(a.at)+' '+time(a.at),badge(a.status)])));
 if(page==='patient-billing')html=heading('My invoices','Your recorded charges and receipts.')+panel('Invoice history','Payments are recorded by the hospital billing team',table(['Invoice','Total','Paid','Balance','Details'],state.bills.map(b=>[esc(b.id),money(b.total),money(b.paid),money(b.balance),btn('View invoice','invoice',b.id)])));
 $('#main').innerHTML=html;
}
