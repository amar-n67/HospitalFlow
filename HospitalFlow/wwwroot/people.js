'use strict';
function personRole(person){return person.patientId?'Patient (User)':person.role==='User'?'User (limited)':person.role;}
function renderPeople(){
 return heading('People & registrations','Register the right person type and maintain contact details.','register-person','Add person')+`<section class="panel">${toolbar('Search ID, name, email, mobile, role or job')}${table(['Registration ID','Name','Type / job','Email','Mobile','DOB','Age','Department','Status','Actions'],(state.people||[]).filter(p=>matches(p.registrationId,p.name,p.email,p.mobile,p.role,p.occupation)).map(p=>[esc(p.registrationId),`<strong>${esc(p.name)}</strong>`,esc(personRole(p))+((p.occupation||p.jobTitle)?'<small>'+esc(p.occupation||p.jobTitle)+'</small>':''),esc(p.email),esc(p.mobile||'Not recorded'),p.dob?date(p.dob):'Not recorded',ageLabel(p.dob),esc(p.department||'—'),badge(p.active?'Active':'Inactive'),p.patientId?btn('Patient details','patient-detail',p.patientId):(['Admin','Developer','Doctor','Nurse','Volunteer'].includes(p.role)?btn('Edit details','person-edit',p.id):'—')]))}</section><div class="info">IDs are generated automatically: A for Admin, D for Doctor, N for Nurse, P for Patient, V for Volunteer and DEV for Developer. Admin and Doctor are separate roles: choose Admin for hospital management, Doctor for clinical work, and Developer for both. Existing links and history remain intact.</div>`;
}
function personForm(action,id){
 const existing=action==='person-edit'?(state.people||[]).find(p=>p.id===id):null;
 if(action==='person-edit'&&!existing){toast('Refresh the directory and try again.');return;}
 const types=fullAccess()?['Patient','Doctor','Nurse','Volunteer','Admin','Developer']:['Patient','Doctor','Nurse','Volunteer'];
 const selected=existing?.role||'Patient';
 const selector=`<label>Adding / editing<select id="person-type" name="role" required ${existing?'disabled':''}>${types.map(role=>`<option ${role===selected?'selected':''}>${role}</option>`).join('')}</select></label>`;
 openModal(existing?'Edit person details':'Add a person',selector+'<div id="person-fields"></div>',existing?'person-update':'person-register',id||'');
 function fields(){
  const role=$('#person-type').value;
  if(role==='Patient'){$('#person-fields').innerHTML=field('name','Full name')+field('email','Patient email','email')+field('phone','Mobile number','tel')+field('dob','Date of birth','date')+field('sex','Sex','select','',['Male','Female','Other','Prefer not to say'].map(v=>option(v,v)).join(''))+optionalField('address','Address (optional)','textarea')+optionalField('emergencyContact','Emergency contact (optional)')+'<p class="field-help">A P ID is generated automatically. First login uses 1234, followed by registered DOB verification and a required password change. Private email/SMS invitations carry the access instructions.</p>';return;}
  const prefix={Admin:'A',Developer:'DEV',Doctor:'D',Nurse:'N',Volunteer:'V'}[role];
  let html=`<p class="field-help">${existing?'Registration ID: '+esc(existing.registrationId):'A '+prefix+' registration ID will be generated automatically.'}</p>`+field('name','Full name')+field('email','Login email','email')+field('mobile','Mobile number','tel')+field('dob','Date of birth','date')+field('sex','Sex','select','',['Male','Female','Other','Prefer not to say'].map(v=>option(v,v)).join(''))+optionalField('address','Address (optional)','textarea')+field('jobTitle','Job title');
  if(role==='Doctor'||role==='Nurse')html+=field('department','Department');
  if(role==='Doctor')html+=field('start','Shift start','time','09:00')+field('end','Shift end','time','17:00');
  if(role==='Volunteer')html+=field('occupation','Volunteer / support job','select','',['Guard','Washerman','Housekeeping','Other'].map(v=>option(v,v)).join(''));
  if(!existing)html+='<p class="field-help">First login password: <strong>1234</strong>. Verify the registered date of birth and choose a new password before accessing the workspace.</p>';
  $('#person-fields').innerHTML=html;
  if(existing){for(const name of ['name','email','mobile','dob','sex','address','department','jobTitle','occupation']){const input=$('#person-fields').querySelector(`[name="${name}"]`);if(input)input.value=existing[name]||'';}$('#person-fields [name="email"]').readOnly=true;if(existing.doctorId){const doctor=state.doctors.find(d=>d.id===existing.doctorId);if(doctor){$('#person-fields [name="start"]').value=doctor.start;$('#person-fields [name="end"]').value=doctor.end;}}}
 }
 $('#person-type').onchange=fields;fields();
}
