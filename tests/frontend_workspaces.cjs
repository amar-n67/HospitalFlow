const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
const ctx={console,URL,Blob,setInterval:()=>{},document:{addEventListener(){},querySelectorAll:()=>[]},me:{},state:{},page:'dashboard',menus:[]};
vm.createContext(ctx);
for(const file of ['medications.js','validation.js','workspaces.js','documents.js','overview.js'])vm.runInContext(fs.readFileSync('HospitalFlow/wwwroot/'+file,'utf8'),ctx);
vm.runInContext(`
var esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
var stats=rows=>rows.map(r=>r.join(' ')).join(' '),panel=(a,b,c,d='')=>a+b+c+d,table=(h,r)=>h.join(' ')+r.flat().join(' '),heading=(a,b)=>a+b;
var date=v=>v,time=v=>v,money=v=>'INR '+v,patient=id=>state.patients.find(p=>p.id===id),patientCode=p=>p.registrationId,doctor=id=>({name:'Doctor',department:'General'}),initials=n=>n[0],person=id=>patient(id)?.name||id,badge=v=>v,btn=(a,b,id)=>a+id,fullAccess=()=>me.role==='Admin',can=roles=>fullAccess()||roles.some(r=>(me.permissions||[]).includes(r)),pageAccess=()=>true,alerts=()=>[],alertList=()=>'';
me={name:'Synthetic Patient',email:'patient@example.test',role:'User',patientId:'p',permissions:[]};
state={patients:[{id:'p',registrationId:'P-001',name:'Synthetic Patient',phone:'9000012345',dob:'2002-01-01',sex:'Other'}],appointments:[],prescriptions:[],admissions:[],bills:[],workTasks:[],beds:[],medicines:[]};
`,ctx);
assert.match(vm.runInContext('patientOverview()',ctx),/Your next appointment/);
assert.match(vm.runInContext('patientOverview()',ctx),/My invoices/);
assert.match(vm.runInContext('documentButtons("invoice","INV-1")',ctx),/data-mode="print"/);
for(const bad of ['123456789','12345678901','+919000012345','90000 12345','１２３４５６７８９０']){ctx.bad=bad;assert.throws(()=>vm.runInContext('validateMobile(bad)',ctx));}
assert.equal(vm.runInContext('validateMobile("9000012345")',ctx),'9000012345');
for(const role of ['Admin','Doctor','Nurse','Volunteer','User']){ctx.role=role;vm.runInContext("me={name:'Colleague',role,permissions:role==='Doctor'?['Doctor']:[],profile:{},registrationId:'TEST-001'}",ctx);assert.ok(vm.runInContext('roleOverview()',ctx).length>50);}
vm.runInContext("me={name:'Billing',role:'User',permissions:['Billing'],profile:{}}",ctx);assert.match(vm.runInContext('roleOverview()',ctx),/Invoices awaiting payment/);
assert.doesNotMatch(vm.runInContext('roleOverview()',ctx),/Today’s visit queue/);
console.log('PASS: patient/staff/nurse/volunteer overview rendering, billing-specific priorities, document buttons and mobile validation.');
vm.runInContext(fs.readFileSync('HospitalFlow/wwwroot/network.js','utf8'),ctx);
vm.runInContext(`
var matches=()=>true,toolbar=()=>'',option=(v,t)=>'<option>'+t+'</option>';
me={role:'Doctor',permissions:['Doctor'],name:'Colleague',canManageNetwork:false};
state.network={hospitals:[{id:'H-1',name:'Example A',address:'Example road',city:'City',state:'State',postalCode:'560001',isDemo:true,active:true,acceptingReferrals:true},{id:'H-2',name:'Example B',address:'Example avenue',city:'Town',state:'State',postalCode:'560002',isDemo:true,active:true,acceptingReferrals:true}],providers:[],access:['H-1'],referrals:[]};
var activeHospital='H-1';
var tree={patient:{id:'p',name:'Synthetic Patient',registrationId:'P-001'},scope:'Own records',registrations:[{hospitalId:'H-1',at:'2026-01-01'}],events:[{hospitalId:'H-1',kind:'Appointment',reference:'APT-1',at:'2026-01-01',status:'Completed'}],referrals:[{sourceHospitalId:'H-1',targetHospitalId:'H-2',status:'Accepted',at:'2026-02-01',reason:'<script>test</script>'}]};
`,ctx);
assert.match(vm.runInContext('hospitalsPage()',ctx),/Refer patient here/);
assert.match(vm.runInContext('historyTree(tree)',ctx),/Example B/);
assert.match(vm.runInContext('historyTree(tree)',ctx),/&lt;script&gt;/);
vm.runInContext("me={role:'Nurse',permissions:['Nurse']}",ctx);assert.equal(vm.runInContext("historyDocumentAllowed('Invoice')",ctx),false);
console.log('PASS: hospital directory, referral controls, retained history tree, HTML escaping and document permissions.');
vm.runInContext(fs.readFileSync('HospitalFlow/wwwroot/booking.js','utf8'),ctx);
vm.runInContext(`
heading=(...args)=>args.join(' ');
me={id:'patient-user',patientId:'p',role:'User'};
state={patients:[{id:'p',name:'Patient',registrationId:'P-001'}],appointments:[{id:'APT-X',patientId:'p',doctorId:'d',at:'2099-01-01T10:00:00Z',status:'Scheduled'}],booking:{paymentMode:'Test',data:{fee:200,doctors:[{id:'d',name:'Test doctor'}],bookings:[{id:'hold',appointment_id:'APT-X',patient_id:'p',doctor_id:'d',state:'Paid',amount:200,method:'UPI',payment_mode:'Test'}],unavailable:['APT-X'],attendance:[],leaves:[],staff:[]}}};
`,ctx);
const bookingHtml=vm.runInContext('patientAppointmentsPage()',ctx);
assert.match(bookingHtml,/TEST PAYMENTS/);assert.match(bookingHtml,/Reschedule/);assert.match(bookingHtml,/Cancel &amp; refund|Cancel & refund/);assert.match(bookingHtml,/Doctor absent/);assert.match(bookingHtml,/Paid/);
vm.runInContext("me={id:'nurse',role:'Nurse'}",ctx);const attendanceHtml=vm.runInContext('attendancePage()',ctx);assert.match(attendanceHtml,/Apply for leave/);assert.match(attendanceHtml,/Check in today/);assert.doesNotMatch(attendanceHtml,/Configure booking fee/);
console.log('PASS: patient booking controls, absent doctor warnings, test payment labels and non-admin attendance controls.');

