using System.Data;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Npgsql;

record PatientAccount(string PatientId,bool MustChangePassword,DateTimeOffset TemporaryExpiresAt);
record SmsMessageData(string To,string Body);
sealed partial class Store {
    public async Task<PatientAccount?> PatientAccount(string userId) {
        await using var c=await Open();await using var cmd=new NpgsqlCommand("SELECT patient_id,must_change_password,temporary_expires_at FROM hospitalflow.patient_accounts WHERE user_id=$1",c);cmd.Parameters.AddWithValue(userId);
        await using var r=await cmd.ExecuteReaderAsync();return await r.ReadAsync()?new(r.GetString(0),r.GetBoolean(1),new DateTimeOffset(r.GetDateTime(2),TimeSpan.Zero)):null;
    }
    public async Task<User?> UserByLogin(string identifier) {
        identifier=identifier.Trim();if(identifier.Contains('@'))return await UserByEmail(AccountValidation.Email(identifier));
        if(identifier.Length>100||!System.Text.RegularExpressions.Regex.IsMatch(identifier,@"^(HF|P|D|N|V|A|DEV|U)-[A-Za-z0-9-]+$",System.Text.RegularExpressions.RegexOptions.IgnoreCase))return null;
        await using var c=await Open();return (await new RowMap<User>("users").Read(c,null,"WHERE lower(registration_id)=lower($1) OR id=(SELECT user_id FROM hospitalflow.patient_accounts WHERE lower(patient_id)=lower($1))",identifier)).FirstOrDefault();
    }
    public async Task<Dictionary<string,string>> PatientEmails() {
        await using var c=await Open();await using var cmd=new NpgsqlCommand("SELECT p.patient_id,u.email FROM hospitalflow.patient_accounts p JOIN hospitalflow.users u ON u.id=p.user_id",c);await using var r=await cmd.ExecuteReaderAsync();var result=new Dictionary<string,string>();while(await r.ReadAsync())result[r.GetString(0)]=r.GetString(1);return result;
    }
    static string Mobile(string value) {
        if(!System.Text.RegularExpressions.Regex.IsMatch(value,@"^[0-9]{10}$"))throw new RuleException("Mobile number must contain exactly 10 digits, without spaces or country code.");
        return value;
    }
    async Task ProvisionPatient(NpgsqlConnection c,NpgsqlTransaction tx,string patientId,string email,IDataProtector mailProtector,IDataProtector smsProtector,AuditContext audit,bool reissue=false,string? initialPassword=null) {
        string? existingId=null;
        await using(var existing=new NpgsqlCommand("SELECT u.email,u.id,p.must_change_password FROM hospitalflow.patient_accounts p JOIN hospitalflow.users u ON u.id=p.user_id WHERE p.patient_id=$1",c,tx)) {
            existing.Parameters.AddWithValue(patientId);await using var reader=await existing.ExecuteReaderAsync();
            if(await reader.ReadAsync()){
                if(reader.GetString(0)!=email)throw new RuleException("This patient already has a login email. Contact administration for an identity-reviewed email change.");
                if(!reissue)return;
                if(!reader.GetBoolean(2))throw new RuleException("This patient has activated access. Use Forgot password for recovery.");existingId=reader.GetString(1);
            }
        }
        var patient=(await new RowMap<Patient>("patients").Read(c,tx,"WHERE id=$1",patientId)).Single();var mobile=Mobile(patient.Phone);
        if(existingId==null)await using(var exists=new NpgsqlCommand("SELECT EXISTS(SELECT 1 FROM hospitalflow.users WHERE lower(email)=$1)",c,tx)){exists.Parameters.AddWithValue(email);if((bool)(await exists.ExecuteScalarAsync())!)throw new RuleException("This email already belongs to an account. Use the patient's unique email address.");}
        var id=existingId??Guid.NewGuid().ToString("N");const string temporary="1234";
        if(existingId==null){
            await Sql(c,tx,"INSERT INTO hospitalflow.users(id,name,email,role,password_hash,active,email_confirmed) VALUES($1,$2,$3,'User',$4,true,true)",id,patient.Name,email,new PasswordHasher<User>().HashPassword(new User(),temporary));
            await Sql(c,tx,"INSERT INTO hospitalflow.patient_accounts(user_id,patient_id,temporary_expires_at) VALUES($1,$2,now()+interval '24 hours')",id,patientId);
        }else{
            await Sql(c,tx,"UPDATE hospitalflow.users SET password_hash=$1 WHERE id=$2 AND active",new PasswordHasher<User>().HashPassword(new User(),temporary),id);
            await Sql(c,tx,"UPDATE hospitalflow.patient_accounts SET temporary_expires_at=now()+interval '24 hours',invited_at=now() WHERE user_id=$1",id);
            await Sql(c,tx,"UPDATE hospitalflow.patient_login_challenges SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",id);
            await Sql(c,tx,"UPDATE hospitalflow.account_tokens SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",id);
            await Sql(c,tx,"DELETE FROM hospitalflow.sessions WHERE user_id=$1",id);
        }
        var origin=config["Accounts:PublicOrigin"]??"http://localhost:5136";
        var body=$"HospitalFlow patient access\nEmail: {email}\nPatient ID: {patient.RegistrationId}\nApplication: {origin.TrimEnd('/')}/#patient-home\nTemporary password: {temporary}\n\nSign in with your email or patient ID and this temporary password within 24 hours. Verify your date of birth, then choose a new password before accessing your records. Never share your password.";
        await Sql(c,tx,"INSERT INTO hospitalflow.account_mail(user_id,encrypted_message) VALUES($1,$2)",id,mailProtector.Protect(JsonSerializer.Serialize(new MailMessageData(email,"Your HospitalFlow patient access",body))));
        await Sql(c,tx,"INSERT INTO hospitalflow.patient_sms(user_id,encrypted_message) VALUES($1,$2)",id,smsProtector.Protect(JsonSerializer.Serialize(new SmsMessageData("+91"+mobile,body))));
        await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("patient-invited",patientId)],[]);
    }
    public async Task ReissuePatientInvitation(string patientId,AuditContext audit,IDataProtectionProvider protection){
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();
        await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301),set_config('hospitalflow.actor_id',$1,true),set_config('hospitalflow.correlation_id',$2,true)",audit.ActorId!,audit.CorrelationId);
        await Sql(c,tx,"SELECT hf_security.require_actor(ARRAY['Reception','Doctor'])");
        await using var cmd=new NpgsqlCommand("SELECT u.email FROM hospitalflow.patient_accounts p JOIN hospitalflow.users u ON u.id=p.user_id WHERE p.patient_id=$1 AND u.active AND p.invited_at<now()-interval '1 minute'",c,tx);cmd.Parameters.AddWithValue(patientId);
        var email=await cmd.ExecuteScalarAsync() as string??throw new RuleException("Patient access is unavailable, disabled, or an invitation was sent less than a minute ago.");
        await ProvisionPatient(c,tx,patientId,email,protection.CreateProtector("HospitalFlow.AccountMail.v1"),protection.CreateProtector("HospitalFlow.PatientSms.v1"),audit,true);await tx.CommitAsync();
    }
    public async Task<string> CreatePatientChallenge(string userId) {
        var token=Convert.ToHexString(RandomNumberGenerator.GetBytes(32));await using var c=await Open();await using var tx=await c.BeginTransactionAsync();
        await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301)");
        await Sql(c,tx,"UPDATE hospitalflow.patient_login_challenges SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",userId);
        await Sql(c,tx,"INSERT INTO hospitalflow.patient_login_challenges(token_hash,user_id,expires_at) VALUES($1,$2,now()+interval '10 minutes')",Hash(token),userId);
        await tx.CommitAsync();return token;
    }
    public async Task CompletePatientOnboarding(string token,string dob,string password,AuditContext audit) {
        if(token.Length!=64||!token.All(Uri.IsHexDigit))throw new RuleException("This sign-in challenge is invalid or expired. Sign in again.");
        if(await CompleteStaffOnboarding(token,dob,password,audit))return;
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301)");
        await Sql(c,tx,"SELECT set_config('hospitalflow.patient_id',COALESCE((SELECT a.patient_id FROM hospitalflow.patient_login_challenges t JOIN hospitalflow.patient_accounts a ON a.user_id=t.user_id WHERE t.token_hash=$1 AND t.consumed_at IS NULL AND t.expires_at>now()),''),true)",Hash(token));
        await Sql(c,tx,"SELECT set_config('hospitalflow.hospital_id',COALESCE((SELECT hospital_id FROM hospitalflow.patients WHERE id=nullif(current_setting('hospitalflow.patient_id',true),'')),hf_security.current_hospital()),true)");
        await using var cmd=new NpgsqlCommand("SELECT t.user_id,p.patient_id,patient.dob::text FROM hospitalflow.patient_login_challenges t JOIN hospitalflow.patient_accounts p ON p.user_id=t.user_id JOIN hospitalflow.users u ON u.id=p.user_id JOIN hospitalflow.patients patient ON patient.id=p.patient_id WHERE t.token_hash=$1 AND t.consumed_at IS NULL AND t.expires_at>now() AND t.attempts<5 AND p.must_change_password AND p.temporary_expires_at>now() AND u.active FOR UPDATE OF t,p,u",c,tx);cmd.Parameters.AddWithValue(Hash(token));
        string id,patientId,expectedDob;await using(var r=await cmd.ExecuteReaderAsync()){if(!await r.ReadAsync())throw new RuleException("This sign-in challenge is invalid or expired. Sign in again.");id=r.GetString(0);patientId=r.GetString(1);expectedDob=r.GetString(2);}
        if(dob!=expectedDob){await Sql(c,tx,"UPDATE hospitalflow.patient_login_challenges SET attempts=attempts+1 WHERE token_hash=$1",Hash(token));await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("patient-verification",patientId,"Rejected")],[]);await tx.CommitAsync();throw new RuleException("Verification failed. Check the date of birth entered during registration.");}
        var user=(await new RowMap<User>("users").Read(c,tx,"WHERE id=$1",id)).Single();AccountValidation.Password(password,user.Name,user.Email);
        if(new PasswordHasher<User>().VerifyHashedPassword(user,user.PasswordHash,password)!=PasswordVerificationResult.Failed)throw new RuleException("Choose a new password different from the temporary password.");
        await Sql(c,tx,"SELECT set_config('hospitalflow.actor_id',$1,true),set_config('hospitalflow.correlation_id',$2,true)",id,audit.CorrelationId);
        await Sql(c,tx,"UPDATE hospitalflow.users SET password_hash=$1 WHERE id=$2",new PasswordHasher<User>().HashPassword(user,password),id);
        await Sql(c,tx,"UPDATE hospitalflow.patient_accounts SET must_change_password=false,activated_at=now() WHERE user_id=$1",id);
        await Sql(c,tx,"UPDATE hospitalflow.patient_login_challenges SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",id);
        await Sql(c,tx,"UPDATE hospitalflow.account_tokens SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",id);
        await Sql(c,tx,"DELETE FROM hospitalflow.sessions WHERE user_id=$1",id);
        await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("patient-access-activated",patientId)],[]);await tx.CommitAsync();
    }
    public async Task<State> PatientState(string userId,bool allHospitals=false) {
        var account=await PatientAccount(userId)??throw new RuleException("Patient access not configured.");if(account.MustChangePassword)throw new RuleException("Complete first-time verification before accessing patient records.");
        var hospitalFilter=allHospitals?"":" AND hospital_id=hf_security.current_hospital()";
        var pid=account.PatientId;await using var c=await Open();await using var tx=await c.BeginTransactionAsync(IsolationLevel.RepeatableRead);
        var s=new State{Patients=await new RowMap<Patient>("patients").Read(c,tx,"WHERE id=$1",pid),Appointments=await new RowMap<Appointment>("appointments").Read(c,tx,"WHERE patient_id=$1"+hospitalFilter+" ORDER BY at DESC",pid),Admissions=await new RowMap<Admission>("admissions").Read(c,tx,"WHERE patient_id=$1"+hospitalFilter+" ORDER BY at DESC",pid),Prescriptions=await new RowMap<Prescription>("prescriptions").Read(c,tx,"WHERE patient_id=$1"+hospitalFilter,pid)};
        s.Doctors=await new RowMap<Doctor>("doctors").Read(c,tx,"WHERE id IN(SELECT doctor_id FROM hospitalflow.appointments WHERE patient_id=$1"+hospitalFilter+")",pid);
        await using(var medicines=new NpgsqlCommand("SELECT DISTINCT m.id,m.name FROM hospitalflow.medicine_batches m JOIN hospitalflow.prescriptions p ON p.medicine_id=m.id WHERE p.patient_id=$1"+(allHospitals?"":" AND p.hospital_id=hf_security.current_hospital()"),c,tx)){medicines.Parameters.AddWithValue(pid);await using var r=await medicines.ExecuteReaderAsync();while(await r.ReadAsync())s.CareMedicines.Add(new(r.GetString(0),r.GetString(1)));}
        // Patient portal never receives staff notes, stock quantities, other patients or account lists.
        foreach(var h in await new RowMap<BillHeader>("bills").Read(c,tx,"WHERE patient_id=$1"+hospitalFilter+" ORDER BY created_at DESC",pid)) {
            var payments=await new RowMap<Payment>("payments").Read(c,tx,"WHERE bill_id=$1 ORDER BY at,id",h.Id);payments.AddRange(await new RowMap<Payment>("payment_reversal_receipts").Read(c,tx,"WHERE bill_id=$1",h.Id));
            s.Bills.Add(new(h.Id,pid,await new RowMap<BillLine>("bill_lines").Read(c,tx,"WHERE bill_id=$1",h.Id),payments));
        }
        await tx.CommitAsync();return s;
    }
    public async Task<bool> PatientOwns(string userId,string kind,string reference) {
        await using var c=await Open();await using var cmd=new NpgsqlCommand(kind=="patient"?"SELECT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=$1 AND patient_id=$2)":"SELECT EXISTS(SELECT 1 FROM hospitalflow.bills b JOIN hospitalflow.patient_accounts p ON p.patient_id=b.patient_id WHERE p.user_id=$1 AND b.id=$2)",c);cmd.Parameters.AddWithValue(userId);cmd.Parameters.AddWithValue(reference);return (bool)(await cmd.ExecuteScalarAsync())!;
    }
}
