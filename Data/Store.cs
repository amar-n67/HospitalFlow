using System.Data;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.DataProtection;
using Npgsql;

sealed partial class Store : IDisposable
{
    readonly NpgsqlDataSource source;
    byte[] requestHashKey=[];
    public string HospitalTimezone {get;private set;}="Asia/Kolkata";
    readonly IConfiguration config;
    readonly IWebHostEnvironment environment;
    public string Mode => "PostgreSQL · relational";
    public Store(IConfiguration config, IWebHostEnvironment env)
    {
        this.config = config; environment = env;
        var connection = config.GetConnectionString("HospitalFlow");
        if (string.IsNullOrWhiteSpace(connection)) throw new InvalidOperationException("PostgreSQL is required. Configure ConnectionStrings:HospitalFlow; see README.md.");
        var b = new NpgsqlConnectionStringBuilder(connection) { ApplicationName = "HospitalFlow", SearchPath = "hospitalflow,public" };
        source = NpgsqlDataSource.Create(b.ConnectionString);
    }
    public void Dispose() => source.Dispose();
    public async ValueTask<NpgsqlConnection> Open() {
        var c=await source.OpenConnectionAsync();
        try{await Sql(c,null,"SELECT set_config('TimeZone',$1,false),set_config('hospitalflow.hospital_id',$2,false),set_config('hospitalflow.actor_id',$3,false),set_config('hospitalflow.patient_id',$4,false)",HospitalTimezone,ContextHospital?.HospitalId??"H-0001",ContextHospital?.UserId??"",ContextHospital?.PatientId??"");return c;}
        catch{await c.DisposeAsync();throw;}
    }
    public string RequestHash(string text)=>Convert.ToHexString(HMACSHA256.HashData(requestHashKey,Encoding.UTF8.GetBytes(text)));
    static string Hash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
    public async Task Migrate()
    {
        await using var c = await Open();
        await using var tx = await c.BeginTransactionAsync();
        await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301); CREATE SCHEMA IF NOT EXISTS hospitalflow; CREATE TABLE IF NOT EXISTS hospitalflow.schema_versions(version text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now());");
        var assembly = Assembly.GetExecutingAssembly();
        foreach (var name in assembly.GetManifestResourceNames().Where(x => x.EndsWith(".sql")).Order())
        {
            using var reader = new StreamReader(assembly.GetManifestResourceStream(name)!);
            var script = await reader.ReadToEndAsync(); var checksum = Hash(script);
            await using var check = new NpgsqlCommand("SELECT checksum FROM hospitalflow.schema_versions WHERE version=$1",c,tx);
            check.Parameters.AddWithValue(name); var existing = await check.ExecuteScalarAsync() as string;
            if (existing != null) { if (existing != checksum) throw new InvalidOperationException("Applied migration checksum mismatch: " + name); continue; }
            await Sql(c,tx,script);
            await Sql(c,tx,"INSERT INTO hospitalflow.schema_versions(version,checksum) VALUES($1,$2)",name,checksum);
        }
        await Sql(c,tx,"INSERT INTO hospitalflow.idempotency_hash_keys(id,secret) VALUES(1,$1) ON CONFLICT DO NOTHING",RandomNumberGenerator.GetBytes(32));
        await tx.CommitAsync();
    }
    public async Task Initialize()
    {
        await using var c = await Open();
        await using var cmd = new NpgsqlCommand("SELECT count(*) FROM hospitalflow.schema_versions",c);
        if (Convert.ToInt32(await cmd.ExecuteScalarAsync()) != Assembly.GetExecutingAssembly().GetManifestResourceNames().Count(x=>x.EndsWith(".sql"))) throw new InvalidOperationException("Database migrations have not been applied. Run --migrate with the migration account.");
        await using var key=new NpgsqlCommand("SELECT secret FROM hospitalflow.idempotency_hash_keys WHERE id=1",c);
        requestHashKey=(byte[])(await key.ExecuteScalarAsync()??throw new InvalidOperationException("Request fingerprint key is missing."));
        await using var timezone=new NpgsqlCommand("SELECT value FROM hospitalflow.system_settings WHERE key='hospital_timezone'",c);
        HospitalTimezone=(string)(await timezone.ExecuteScalarAsync()??"Asia/Kolkata");
        _=TimeZoneInfo.FindSystemTimeZoneById(HospitalTimezone);
    }
    public async Task Bootstrap(string? legacyPath = null)
    {
        await using var c=await Open(); await using var tx=await c.BeginTransactionAsync();
        await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301)");
        var old=await Load(c,tx);
        if(old.Users.Count>0) { if(legacyPath!=null) throw new InvalidOperationException("Import refused: destination already contains users. Existing records were not changed."); return; }
        State next;
        if(legacyPath!=null) next=JsonSerializer.Deserialize<State>(await File.ReadAllTextAsync(legacyPath))??throw new InvalidOperationException("Invalid legacy import.");
        else if(config.GetValue<bool>("Database:SeedDemo")) {
            if(!environment.IsDevelopment())throw new InvalidOperationException("Demo seeding is allowed only in Development.");
            next=DemoData.Create();
        } else {
            var email=config["Bootstrap:Email"]??throw new InvalidOperationException("Bootstrap:Email is required for an empty database.");
            var password=config["Bootstrap:Password"]??throw new InvalidOperationException("Bootstrap:Password is required for an empty database.");
            AccountValidation.Email(email);
            AccountValidation.Password(password,config["Bootstrap:Name"]??"Administrator",email);
            var u=new User{Id=Guid.NewGuid().ToString("N"),Name=config["Bootstrap:Name"]??"Administrator",Email=email,Role="Admin"};
            u.PasswordHash=new PasswordHasher<User>().HashPassword(u,password);next=new State{Users=[u]};
        }
        await Sql(c,tx,"SELECT set_config('hospitalflow.actor_id','migration',true),set_config('hospitalflow.correlation_id','initial-import',true)");
        foreach(var medicine in next.Medicines) {
            var opening=medicine.Quantity-next.Movements.Where(x=>x.MedicineId==medicine.Id).Sum(x=>x.Quantity);
            if(opening!=0)next.Movements.Add(new("OPEN-"+Guid.NewGuid().ToString("N"),medicine.Id,opening,"Opening balance carried from initial import",DateTimeOffset.UtcNow));
        }
        var legacyPermissions=next.Users.Where(u=>u.Role is not ("Admin" or "Developer" or "User" or "Doctor" or "Nurse" or "Volunteer")).Select(u=>(u.Id,u.Role)).ToList();
        foreach(var u in next.Users)if(u.Role is not ("Admin" or "Developer" or "User" or "Doctor" or "Nurse" or "Volunteer"))u.Role=u.Role=="Administrator"?"Admin":"User";
        await Persist(c,tx,next,old);
        foreach(var (id,permission) in legacyPermissions.Where(x=>x.Role!="Administrator"))
            await Sql(c,tx,"INSERT INTO hospitalflow.user_permissions VALUES($1,$2) ON CONFLICT DO NOTHING",id,permission);
        await Sql(c,tx,"INSERT INTO hospitalflow.system_settings(key,value) VALUES('demo_data',$1) ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value",next.Patients.Count>0?"true":"false");
        // Preserve the imported snapshot separately; application reads and writes only relational tables.
        await tx.CommitAsync();
    }
    public async Task<State> Current()
    {
        await using var c=await Open(); await using var tx=await c.BeginTransactionAsync(IsolationLevel.RepeatableRead);
        var s=await Load(c,tx); await tx.CommitAsync();return s;
    }
    static async Task<State> Load(NpgsqlConnection c,NpgsqlTransaction tx)
    {
        var s=new State {
            Patients=await new RowMap<Patient>("patients").Read(c,tx,"ORDER BY created,id"),
            Doctors=await new RowMap<Doctor>("doctors").Read(c,tx,"ORDER BY id"),
            Appointments=await new RowMap<Appointment>("appointments").Read(c,tx,"ORDER BY at,id"),
            Beds=await new RowMap<Bed>("beds").Read(c,tx,"ORDER BY id"),
            Admissions=await new RowMap<Admission>("admissions").Read(c,tx,"ORDER BY at,id"),
            Medicines=await new RowMap<Medicine>("medicine_batches").Read(c,tx,"ORDER BY id"),
            Prescriptions=await new RowMap<Prescription>("prescriptions").Read(c,tx,"ORDER BY id"),
            Movements=await new RowMap<Movement>("stock_movements").Read(c,tx,"ORDER BY at,id"),
            Notes=await new RowMap<Note>("notes").Read(c,tx,"ORDER BY at,id"),
            Users=await new RowMap<User>("users").Read(c,tx,"ORDER BY id"),
            Audit=await new RowMap<Audit>("activity_log").Read(c,tx,"ORDER BY at DESC,id LIMIT 500")
        };
        var headers=await new RowMap<BillHeader>("bills").Read(c,tx,"ORDER BY created_at,id");
        foreach(var h in headers) s.Bills.Add(new(h.Id,h.PatientId,
            await new RowMap<BillLine>("bill_lines").Read(c,tx,"WHERE bill_id=$1 ORDER BY created_at,id",h.Id),
            await new RowMap<Payment>("payments").Read(c,tx,"WHERE bill_id=$1 ORDER BY at,id",h.Id)));
        for(var i=0;i<s.Bills.Count;i++) {
            var bill=s.Bills[i];
            bill.Payments.AddRange(await new RowMap<Payment>("payment_reversal_receipts").Read(c,tx,"WHERE bill_id=$1 ORDER BY at,id",bill.Id));
        }
        s.Audit.Reverse();return s;
    }
    static async Task Persist(NpgsqlConnection c,NpgsqlTransaction tx,State s,State old)
    {
        foreach(var d in s.Doctors.Select(x=>x.Department).Distinct()) await Sql(c,tx,"INSERT INTO hospitalflow.departments(name) VALUES($1) ON CONFLICT DO NOTHING",d);
        foreach(var w in s.Beds.Select(x=>x.Ward).Distinct()) await Sql(c,tx,"INSERT INTO hospitalflow.wards(name) VALUES($1) ON CONFLICT DO NOTHING",w);
        await new RowMap<User>("users").Save(c,tx,s.Users,old.Users);
        await new RowMap<Patient>("patients").Save(c,tx,s.Patients,old.Patients);
        await new RowMap<Doctor>("doctors").Save(c,tx,s.Doctors,old.Doctors);
        await new RowMap<Bed>("beds").Save(c,tx,s.Beds,old.Beds);
        await new RowMap<Appointment>("appointments").Save(c,tx,s.Appointments,old.Appointments);
        await new RowMap<Admission>("admissions").Save(c,tx,s.Admissions,old.Admissions);
        await new RowMap<Medicine>("medicine_batches").Save(c,tx,s.Medicines,old.Medicines);
        await new RowMap<Prescription>("prescriptions").Save(c,tx,s.Prescriptions,old.Prescriptions);
        await new RowMap<Movement>("stock_movements").Save(c,tx,s.Movements,old.Movements);
        await new RowMap<BillHeader>("bills").Save(c,tx,s.Bills.Select(b=>new BillHeader(b.Id,b.PatientId)),old.Bills.Select(b=>new BillHeader(b.Id,b.PatientId)));
        foreach(var b in s.Bills) {
            var before=old.Bills.FirstOrDefault(x=>x.Id==b.Id);
            await new RowMap<BillLine>("bill_lines").Save(c,tx,b.Lines,before?.Lines??[],"bill_id",b.Id);
            await new RowMap<Payment>("payments").Save(c,tx,b.Payments,before?.Payments??[],"bill_id",b.Id);
        }
        await new RowMap<Note>("notes").Save(c,tx,s.Notes,old.Notes);
        await new RowMap<Audit>("activity_log").Save(c,tx,s.Audit,old.Audit);
    }
    public async Task<string> Change(string action,JsonElement payload,AuditContext audit,string? key,string requestHash,IDataProtectionProvider? protection=null)
    {
        if(action is "hospital-profile" or "ward-department"&&!await NetworkOperator(audit.ActorId!))throw new RuleException("This shared network setting requires a network operator.");
        if(!Guid.TryParse(key,out var keyId))throw new RuleException("A valid Idempotency-Key header is required for changes.");
        if(action=="user-status"&&payload.TryGetProperty("id",out var sharedTarget)&&await UserHasOtherHospitals(sharedTarget.GetString()!)&&!await NetworkOperator(audit.ActorId!))throw new RuleException("A network operator must manage an account shared by multiple hospitals.");
        if(action=="user-status"&&payload.TryGetProperty("id",out var protectedTarget)&&await NetworkOperator(protectedTarget.GetString()!)&&!await NetworkOperator(audit.ActorId!))throw new RuleException("Only a network operator can manage this account.");
        if(action=="user-status"&&payload.TryGetProperty("id",out var targetUser)&&!await UserInHospital(targetUser.GetString()!))throw new RuleException("Account is outside this hospital.");
        if(action=="user") {
            if(payload.TryGetProperty("role",out var requestedRole)&&requestedRole.GetString()=="Developer"&&!await NetworkOperator(audit.ActorId!))throw new RuleException("Only a network operator can create Developer access.");
            if(!payload.TryGetProperty("password",out var password)||password.ValueKind!=JsonValueKind.String)
                throw new RuleException("Enter a password.");
            if(!payload.TryGetProperty("name",out var accountName)||accountName.ValueKind!=JsonValueKind.String||!payload.TryGetProperty("email",out var accountEmail)||accountEmail.ValueKind!=JsonValueKind.String)throw new RuleException("Name and email are required.");
            var validEmail=AccountValidation.Email(accountEmail.GetString()!);
            AccountValidation.Password(password.GetString()!,accountName.GetString()!,validEmail);
            var fields=payload.EnumerateObject().Where(x=>x.Name!="password").ToDictionary(x=>x.Name,x=>x.Value.Clone());
            fields["email"]=JsonSerializer.SerializeToElement(validEmail);
            fields["passwordHash"]=JsonSerializer.SerializeToElement(new PasswordHasher<User>().HashPassword(new User(),password.GetString()!));
            payload=JsonSerializer.SerializeToElement(fields);
        }
        if(payload.TryGetProperty("phone",out var contactPhone)&&contactPhone.ValueKind==JsonValueKind.String)Mobile(contactPhone.GetString()!);
        string? patientEmail=null,initialPatientPassword=null;
        if(action=="patient"||(action=="patient-update"&&payload.TryGetProperty("email",out _))) {
            if(!payload.TryGetProperty("email",out var emailValue)||emailValue.ValueKind!=JsonValueKind.String)throw new RuleException("Patient email is required for patient access.");
            patientEmail=AccountValidation.Email(emailValue.GetString()!);
            // Initial credentials are set server-side; never accept a registration password.
            payload=JsonSerializer.SerializeToElement(payload.EnumerateObject().Where(x=>x.Name!="initialPassword").ToDictionary(x=>x.Name,x=>x.Value.Clone()));
            if(protection==null)throw new InvalidOperationException("Patient invitation protection is required.");
        }
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();
        await Sql(c,tx,"SELECT set_config('hospitalflow.actor_id',$1,true),set_config('hospitalflow.correlation_id',$2,true)",audit.ActorId??"",audit.CorrelationId);
        await using var cmd=new NpgsqlCommand("SELECT hf_api.execute($1,$2::jsonb,$3,$4)",c,tx);
        cmd.Parameters.AddWithValue(action);cmd.Parameters.AddWithValue(payload.GetRawText());cmd.Parameters.AddWithValue(keyId);cmd.Parameters.AddWithValue(requestHash);
        var reference=(string)(await cmd.ExecuteScalarAsync())!;
        if(patientEmail!=null)await ProvisionPatient(c,tx,reference,patientEmail,protection!.CreateProtector("HospitalFlow.AccountMail.v1"),protection.CreateProtector("HospitalFlow.PatientSms.v1"),audit,initialPassword:initialPatientPassword);
        await tx.CommitAsync();return reference;
    }
    public async Task Log(Audit entry)
    {
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();
        await new RowMap<Audit>("activity_log").Save(c,tx,[entry],[]);await tx.CommitAsync();
    }
    public async Task<User?> UserByEmail(string email)
    {
        await using var c=await Open();return (await new RowMap<User>("users").Read(c,null,"WHERE lower(email)=lower($1)",email)).FirstOrDefault();
    }
    public async Task<User?> UserById(string id)
    {
        await using var c=await Open();return (await new RowMap<User>("users").Read(c,null,"WHERE id=$1",id)).FirstOrDefault();
    }
    public async Task<bool> IsBlocked(string key)
    {
        await using var c=await Open();await using var cmd=new NpgsqlCommand("SELECT EXISTS(SELECT 1 FROM hospitalflow.auth_attempts WHERE key_hash=$1 AND failures>=10 AND blocked_until>now())",c);
        cmd.Parameters.AddWithValue(Hash(key));return (bool)(await cmd.ExecuteScalarAsync())!;
    }
    public async Task LoginAttempt(string key,bool success)
    {
        await using var c=await Open();await Sql(c,null,success?"DELETE FROM hospitalflow.auth_attempts WHERE key_hash=$1":
            "INSERT INTO hospitalflow.auth_attempts VALUES($1,1,now()+interval '15 minutes') ON CONFLICT(key_hash) DO UPDATE SET failures=CASE WHEN auth_attempts.blocked_until<now() THEN 1 ELSE auth_attempts.failures+1 END,blocked_until=CASE WHEN auth_attempts.blocked_until<now() THEN now()+interval '15 minutes' ELSE auth_attempts.blocked_until END",Hash(key));
    }
    public async Task ChangePassword(AuditContext audit,string currentPassword,string newPassword)
    {
        AccountValidation.Password(newPassword);
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();
        await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301)");
        var user=(await new RowMap<User>("users").Read(c,tx,"WHERE id=$1 FOR UPDATE",audit.ActorId!)).FirstOrDefault()??throw new RuleException("Account not found.");
        AccountValidation.Password(newPassword,user.Name,user.Email);
        var hasher=new PasswordHasher<User>();
        if(hasher.VerifyHashedPassword(user,user.PasswordHash,currentPassword)==PasswordVerificationResult.Failed)throw new RuleException("The current password is incorrect.");
        await Sql(c,tx,"SELECT set_config('hospitalflow.actor_id',$1,true),set_config('hospitalflow.correlation_id',$2,true)",audit.ActorId!,audit.CorrelationId);
        await Sql(c,tx,"UPDATE hospitalflow.users SET password_hash=$1 WHERE id=$2",hasher.HashPassword(user,newPassword),user.Id);
        await Sql(c,tx,"DELETE FROM hospitalflow.sessions WHERE user_id=$1",user.Id);
        await Sql(c,tx,"UPDATE hospitalflow.account_tokens SET consumed_at=now() WHERE user_id=$1 AND purpose='reset' AND consumed_at IS NULL",user.Id);
        await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("password-change",user.Id)],[]);
        await tx.CommitAsync();
    }
    public async Task<bool> DemoMode()
    {
        await using var c=await Open();await using var cmd=new NpgsqlCommand("SELECT value='true' FROM hospitalflow.system_settings WHERE key='demo_data'",c);return (await cmd.ExecuteScalarAsync()) is true;
    }
    public async Task<bool> RecordExists(string kind,string id)
    {
        await using var c=await Open();
        var table=kind=="patient"?"patients":"bills";
        await using var cmd=new NpgsqlCommand($"SELECT EXISTS(SELECT 1 FROM hospitalflow.{table} WHERE id=$1)",c);
        cmd.Parameters.AddWithValue(id);return (bool)(await cmd.ExecuteScalarAsync())!;
    }
    public async Task<List<Audit>> Activity(string? actorId,int offset,int limit)
    {
        await using var c=await Open();return await new RowMap<Audit>("activity_log").Read(c,null,
          "WHERE ($1::text IS NULL OR actor_id=$1) ORDER BY at DESC,id LIMIT $2 OFFSET $3",actorId is null?DBNull.Value:actorId,limit,offset);
    }
    public async Task<List<OperationalAlert>> Notifications()
    {
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();await RefreshAlerts(c,tx);
        var list=new List<OperationalAlert>();await using(var cmd=new NpgsqlCommand("SELECT id,rule,reference,title,message,target,opened_at FROM hospitalflow.notifications WHERE resolved_at IS NULL ORDER BY opened_at DESC",c,tx))
        await using(var r=await cmd.ExecuteReaderAsync())while(await r.ReadAsync())list.Add(new(r.GetString(0),r.GetString(1),r.GetString(2),r.GetString(3),r.GetString(4),r.GetString(5),new DateTimeOffset(r.GetDateTime(6))));
        await tx.CommitAsync();return list;
    }
    static Task RefreshAlerts(NpgsqlConnection c,NpgsqlTransaction tx)=>Sql(c,tx,"CALL hf_ops.refresh_alerts()");
    internal static async Task Sql(NpgsqlConnection c,NpgsqlTransaction? tx,string sql,params object[] values)
    {
        await using var cmd=new NpgsqlCommand(sql,c,tx);foreach(var v in values)cmd.Parameters.AddWithValue(v);await cmd.ExecuteNonQueryAsync();
    }
}