vm.runInContext("me={id:'admin',role:'Admin'};state.booking.data.canReviewAttendance=true;state.booking.data.attendance=[{id:'ATT-1',user_id:'nurse',name:'Nurse',day:'2026-10-19',status:'Present',approval_status:'Pending'}]",ctx);
const reviewHtml=vm.runInContext('attendancePage()',ctx);assert.match(reviewHtml,/Approve/);assert.match(reviewHtml,/Reject/);assert.match(reviewHtml,/awaiting your review/);
vm.runInContext("me={id:'nurse',role:'Nurse'};state.booking.data.canReviewAttendance=false",ctx);assert.doesNotMatch(vm.runInContext('attendancePage()',ctx),/ApproveATT-1|RejectATT-1/);
console.log('PASS: attendance approval queue and staff-only request visibility controls.');

vm.runInContext("me={id:'admin',role:'Admin'};state.booking.data.canReviewAttendance=true;state.booking.data.attendance=[{id:'SELF',user_id:'admin',name:'Admin',day:'2026-10-19',status:'Present',approval_status:'Pending',check_out:'2026-10-19T17:30:00+05:30',total_seconds:30600}]",ctx);
const selfReview=vm.runInContext('attendancePage()',ctx);assert.match(selfReview,/ApproveSELF/);assert.match(selfReview,/8h 30m 00s/);assert.match(selfReview,/Manage employee attendance/);
assert.match(vm.runInContext("attendanceDuration({status:'Present',elapsedSeconds:3600,approval_status:'Pending'})",ctx),/In progress/);
console.log('PASS: administrator self-approval controls and daily attendance duration display.');

vm.runInContext("state.leaveCalendar={hospitalName:'<script>bad</script>',leaves:[{name:'<b>Colleague</b>',registrationId:'N-123',role:'Nurse',department:'Ward',startsOn:'2026-10-19',endsOn:'2026-10-21',availability:'On leave',daysRemaining:3}]}",ctx);
const leaveHtml=vm.runInContext('hospitalLeavePage()',ctx);assert.match(leaveHtml,/On leave until/);assert.match(leaveHtml,/3 day/);assert.match(leaveHtml,/&lt;b&gt;Colleague/);assert.doesNotMatch(leaveHtml,/<script>|<b>Colleague/);
console.log('PASS: shared hospital leave calendar, inclusive leave dates and escaped staff/hospital names.');

