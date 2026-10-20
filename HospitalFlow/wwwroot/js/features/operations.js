'use strict';
// Business forms share the same audited, idempotent command gateway as the main modules.
const operations=[
 ['hospital-profile','Hospital settings','Hospital profile',[['name','Hospital name']]],
 ['supplier','Procurement','Add supplier',[['code','Supplier code'],['name','Supplier name'],['email','Contact email','email'],['phone','Contact phone']]],
 ['purchase-order','Procurement','Create purchase order',[['supplierId','Supplier','suppliers'],['lines','Order items','order-lines']]],
 ['approve-purchase-order','Procurement','Approve purchase order',[['id','Purchase order','purchase_orders']]],
 ['receive-purchase-order','Procurement','Receive purchase order',[['id','Purchase order','purchase_orders'],['reference','Delivery reference'],['lines','Received items','receipt-lines']]],
 ['hold-batch','Inventory','Quarantine batch',[['medicineId','Medicine batch','medicines'],['reason','Reason']]],
 ['release-batch','Inventory','Release batch hold',[['id','Batch hold','medicine_batch_holds']]],
 ['stock-adjustment','Inventory','Adjust stock',[['id','Medicine batch','medicines'],['quantity','Quantity change (+ receipt / − issue)','signed'],['reason','Reason']]],
 ['reserve-prescription','Inventory','Reserve prescription stock',[['id','Prescription','prescriptions']]],
 ['release-reservation','Inventory','Release stock reservation',[['id','Reservation','stock_reservations']]],
 ['cancel-prescription','Clinical','Cancel pending prescription',[['id','Prescription','prescriptions']]],
 ['service','Finance','Add service',[['code','Service code'],['name','Service name'],['department','Department','departments'],['category','Category']]],
 ['service-price','Finance','Set service price',[['serviceId','Service','service_catalog'],['amount','Amount (INR)','number'],['effectiveFrom','Effective from','datetime-local']]],
 ['service-charge','Finance','Charge a service',[['id','Invoice','bills'],['serviceId','Service','service_catalog'],['quantity','Quantity','number']]],
 ['reverse-payment','Finance','Reverse recorded payment',[['id','Payment','payments'],['amount','Reversal amount (INR)','number'],['reason','Reason']]],
 ['provider-session','Workforce','Add provider session',[['doctorId','Provider','doctors'],['startsAt','Starts at','datetime-local'],['endsAt','Ends at','datetime-local']]],
 ['provider-absence','Workforce','Record provider absence',[['doctorId','Provider','doctors'],['startsAt','Starts at','datetime-local'],['endsAt','Ends at','datetime-local'],['reasonCode','Reason code']]],
 ['cancel-absence','Workforce','Cancel provider absence',[['id','Provider absence','provider_absences']]],
 ['staff-member','Workforce','Add staff member',[['userId','User','users'],['doctorId','Provider','doctors'],['employeeNumber','Employee number'],['department','Department','departments'],['jobTitle','Job title']]],
 ['grant-department','Access','Assign user department',[['userId','User','users'],['department','Department','departments']]],
 ['ward-department','Access','Assign ward department',[['ward','Ward','wards'],['department','Department','departments']]],
 ['grant-patient-access','Access','Grant patient access',[['userId','User','users'],['patientId','Patient','patients'],['purpose','Purpose'],['expiresAt','Expires at','datetime-local']]],
 ['patient-contact','Patients','Add patient contact',[['patientId','Patient','patients'],['name','Contact name'],['relationship','Relationship'],['phone','Phone'],['isEmergency','Emergency contact','boolean']]],
 ['patient-consent','Patients','Record patient consent',[['patientId','Patient','patients'],['purpose','Consent purpose'],['expiresAt','Expires at','datetime-local'],['evidenceReference','Evidence reference']]],
 ['revoke-consent','Patients','Revoke consent',[['id','Consent','patient_consents']]],
 ['discharge-task','Patient flow','Add discharge task',[['admissionId','Admission','admissions'],['code','Task code'],['required','Required for discharge','boolean']]],
 ['complete-discharge-task','Patient flow','Complete discharge task',[['id','Discharge task','discharge_tasks']]],
 ['follow-up','Patient flow','Schedule follow-up',[['patientId','Patient','patients'],['admissionId','Admission','admissions'],['doctorId','Provider','doctors'],['dueAt','Due at','datetime-local'],['instructions','Instructions','textarea']]],
 ['book-follow-up','Patient flow','Book follow-up appointment',[['id','Follow-up','follow_ups'],['doctorId','Provider','doctors'],['at','Appointment time','datetime-local']]],
 ['clinical-order','Clinical','Create clinical order',[['encounterId','Encounter','encounters'],['serviceId','Service','service_catalog']]],
 ['clinical-order-status','Clinical','Update clinical order',[['id','Clinical order','clinical_orders'],['status','Status','order-status']]],
 ['complete-clinical-order','Clinical','Complete clinical order',[['id','Clinical order','clinical_orders']]],
 ['notification-ack','Operations','Acknowledge notification',[['id','Notification','notifications'],['reason','Acknowledgement note']]]
];
const operationRecords=[['suppliers','Suppliers'],['purchase_orders','Purchase orders'],['purchase_order_lines','Purchase order items'],['goods_receipts','Goods receipts'],['medicine_batch_holds','Batch holds'],['stock_reservations','Stock reservations'],['service_catalog','Services'],['service_prices','Service prices'],['payment_reversals','Payment reversals'],['provider_sessions','Provider sessions'],['provider_absences','Provider absences'],['staff_members','Staff members'],['patient_contacts','Patient contacts'],['patient_consents','Patient consents'],['patient_access_grants','Patient access grants'],['discharge_tasks','Discharge checklist'],['follow_ups','Follow-ups'],['clinical_orders','Clinical orders']];

const clinicalOperationNames=["prescription","cancel-prescription","note","clinical-order","clinical-order-status","complete-clinical-order","follow-up"];
function availableOperations(){return operations.filter(o=>me.role!=="Admin"||!clinicalOperationNames.includes(o[0]));}
