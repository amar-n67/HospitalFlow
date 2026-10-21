using System.Net;
using System.Security.Claims;
using System.Globalization;
using Npgsql;
sealed partial class Store {
    public async Task<DocumentCopy?> RecordDocument(string kind,string id,string userId,bool patient){
        var s=patient?await PatientState(userId,true):await Current();
        string patientId,title,details;
        string E(object? v)=>WebUtility.HtmlEncode(v?.ToString()??"");
        string Row(string label,object? value)=>$"<tr><th>{E(label)}</th><td>{E(value)}</td></tr>";
        string At(DateTimeOffset value)=>TimeZoneInfo.ConvertTime(value,TimeZoneInfo.FindSystemTimeZoneById(HospitalTimezone)).ToString("dd MMM yyyy, hh:mm tt",CultureInfo.InvariantCulture)+" IST";
        string Money(decimal value)=>"INR "+value.ToString("0.00",CultureInfo.InvariantCulture);
        if(kind=="appointment"){
            var a=s.Appointments.FirstOrDefault(a=>a.Id==id);if(a==null)return null;patientId=a.PatientId;title="Appointment record";var d=s.Doctors.FirstOrDefault(d=>d.Id==a.DoctorId);
            details="<table>"+Row("Appointment reference",a.Id)+Row("Doctor",d?.Name??a.DoctorId)+Row("Department",d?.Department)+Row("Appointment",At(a.At))+Row("Visit type",a.Type)+Row("Current status",a.Status)+"</table><p>Manage future scheduled appointments from My appointments, or contact the hospital. This copy reflects the status when generated.</p>";
            await using(var c=await Open())await using(var cmd=new NpgsqlCommand("SELECT amount,method,state,payment_mode,id::text FROM hospitalflow.appointment_bookings WHERE appointment_id=$1",c)){
                cmd.Parameters.AddWithValue(id);await using var r=await cmd.ExecuteReaderAsync();
                if(await r.ReadAsync())details+="<h2>Booking payment</h2><table>"+Row("Payment reference",r.GetString(4))+Row("Fee",Money(r.GetDecimal(0)))+Row("Method",r.GetString(1))+Row("Payment / refund status",r.GetString(2))+Row("Mode",r.GetString(3))+"</table>"+(r.GetString(3)=="Test"?"<p><strong>TEST PAYMENT: No real money was charged or refunded.</strong></p>":"");
            }
        }else if(kind=="prescription"){
            var r=s.Prescriptions.FirstOrDefault(r=>r.Id==id);if(r==null)return null;patientId=r.PatientId;title="Prescription record";
            var medicine=s.Medicines.FirstOrDefault(m=>m.Id==r.MedicineId)?.Name??s.CareMedicines.FirstOrDefault(m=>m.Id==r.MedicineId)?.Name??r.MedicineId;
            string? author=null;await using(var c=await Open())await using(var cmd=new NpgsqlCommand("SELECT u.name FROM hospitalflow.prescription_authors a JOIN hospitalflow.users u ON u.id=a.created_by WHERE a.prescription_id=$1",c)){cmd.Parameters.AddWithValue(id);author=await cmd.ExecuteScalarAsync() as string;}
            details="<table>"+Row("Prescription reference",r.Id)+Row("Recorded by",author??"Not recorded")+Row("Medicine",medicine)+Row("Quantity",r.Quantity)+Row("Status",r.Status)+"</table><h2>Clinician instructions</h2><p class='instructions'>"+E(r.Instructions)+"</p><p>Copy of the hospital record. Follow the treating clinician's instructions; this copy does not add or change treatment.</p>";
        }else if(kind=="invoice"){
            var b=s.Bills.FirstOrDefault(b=>b.Id==id);if(b==null)return null;patientId=b.PatientId;title="Invoice and payment receipts";
            details="<table><tr><th>Description</th><th>Amount</th></tr>"+string.Concat(b.Lines.Select(l=>$"<tr><td>{E(l.Description)}</td><td>{E(Money(l.Amount))}</td></tr>"))+Row("Total",Money(b.Total))+Row("Paid",Money(b.Paid))+Row("Balance",Money(b.Balance))+"</table><h2>Payment receipts</h2><table><tr><th>Reference</th><th>Date</th><th>Method</th><th>Amount</th></tr>"+string.Concat(b.Payments.Select(p=>$"<tr><td>{E(p.Id)}</td><td>{E(At(p.At))}</td><td>{E(p.Method)}</td><td>{E(Money(p.Amount))}</td></tr>"))+"</table><p>This is a copy of recorded charges and payments, not proof of any unrecorded payment.</p>";
        }else if(kind=="discharge-summary"){
            var a=s.Admissions.FirstOrDefault(a=>a.Id==id);if(a==null)return null;patientId=a.PatientId;title="Discharge summary";
            await using var c=await Open();await using var cmd=new NpgsqlCommand("SELECT (to_jsonb(r)||jsonb_build_object('doctor_name',d.name,'nurse_name',n.name))::text FROM hospitalflow.care_discharge_reviews r JOIN hospitalflow.users n ON n.id=r.nurse_id LEFT JOIN hospitalflow.users d ON d.id=r.doctor_id WHERE r.admission_id=$1 AND r.hospital_id=hf_security.current_hospital() AND hf_security.can_read_care(r.patient_id)",c);cmd.Parameters.AddWithValue(id);
            var raw=await cmd.ExecuteScalarAsync() as string;if(raw==null)return null;var review=System.Text.Json.JsonDocument.Parse(raw).RootElement;
            string Value(string key)=>review.TryGetProperty(key,out var v)&&v.ValueKind!=System.Text.Json.JsonValueKind.Null?v.ToString():"Awaiting review";
            details="<table>"+Row("Admission",id)+Row("Admission date",At(a.At))+Row("Discharged",a.Discharged is {} when?At(when):"Not finalized")+Row("Doctor",Value("doctor_name"))+Row("Doctor approval timestamp",Value("approved_at"))+Row("Nurse",Value("nurse_name"))+Row("Nurse preparation timestamp",Value("prepared_at"))+Row("Nurse completion timestamp",Value("completed_at"))+"</table>";
            foreach(var key in new[]{"diagnosis","treatment","final_condition","discharge_medications","follow_up","doctor_remarks","nurse_remarks"})details+="<h2>"+E(key.Replace('_',' '))+"</h2><p class='instructions'>"+E(Value(key))+"</p>";
            await using var medications=new NpgsqlCommand("SELECT m.name,d.dose,d.quantity,d.status,d.actual_at,u.name,d.remarks FROM hospitalflow.medication_doses d JOIN hospitalflow.prescriptions p ON p.id=d.prescription_id JOIN hospitalflow.medicine_batches m ON m.id=p.medicine_id LEFT JOIN hospitalflow.users u ON u.id=d.recorded_by WHERE d.admission_id=$1 ORDER BY d.scheduled_at",c);medications.Parameters.AddWithValue(id);
            details+="<h2>Medication administration record</h2><table><tr><th>Medicine / dose</th><th>Quantity / outcome</th><th>Actual administration / nurse</th><th>Remarks</th></tr>";
            await using(var r=await medications.ExecuteReaderAsync()){while(await r.ReadAsync())details+="<tr><td>"+E(r.GetString(0))+"<br>"+E(r.GetString(1))+"</td><td>"+r.GetInt32(2)+" · "+E(r.GetString(3))+"</td><td>"+(r.IsDBNull(4)?"—":E(At(new DateTimeOffset(r.GetDateTime(4),TimeSpan.Zero))))+"<br>"+(r.IsDBNull(5)?"—":E(r.GetString(5)))+"</td><td>"+(r.IsDBNull(6)?"—":E(r.GetString(6)))+"</td></tr>";}
            details+="</table><p>This copy reflects the recorded approval/finalization state when generated.</p>";
        }else{
            var a=s.Admissions.FirstOrDefault(a=>a.Id==id);if(a==null)return null;patientId=a.PatientId;title="Admission record";
            details="<table>"+Row("Admission",a.Id)+Row("Admitted",At(a.At))+Row("Bed",a.BedId)+Row("Status",a.Status)+Row("Discharged",a.Discharged is {} end?At(end):"Not discharged")+"</table>";
        }
        var p=s.Patients.Single(p=>p.Id==patientId);
        var showMobile=patient||Access.Full((await UserById(userId))?.Role)||(await Permissions(userId)).Any(p=>p is "Reception" or "Doctor" or "Nurse");
        var html=$"<article class='record-document'><header><b>HospitalFlow</b><span>Patient services</span></header><h1>{E(title)}</h1><p class='reference'>Reference: {E(id)}</p><h2>Patient details</h2><table>{Row("Patient ID",p.RegistrationId??p.Id)}{Row("Name",p.Name)}{Row("Date of birth",p.Dob)}{Row("Email",p.Email)}{Row("Mobile",showMobile?p.Phone:"Restricted")}</table>{details}<footer>Generated {E(At(DateTimeOffset.UtcNow))}. Contains private patient information.</footer></article>";
        return new(title,id,html);
    }
}