const accessCtx={me:{role:'Admin',permissions:[]}};vm.createContext(accessCtx);const appSource=fs.readFileSync('HospitalFlow/wwwroot/app.js','utf8');for(const name of ['fullAccess','canClinical','can']){const definition=appSource.split('\n').find(line=>line.startsWith('const '+name+'='));assert.ok(definition);vm.runInContext(definition,accessCtx);}
assert.equal(vm.runInContext('fullAccess()',accessCtx),true);assert.equal(vm.runInContext('canClinical(["Doctor"])',accessCtx),false);
accessCtx.me={role:'Doctor',permissions:['Doctor']};assert.equal(vm.runInContext('canClinical(["Doctor"])',accessCtx),true);assert.equal(vm.runInContext('fullAccess()',accessCtx),false);
accessCtx.me={role:'Developer',permissions:[]};assert.equal(vm.runInContext('canClinical(["Doctor"])',accessCtx),true);assert.equal(vm.runInContext('fullAccess()',accessCtx),true);
vm.runInContext(fs.readFileSync('HospitalFlow/wwwroot/operations.js','utf8'),accessCtx);accessCtx.me={role:'Admin'};assert.equal(vm.runInContext('availableOperations().some(o=>o[0]==="clinical-order")',accessCtx),false);accessCtx.me={role:'Developer'};assert.equal(vm.runInContext('availableOperations().some(o=>o[0]==="clinical-order")',accessCtx),true);
console.log('PASS: Admin management versus Doctor clinical controls, with Developer access to both.');
vm.runInContext(appSource.split('\n').find(line=>line.startsWith('const pageAccess=')),accessCtx);
accessCtx.me={role:'Nurse',permissions:['Nurse']};assert.equal(vm.runInContext('pageAccess("hospitals")',accessCtx),false);assert.equal(vm.runInContext('pageAccess("referrals")',accessCtx),false);assert.equal(vm.runInContext('pageAccess("clinical")',accessCtx),true);
vm.runInContext(`me={role:'Nurse'};state.medicationCare={prescriptions:[{id:'RX-1',patientId:'p',patientName:'<b>Patient</b>',patientCode:'P-001',medicine:'Medicine',instructions:'Clinician instructions',quantity:3,provided:1,status:'Dispensed'}],administrations:[{id:'a',prescriptionId:'RX-1',quantity:1,providedAt:'2026-10-19T12:00:00Z',providedBy:'Nurse',staffId:'N-001',note:'<script>note</script>'}]}`,ctx);
const medicationHtml=vm.runInContext('medicationCarePanel()',ctx);assert.match(medicationHtml,/Record provided/);assert.match(medicationHtml,/N-001/);assert.match(medicationHtml,/2026-10-19/);assert.match(medicationHtml,/&lt;script&gt;note/);
vm.runInContext("me={role:'User',patientId:'p'}",ctx);assert.doesNotMatch(vm.runInContext('medicationCarePanel()',ctx),/Record provided/);
console.log('PASS: Nurse network/referral navigation restrictions and escaped medication administration records with patient read-only controls.');
vm.runInContext("state.medicationCare.visits=['APT-OWN'];me={role:'Doctor',permissions:['Doctor']}",ctx);
assert.match(vm.runInContext("visitPrescriptionButton({id:'APT-OWN',status:'In consultation'})",ctx),/Prescribe \/ history/);
assert.equal(vm.runInContext("visitPrescriptionButton({id:'APT-OTHER',status:'In consultation'})",ctx),'');
assert.equal(vm.runInContext("visitPrescriptionButton({id:'APT-OWN',status:'Scheduled'})",ctx),'');
vm.runInContext("me={role:'User',permissions:['Pharmacist']};state.medicationCare.prescriptions[0].status='Pending'",ctx);
assert.match(vm.runInContext('medicationCarePanel()',ctx),/Dispense & invoice/);
console.log('PASS: assigned-visit prescription controls and pharmacy dispensing/invoice actions.');
vm.runInContext(`
var capturedModal=null;var modalForm={};var openModal=(title,html,action)=>{capturedModal={title,html,action};};var $=()=>modalForm;var field=(name,label)=>'<input name="'+name+'">',option=(id,label)=>'<option>'+label+'</option>';
state.appointments=[{id:'APT-OWN',patientId:'p',doctorId:'D-1',at:'2026-10-19T12:00:00Z',status:'In consultation'}];state.medicationCare.visits=[];me={role:'Admin',permissions:[]};
openVisitPrescription('APT-OWN');
`,ctx);
assert.match(vm.runInContext('capturedModal.title',ctx),/Read-only/);assert.match(vm.runInContext('capturedModal.html',ctx),/assigned Doctor/);assert.equal(vm.runInContext('capturedModal.action',ctx),'');assert.doesNotMatch(vm.runInContext('capturedModal.html',ctx),/name="medicineId"/);
assert.match(vm.runInContext("visitPrescriptionButton(state.appointments[0])",ctx),/View prescriptions/);
vm.runInContext("me={role:'Doctor',permissions:['Doctor']};state.medicines=[];state.medicationCare.visits=['APT-OWN'];openVisitPrescription('APT-OWN');",ctx);
assert.equal(vm.runInContext('capturedModal.action',ctx),'visit-prescription');assert.match(vm.runInContext('capturedModal.html',ctx),/name="medicineId"/);assert.match(vm.runInContext('capturedModal.html',ctx),/P-001/);assert.equal(vm.runInContext('typeof modalForm.onsubmit',ctx),'function');
assert.ok(appSource.includes("if(action==='appointment-status'&&el.dataset.extra==='In consultation')openVisitPrescription(id)"));
console.log('PASS: Start visit opens Admin read-only history and assigned Doctor prescription form; existing visits can reopen the dialog.');
