using System.Net;
using System.Security.Claims;
using System.Globalization;
using Npgsql;
record DocumentCopy(string Title,string Reference,string Html);
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
static class RecordDocumentEndpoints {
    public static void Map(WebApplication app,Store store){
        app.MapGet("/api/documents/{kind}/{id}",async(string kind,string id,string? mode,HttpContext ctx)=>{
            if(kind is not("appointment" or "prescription" or "invoice" or "admission")||id.Length>100)return Results.NotFound();
            if(mode is not("print" or "download"))return Results.BadRequest();
            var userId=ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!;var patient=await store.PatientAccount(userId)!=null;
            if(!patient&&!Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role))){
                var grants=await store.Permissions(userId);var allowed=kind switch{"appointment"=>new[]{"Reception","Doctor","Nurse"},"prescription"=>new[]{"Doctor","Nurse","Pharmacist"},"invoice"=>new[]{"Billing","Pharmacist"},_=>new[]{"Doctor","Nurse"}};
                if(!allowed.Any(grants.Contains))return Results.Forbid();
                if(kind=="invoice"&&!grants.Contains("Billing")){await using var c=await store.Open();await using var cmd=new NpgsqlCommand("SELECT EXISTS(SELECT 1 FROM hospitalflow.prescription_dispensations WHERE bill_id=$1 AND hospital_id=hf_security.current_hospital())",c);cmd.Parameters.AddWithValue(id);if(!(bool)(await cmd.ExecuteScalarAsync())!)return Results.Forbid();}
            }
            var copy=await store.RecordDocument(kind,id,userId,patient);if(copy==null)return Results.NotFound();
            await store.Log(new AuditContext(ctx.User.Identity!.Name!,userId,ctx.TraceIdentifier,ctx.Connection.RemoteIpAddress?.ToString(),ctx.Request.Method).Event("document-"+mode,kind+":"+id));
            return Results.Ok(copy);
        }).RequireAuthorization();
    }
}
