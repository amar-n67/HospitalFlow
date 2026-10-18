using System.Text.Json;
using Microsoft.AspNetCore.Identity;

static class Workflows {
 static string Id(string prefix)=>prefix+"-"+Guid.NewGuid().ToString("N")[..10];
 static string Text(JsonElement j,string k,int max=500) {if(!j.TryGetProperty(k,out var p)||p.ValueKind!=JsonValueKind.String)throw new RuleException($"{k} is required.");var v=p.GetString()!.Trim();if(v.Length==0||v.Length>max)throw new RuleException($"{k} must contain 1–{max} characters.");return v;}
 static int Num(JsonElement j,string k) {if(!j.TryGetProperty(k,out var p)||!p.TryGetInt32(out var n)||n<1||n>100000)throw new RuleException($"{k} must be a positive whole number.");return n;}
 static decimal Money(JsonElement j,string k) {if(!j.TryGetProperty(k,out var p)||!p.TryGetDecimal(out var n)||n<=0||n>10000000||decimal.Round(n,2)!=n)throw new RuleException($"{k} must be a positive amount with up to two decimals.");return n;}
 static T Find<T>(IEnumerable<T> list,Func<T,bool> predicate)=>list.FirstOrDefault(predicate)??throw new RuleException("The selected record no longer exists.");
 static void Patient(State s,string id)=>Find(s.Patients,x=>x.Id==id);
 public static string Reference(State s,string action,JsonElement j)=>action switch {
 "patient"=>s.Patients.Last().Id, "bed"=>s.Beds.Last().Id, "doctor"=>s.Doctors.Last().Id, "medicine"=>s.Medicines.Last().Id,
 "user"=>s.Users.Last().Id, "appointment"=>s.Appointments.Last().Id, "admit"=>s.Admissions.Last().Id,
 "bill"=>s.Bills.Last().Id,"prescription"=>s.Prescriptions.Last().Id,"note"=>s.Notes.Last().Id,
 _=>j.TryGetProperty("id",out var id)?id.GetString()??"Transaction":"Transaction"
 };
 public static void Apply(State s,string action,JsonElement j,string timezone="Asia/Kolkata") {
 var now=DateTimeOffset.UtcNow;
 var hospitalNow=TimeZoneInfo.ConvertTime(now,TimeZoneInfo.FindSystemTimeZoneById(timezone));
 var hospitalToday=DateOnly.FromDateTime(hospitalNow.DateTime);
 switch(action) {
 case "patient":
 case "patient-update": {
   var name=Text(j,"name",100);var dob=Text(j,"dob");var phone=Text(j,"phone",20);var sex=Text(j,"sex");
   if(!DateOnly.TryParse(dob,out var d)||d>hospitalToday||d.Year<1900)throw new RuleException("Enter a valid birth date.");
   if(!System.Text.RegularExpressions.Regex.IsMatch(phone,@"^\+?[0-9 ()-]{7,20}$"))throw new RuleException("Enter a valid contact number.");
   if(!new[]{"Male","Female","Other","Prefer not to say"}.Contains(sex))throw new RuleException("Select a valid sex value.");
   var existing=action=="patient-update"?Find(s.Patients,x=>x.Id==Text(j,"id")):null;
   if(s.Patients.Any(p=>p.Id!=existing?.Id&&(p.Name.Equals(name,StringComparison.OrdinalIgnoreCase)&&p.Dob==dob || p.Phone==phone&&p.Dob==dob)))throw new RuleException("Possible duplicate patient. Search existing records before registering.");
   if(existing==null)s.Patients.Add(new(Id("HF"),name,dob,sex,phone,now));
   else s.Patients[s.Patients.IndexOf(existing)]=existing with{Name=name,Dob=dob,Sex=sex,Phone=phone};break; }
 case "bed": {
   var bedId=Text(j,"id",50);if(s.Beds.Any(b=>b.Id.Equals(bedId,StringComparison.OrdinalIgnoreCase)))throw new RuleException("Bed identifier already exists.");
   s.Beds.Add(new(bedId,Text(j,"ward",100),Text(j,"category",100),"Available"));break;
 }
 case "doctor": {
   var start=Text(j,"start");var end=Text(j,"end");if(!TimeOnly.TryParse(start,out var st)||!TimeOnly.TryParse(end,out var en)||st>=en)throw new RuleException("Enter a valid same-day shift.");
   s.Doctors.Add(new(Id("DR"),Text(j,"name",100),Text(j,"department",80),start,end));break; }
 case "appointment": {
   var pid=Text(j,"patientId");Patient(s,pid);var doctor=Find(s.Doctors,x=>x.Id==Text(j,"doctorId"));
   if(!DateTimeOffset.TryParse(Text(j,"at"),out var at)||at<now.AddMinutes(-5))throw new RuleException("Choose a future appointment time.");
   var t=TimeOnly.FromDateTime(TimeZoneInfo.ConvertTime(at,TimeZoneInfo.FindSystemTimeZoneById(timezone)).DateTime);if(t<TimeOnly.Parse(doctor.Start)||t>TimeOnly.Parse(doctor.End).AddMinutes(-30)||t.Minute%30!=0)throw new RuleException("Select a 30-minute slot within the doctor's shift.");
   if(s.Appointments.Any(x=>x.Status!="Cancelled"&&x.Status!="No show"&&(x.DoctorId==doctor.Id||x.PatientId==pid)&&Math.Abs((x.At-at).TotalMinutes)<30))throw new RuleException("This doctor or patient already has an overlapping appointment.");
   s.Appointments.Add(new(Id("APT"),pid,doctor.Id,at,Text(j,"type"),"Scheduled"));break; }
 case "appointment-status": {
   var a=Find(s.Appointments,x=>x.Id==Text(j,"id"));var status=Text(j,"status");
   var allowed=a.Status switch {"Scheduled"=>new[]{"Checked in","Cancelled","No show"},"Checked in"=>new[]{"In consultation","Cancelled"},"In consultation"=>new[]{"Completed"},_=>Array.Empty<string>()};
   if(!allowed.Contains(status))throw new RuleException("This appointment status transition is not allowed.");
   if(status=="No show"&&a.At>now)throw new RuleException("A future appointment cannot be marked no-show.");
   s.Appointments[s.Appointments.IndexOf(a)]=a with{Status=status,CheckedIn=status=="Checked in"?now:a.CheckedIn};break; }
 case "admit": {
   var pid=Text(j,"patientId");Patient(s,pid);var b=Find(s.Beds,x=>x.Id==Text(j,"bedId"));
   if(b.Status!="Available")throw new RuleException("Bed is no longer available.");
   if(s.Admissions.Any(x=>x.PatientId==pid&&x.Status=="Admitted"))throw new RuleException("Patient already has an active admission.");
   s.Admissions.Add(new(Id("ADM"),pid,b.Id,Text(j,"reason"),now,"Admitted"));s.Beds[s.Beds.IndexOf(b)]=b with{Status="Occupied"};break; }
 case "transfer": {
   var a=Find(s.Admissions,x=>x.Id==Text(j,"id")&&x.Status=="Admitted");var b=Find(s.Beds,x=>x.Id==Text(j,"bedId"));Text(j,"reason");if(b.Status!="Available")throw new RuleException("Destination bed is not available.");
   var old=Find(s.Beds,x=>x.Id==a.BedId);s.Beds[s.Beds.IndexOf(old)]=old with{Status="Cleaning"};s.Beds[s.Beds.IndexOf(b)]=b with{Status="Occupied"};s.Admissions[s.Admissions.IndexOf(a)]=a with{BedId=b.Id};
   s.Audit.Add(new(Id("AUD"),"Workflow","Bed transfer",a.Id+": "+old.Id+" → "+b.Id,now));break; }
 case "discharge": {
   var a=Find(s.Admissions,x=>x.Id==Text(j,"id")&&x.Status=="Admitted");Text(j,"summary");
   if(s.Bills.Any(x=>x.PatientId==a.PatientId&&x.Balance>0))throw new RuleException("Settle all outstanding bills before discharge.");
   if(s.Prescriptions.Any(x=>x.PatientId==a.PatientId&&x.Status=="Pending"))throw new RuleException("Complete pending medicine dispensing before discharge.");
   var b=Find(s.Beds,x=>x.Id==a.BedId);s.Beds[s.Beds.IndexOf(b)]=b with{Status="Cleaning"};s.Admissions[s.Admissions.IndexOf(a)]=a with{Status="Discharged",Discharged=now};
   s.Notes.Add(new(Id("NOTE"),a.PatientId,Text(j,"summary"),"Discharge summary",now));break; }
 case "bed-status": {
   var b=Find(s.Beds,x=>x.Id==Text(j,"id"));var status=Text(j,"status");if(b.Status=="Occupied"||!new[]{"Available","Cleaning","Maintenance"}.Contains(status))throw new RuleException("Occupied beds must be released through discharge or transfer.");s.Beds[s.Beds.IndexOf(b)]=b with{Status=status};break; }
 case "medicine": {
   if(!DateOnly.TryParse(Text(j,"expiry"),out var expiry)||expiry<=hospitalToday)throw new RuleException("Expiry must be in the future.");
   var name=Text(j,"name");var batch=Text(j,"batch");if(s.Medicines.Any(x=>x.Name.Equals(name,StringComparison.OrdinalIgnoreCase)&&x.Batch==batch))throw new RuleException("This medicine batch already exists. Receive stock instead.");
   var m=new Medicine(Id("MED"),name,batch,expiry,Num(j,"quantity"),Num(j,"reorder"),Money(j,"price"));s.Medicines.Add(m);s.Movements.Add(new(Id("MOV"),m.Id,m.Quantity,"Opening stock",now));break; }
 case "stock": {
   var m=Find(s.Medicines,x=>x.Id==Text(j,"id"));int n=Num(j,"quantity");var reason=Text(j,"reason");s.Medicines[s.Medicines.IndexOf(m)]=m with{Quantity=checked(m.Quantity+n)};s.Movements.Add(new(Id("MOV"),m.Id,n,reason,now));break; }
 case "prescription": {
   var pid=Text(j,"patientId");Patient(s,pid);Find(s.Medicines,x=>x.Id==Text(j,"medicineId"));s.Prescriptions.Add(new(Id("RX"),pid,Text(j,"medicineId"),Num(j,"quantity"),Text(j,"instructions"),"Pending"));break; }
 case "dispense": {
   var rx=Find(s.Prescriptions,x=>x.Id==Text(j,"id"));if(rx.Status!="Pending")throw new RuleException("Prescription has already been dispensed.");var m=Find(s.Medicines,x=>x.Id==rx.MedicineId);
   if(m.Expiry<=hospitalToday)throw new RuleException("Expired batches cannot be dispensed.");if(m.Quantity<rx.Quantity)throw new RuleException("Insufficient stock. Receive stock before dispensing.");
   s.Medicines[s.Medicines.IndexOf(m)]=m with{Quantity=m.Quantity-rx.Quantity};s.Prescriptions[s.Prescriptions.IndexOf(rx)]=rx with{Status="Dispensed"};s.Movements.Add(new(Id("MOV"),m.Id,-rx.Quantity,rx.Id,now));
   s.Bills.Add(new(Id("INV"),rx.PatientId,[new(Id("LINE"),m.Name+" × "+rx.Quantity,rx.Quantity*m.Price)],[]));break; }
 case "bill": {var pid=Text(j,"patientId");Patient(s,pid);s.Bills.Add(new(Id("INV"),pid,[new(Id("LINE"),Text(j,"description"),Money(j,"amount"))],[]));break;}
 case "payment": {var b=Find(s.Bills,x=>x.Id==Text(j,"id"));var amount=Money(j,"amount");var method=Text(j,"method");if(!new[]{"Cash","Card","UPI","Bank transfer"}.Contains(method))throw new RuleException("Invalid payment method.");if(amount>b.Balance)throw new RuleException("Payment exceeds the outstanding balance.");b.Payments.Add(new(Id("PAY"),amount,method,now));break;}
 case "adjustment": {var b=Find(s.Bills,x=>x.Id==Text(j,"id"));var amount=Money(j,"amount");if(amount>b.Balance)throw new RuleException("Adjustment cannot exceed the unpaid balance.");b.Lines.Add(new(Id("ADJ"),"Adjustment: "+Text(j,"reason"),-amount));break;}
 case "note": {var pid=Text(j,"patientId");Patient(s,pid);s.Notes.Add(new(Id("NOTE"),pid,Text(j,"text",4000),"Operational note",now));break;}
 case "user-status": {
   var user=Find(s.Users,x=>x.Id==Text(j,"id"));
   if(!j.TryGetProperty("active",out var value)||value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))throw new RuleException("Select a valid account status.");
   var active=value.GetBoolean();
   if(!active&&user.Role=="Administrator"&&s.Users.Count(x=>x.Active&&x.Role=="Administrator")<=1)throw new RuleException("At least one administrator must remain active.");
   user.Active=active;break;
 }
 case "user": {
   var email=Text(j,"email",150);var role=Text(j,"role");var pwd=Text(j,"password",128);if(!email.Contains('@')||pwd.Length<12)throw new RuleException("Provide a valid email and a password of at least 12 characters.");
   if(!new[]{"Administrator","Reception","Doctor","Nurse","Pharmacist","Billing"}.Contains(role))throw new RuleException("Invalid role.");if(s.Users.Any(x=>x.Email.Equals(email,StringComparison.OrdinalIgnoreCase)))throw new RuleException("Email already exists.");
   var u=new User{Id=Id("USR"),Name=Text(j,"name"),Email=email,Role=role};u.PasswordHash=new PasswordHasher<User>().HashPassword(u,pwd);s.Users.Add(u);break;}
 }
 }
}
