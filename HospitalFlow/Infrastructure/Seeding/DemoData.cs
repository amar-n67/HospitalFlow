using System.Security.Cryptography;
using Microsoft.AspNetCore.Identity;

static class DemoData {
 public static State Create() {
   var s=new State(); var now=DateTimeOffset.UtcNow;
   string[] names=["Aarav Sharma","Meera Nair","Rohan Patel","Ananya Rao","Kabir Singh","Diya Menon","Ishaan Das","Sara Thomas"];
   for(int i=0;i<names.Length;i++) s.Patients.Add(new($"HF-{1001+i}",names[i],$"{1984+i}-05-12",i%2==0?"Male":"Female",$"90000000{i:00}",now.AddDays(-i)));
   s.Doctors=[new("DR-01","Dr. Aditi Mehta","General Medicine","09:00","17:00"),new("DR-02","Dr. Vikram Rao","Cardiology","09:00","17:00"),new("DR-03","Dr. Neha Kapoor","Orthopaedics","10:00","18:00"),new("DR-04","Dr. Arjun Das","Paediatrics","08:00","16:00")];
   for(int i=1;i<=24;i++) s.Beds.Add(new($"B-{i:00}",i<=12?"General Ward":"East Wing",i<=12?"General":"Private",i<=4?"Occupied":i==8?"Cleaning":i==18?"Maintenance":"Available"));
   for(int i=0;i<4;i++) s.Admissions.Add(new($"ADM-{i+1}",s.Patients[i].Id,s.Beds[i].Id,"Observation",now.AddDays(-i-1),"Admitted"));
   var date=DateTimeOffset.Now.Date;
   for(int i=0;i<8;i++) s.Appointments.Add(new($"APT-{i+1}",s.Patients[i].Id,s.Doctors[i%4].Id,new DateTimeOffset(date.AddHours(10).AddMinutes(i*30),DateTimeOffset.Now.Offset),"Consultation",i<2?"Completed":i<5?"Checked in":"Scheduled",i is >=2 and <5?now.AddMinutes(-15*i):null));
   s.Medicines=[new("MED-01","Paracetamol 500 mg","PCM-2601",DateOnly.FromDateTime(DateTime.Today.AddYears(1)),240,50,2.50m),new("MED-02","Amoxicillin 250 mg","AMX-2603",DateOnly.FromDateTime(DateTime.Today.AddMonths(8)),18,30,8m),new("MED-03","Oral rehydration salts","ORS-2602",DateOnly.FromDateTime(DateTime.Today.AddDays(24)),64,20,15m),new("MED-04","Cetirizine 10 mg","CTZ-2604",DateOnly.FromDateTime(DateTime.Today.AddYears(1)),80,25,4m)];
   s.Bills=[new("INV-1001","HF-1001",[new("L1","Consultation",500),new("L2","Room charges",1500)],[new("PAY-1",500,"Cash",now)]),new("INV-1002","HF-1002",[new("L3","Consultation",500)],[])];
   s.Prescriptions=[new("RX-01","HF-1001","MED-01",6,"Synthetic example only; verify against the clinician's prescription.","Pending")];
   var pwd=Environment.GetEnvironmentVariable("HOSPITALFLOW_ADMIN_PASSWORD")??Convert.ToHexString(RandomNumberGenerator.GetBytes(12))+"a!";
   foreach(var role in new[]{"Administrator","Reception","Doctor","Nurse","Pharmacist","Billing"}) {
      var u=new User{Id=Guid.NewGuid().ToString("N"),Name=role=="Administrator"?"Amar Nath":role+" Demo",Email=role.ToLowerInvariant()+"@hospitalflow.local",Role=role};u.PasswordHash=new PasswordHasher<User>().HashPassword(u,pwd);s.Users.Add(u);
   }
   Console.WriteLine("HospitalFlow synthetic accounts created. Credentials are never written to application logs.");
   Console.WriteLine("Other demo roles use the same initial password. Set HOSPITALFLOW_ADMIN_PASSWORD before first launch to choose it.");
   Log(s,"System","Synthetic demonstration data created"); return s;
 }
 static void Log(State s,string actor,string action)=>s.Audit.Add(new(Guid.NewGuid().ToString("N"),actor,action,"Seed",DateTimeOffset.UtcNow));
}
