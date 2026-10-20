'use strict';
function renderPatient(){
 const menus=[['care-flow','♡','Care timeline & hospital stay'],['patient-home','◫','Overview'],['hospitals','▥','Hospital network'],['hospital-history','♧','Hospital history'],['referrals','⇄','My referrals'],['patient-care','♡','My care'],['patient-appointments','▦','My appointments'],['patient-billing','▧','My invoices'],['profile','♙','Edit my profile']];
 page=location.hash.slice(1);if(!menus.some(m=>m[0]===page))page='patient-home';
 $('#nav').innerHTML=menus.map(m=>`<a href="#${m[0]}" class="${page===m[0]?'active':''}"><span>${m[1]}</span>${m[2]}</a>`).join('');$('#breadcrumb').textContent=menus.find(m=>m[0]===page)[2];$('.aside-bottom p').textContent='Your private patient workspace';$('#alert-count').textContent='0';
 if(page!==lastLoggedPage){lastLoggedPage=page;api('/api/activity',{event:'page-view',reference:page}).catch(e=>toast(e.message));}
 const p=state.patients[0];let html=heading('My patient workspace','Your records, appointments and invoices.');
 if(page==='patient-home')html=patientOverview()+state.appointments.filter(a=>bookingData().unavailable.includes(a.id)).map(a=>`<div class="info">${esc(doctor(a.doctorId).name)} · ${date(a.at)} ${time(a.at)}${bookingWarning(a)}${bookingChangeButtons(a)}</div>`).join('');
 if(page==='patient-appointments')html=patientAppointmentsPage();
 if(page==='patient-billing')html=heading('My invoices','Your recorded charges and receipts.')+panel('Invoice history','Payments are recorded by the hospital billing team',table(['Invoice','Total','Paid','Balance','Details'],state.bills.map(b=>[esc(b.id),money(b.total),money(b.paid),money(b.balance),btn('View invoice','invoice',b.id)+documentButtons('invoice',b.id)])));
 if(page==='profile')html=profilePage();
 if(page==='patient-care')html=heading('My care','Your recorded prescriptions and inpatient stays.')+panel('Prescriptions','Follow the instructions from your treating clinician. Contact the hospital with questions.',table(['Prescription','Medicine','Quantity','Instructions','Status','Documents'],state.prescriptions.map(r=>[esc(r.id),esc((state.careMedicines||[]).find(m=>m.id===r.medicineId)?.name||r.medicineId),esc(r.quantity),esc(r.instructions),badge(r.status),documentButtons('prescription',r.id)])))+panel('Inpatient history','Admissions recorded under your patient ID',table(['Admission','Admitted','Discharged','Status','Documents'],state.admissions.map(a=>[esc(a.id),date(a.at),a.discharged?date(a.discharged):'—',badge(a.status),documentButtons('admission',a.id)])));
 if(page==='patient-care')html+=medicationCarePanel();if(page==='care-flow')html=careFlowPage();
 if(page==='hospitals')html=hospitalsPage();if(page==='referrals')html=referralsPage();if(page==='hospital-history')html=historyPage();updateHospitalSwitcher();
 updatePageJump(menus);
 $('#main').innerHTML=html;
}
