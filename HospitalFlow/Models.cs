record Login(string Email,string Password);
class RuleException(string message):Exception(message);
class State {
 public List<Patient> Patients {get;set;}=[]; public List<Doctor> Doctors {get;set;}=[];
 public List<Appointment> Appointments {get;set;}=[]; public List<Bed> Beds {get;set;}=[];
 public List<Admission> Admissions {get;set;}=[]; public List<Medicine> Medicines {get;set;}=[];
 public List<Prescription> Prescriptions {get;set;}=[]; public List<Bill> Bills {get;set;}=[];
 public List<Note> Notes {get;set;}=[]; public List<Audit> Audit {get;set;}=[];
 public List<User> Users {get;set;}=[]; public List<Movement> Movements {get;set;}=[];
}
record Patient(string Id,string Name,string Dob,string Sex,string Phone,DateTimeOffset Created);
record Doctor(string Id,string Name,string Department,string Start,string End);
record Appointment(string Id,string PatientId,string DoctorId,DateTimeOffset At,string Type,string Status,DateTimeOffset? CheckedIn=null);
record Bed(string Id,string Ward,string Category,string Status);
record Admission(string Id,string PatientId,string BedId,string Reason,DateTimeOffset At,string Status,DateTimeOffset? Discharged=null);
record Medicine(string Id,string Name,string Batch,DateOnly Expiry,int Quantity,int Reorder,decimal Price);
record Prescription(string Id,string PatientId,string MedicineId,int Quantity,string Instructions,string Status);
record Movement(string Id,string MedicineId,int Quantity,string Reason,DateTimeOffset At);
record BillLine(string Id,string Description,decimal Amount);
record Payment(string Id,decimal Amount,string Method,DateTimeOffset At);
record Bill(string Id,string PatientId,List<BillLine> Lines,List<Payment> Payments) {
 public decimal Total=>Lines.Sum(x=>x.Amount); public decimal Paid=>Payments.Sum(x=>x.Amount); public decimal Balance=>Total-Paid;
}
record Note(string Id,string PatientId,string Text,string Kind,DateTimeOffset At);
record Audit(string Id,string Actor,string Action,string Reference,DateTimeOffset At, string Outcome="Success", string? ActorId=null, string? CorrelationId=null, string? SourceIp=null, string? Method=null, int? StatusCode=null);
record BillHeader(string Id,string PatientId);
class User { public string Id{get;set;}=""; public string Name{get;set;}=""; public string Email{get;set;}=""; public string Role{get;set;}=""; public string PasswordHash{get;set;}=""; public bool Active{get;set;}=true; }

record OperationalAlert(string Id,string Rule,string Reference,string Title,string Text,string Link,DateTimeOffset OpenedAt);
