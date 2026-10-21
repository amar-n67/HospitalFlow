using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Npgsql;
sealed partial class Store {
    public async Task<List<PersonEntry>> People(string actorId,string role,bool ownOnly=false){
        await using var c=await Open();await using var cmd=new NpgsqlCommand("SELECT u.id,u.registration_id,u.name,u.email,u.role,a.patient_id,p.doctor_id,COALESCE(patient.phone,p.mobile),COALESCE(patient.dob,p.dob)::text,COALESCE(patient.sex,p.sex),COALESCE(patient.address,p.address),p.department,p.job_title,p.occupation,u.active FROM hospitalflow.users u LEFT JOIN hospitalflow.person_profiles p ON p.user_id=u.id LEFT JOIN hospitalflow.patient_accounts a ON a.user_id=u.id LEFT JOIN hospitalflow.patients patient ON patient.id=a.patient_id WHERE ($1::boolean OR u.id=$2 OR($3::boolean AND u.role IN ('Doctor','Nurse','Volunteer','User'))) AND (NOT $4::boolean OR u.id=$2) AND (u.id=$2 OR EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships m WHERE m.user_id=u.id AND m.hospital_id=hf_security.current_hospital() AND m.active)) ORDER BY u.registration_id",c);
        cmd.Parameters.AddWithValue(Access.Full(role));cmd.Parameters.AddWithValue(actorId);cmd.Parameters.AddWithValue(role=="Doctor");cmd.Parameters.AddWithValue(ownOnly);
        await using var r=await cmd.ExecuteReaderAsync();var list=new List<PersonEntry>();string? Text(int i)=>r.IsDBNull(i)?null:r.GetString(i);
        while(await r.ReadAsync())list.Add(new(r.GetString(0),r.GetString(1),r.GetString(2),r.GetString(3),r.GetString(4),Text(5),Text(6),Text(7),Text(8),Text(9),Text(10),Text(11),Text(12),Text(13),r.GetBoolean(14)));return list;
    }
    public async Task<string> SavePerson(JsonElement body,AuditContext audit,string key,bool update=false){
        if(!Guid.TryParse(key,out var retryKey))throw new RuleException("A valid Idempotency-Key is required.");
        string Text(string name,int max=1000,bool required=true){var value=body.TryGetProperty(name,out var e)&&e.ValueKind==JsonValueKind.String?(name=="password"?e.GetString()!:e.GetString()!.Trim()):"";if(value.Length>max||(required&&value.Length==0))throw new RuleException("Check the "+name+" field.");return value;}
        var name=Text("name",100);Text("mobile",30);var mobile=Mobile(body.GetProperty("mobile").GetString()!);var date=Text("dob",10);if(!DateOnly.TryParseExact(date,"yyyy-MM-dd",out var dob)||dob<new DateOnly(1900,1,1)||dob>DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow,TimeZoneInfo.FindSystemTimeZoneById(HospitalTimezone)).Date))throw new RuleException("Enter a valid date of birth, not in the future.");
        var sex=Text("sex",30);if(sex is not("Male" or "Female" or "Other" or "Prefer not to say"))throw new RuleException("Choose a valid sex.");
        var email=AccountValidation.Email(Text("email",150));var requested=Text("role",20);if(requested is not("Admin" or "Developer" or "Doctor" or "Nurse" or "Volunteer"))throw new RuleException("Choose a staff type, or use patient registration.");
        if(requested=="Developer"&&!await NetworkOperator(audit.ActorId!))throw new RuleException("Only a network operator can create Developer access.");
        if(update&&await NetworkOperator(Text("id",100))&&!await NetworkOperator(audit.ActorId!))throw new RuleException("Only a network operator can manage this profile.");
        if(update&&!await UserInHospital(Text("id",100)))throw new RuleException("Account is outside this hospital.");
        var department=Text("department",80,requested is "Doctor" or "Nurse");var title=Text("jobTitle",100,false);var address=Text("address",1000,false);var occupation=Text("occupation",40,requested=="Volunteer");
        if(requested=="Volunteer"&&occupation is not("Guard" or "Washerman" or "Housekeeping" or "Other"))throw new RuleException("Choose a volunteer occupation.");
        var hash=RequestHash(body.GetRawText());await using var c=await Open();await using var tx=await c.BeginTransactionAsync();
        await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301),set_config('hospitalflow.actor_id',$1,true),set_config('hospitalflow.correlation_id',$2,true)",audit.ActorId!,audit.CorrelationId);
        await Sql(c,tx,"SELECT hf_security.require_actor(ARRAY['Doctor'])");
        var actor=(await new RowMap<User>("users").Read(c,tx,"WHERE id=$1",audit.ActorId!)).Single();
        if(!Access.Full(actor.Role)&&(requested is "Admin" or "Developer"))throw new RuleException("Only Admin or Developer can create privileged accounts.");
        await using(var prior=new NpgsqlCommand("SELECT action,request_hash,reference FROM hospitalflow.idempotency_keys WHERE user_id=$1 AND key=$2",c,tx)){
            prior.Parameters.AddWithValue(audit.ActorId!);prior.Parameters.AddWithValue(retryKey);await using var r=await prior.ExecuteReaderAsync();if(await r.ReadAsync()){if(r.GetString(0)!=(update?"person-update":"person")||r.GetString(1)!=hash)throw new RuleException("Retry key already belongs to a different entry.");return r.GetString(2);}
        }
        var id=update?Text("id",100):Guid.NewGuid().ToString("N");string? doctorId=null;
        if(update){
            var target=(await new RowMap<User>("users").Read(c,tx,"WHERE id=$1 FOR UPDATE",id)).SingleOrDefault()??throw new RuleException("Person not found.");
            if(!Access.Full(actor.Role)&&requested=="Doctor"){
                await using var departmentCheck=new NpgsqlCommand("SELECT COALESCE(d.department,p.department,s.department) FROM hospitalflow.users u LEFT JOIN hospitalflow.person_profiles p ON p.user_id=u.id LEFT JOIN hospitalflow.doctors d ON d.id=p.doctor_id LEFT JOIN hospitalflow.staff_members s ON s.user_id=u.id AND s.active WHERE u.id=$1",c,tx);departmentCheck.Parameters.AddWithValue(id);
                var registeredDepartment=await departmentCheck.ExecuteScalarAsync() as string;
                if(registeredDepartment!=department)throw new RuleException("Only administration can change a doctor's registered department.");
            }

            if(target.Role!=requested||target.Email!=email)throw new RuleException("Role and login email cannot be changed in a contact edit.");
            if(!Access.Full(actor.Role)&&target.Role is not("Doctor" or "Nurse" or "Volunteer"))throw new RuleException("This contact is restricted to administration.");
            await using(var patient=new NpgsqlCommand("SELECT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=$1)",c,tx)){patient.Parameters.AddWithValue(id);if((bool)(await patient.ExecuteScalarAsync())!)throw new RuleException("Use the patient directory to edit a patient.");}
            await Sql(c,tx,"UPDATE hospitalflow.users SET name=$1 WHERE id=$2",name,id);
            await using var linked=new NpgsqlCommand("SELECT doctor_id FROM hospitalflow.person_profiles WHERE user_id=$1",c,tx);linked.Parameters.AddWithValue(id);doctorId=await linked.ExecuteScalarAsync() as string;
        }else{
            const string password="1234";
            await Sql(c,tx,"INSERT INTO hospitalflow.users(id,name,email,role,password_hash,active,email_confirmed) VALUES($1,$2,$3,$4,$5,true,true)",id,name,email,requested,new PasswordHasher<User>().HashPassword(new User(),password));
        }
        if(!update)await Sql(c,tx,"INSERT INTO hospitalflow.staff_onboarding(user_id) VALUES($1)",id);
        if(department.Length>0)await Sql(c,tx,"INSERT INTO hospitalflow.departments(name) VALUES($1) ON CONFLICT DO NOTHING",department);
        if(requested=="Doctor"){
            var start=Text("start",5);var end=Text("end",5);if(!TimeOnly.TryParseExact(start,"HH:mm",out var from)||!TimeOnly.TryParseExact(end,"HH:mm",out var to)||from>=to)throw new RuleException("Enter a valid provider shift.");
            if(doctorId==null){
                await using var number=new NpgsqlCommand("SELECT hf_api.new_id('DR')",c,tx);doctorId=(string)(await number.ExecuteScalarAsync())!;
                await Sql(c,tx,"INSERT INTO hospitalflow.doctors(id,name,department,start,\"end\",registration_id) SELECT $1,$2,$3,$4,$5,registration_id FROM hospitalflow.users WHERE id=$6",doctorId,name,department,from,to,id);
            }else await Sql(c,tx,"UPDATE hospitalflow.doctors SET name=$1,department=$2,start=$3,\"end\"=$4 WHERE id=$5",name,department,from,to,doctorId);
        }
        await using(var profile=new NpgsqlCommand("INSERT INTO hospitalflow.person_profiles(user_id,doctor_id,mobile,dob,sex,address,department,job_title,occupation) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(user_id) DO UPDATE SET doctor_id=EXCLUDED.doctor_id,mobile=EXCLUDED.mobile,dob=EXCLUDED.dob,sex=EXCLUDED.sex,address=EXCLUDED.address,department=EXCLUDED.department,job_title=EXCLUDED.job_title,occupation=EXCLUDED.occupation,updated_at=now()",c,tx)){
            profile.Parameters.AddWithValue(id);profile.Parameters.Add(new NpgsqlParameter{NpgsqlDbType=NpgsqlTypes.NpgsqlDbType.Text,Value=(object?)doctorId??DBNull.Value});profile.Parameters.AddWithValue(mobile);profile.Parameters.AddWithValue(dob);profile.Parameters.AddWithValue(sex);profile.Parameters.AddWithValue(address);profile.Parameters.Add(new NpgsqlParameter{NpgsqlDbType=NpgsqlTypes.NpgsqlDbType.Text,Value=department.Length>0?department:DBNull.Value});profile.Parameters.AddWithValue(title);profile.Parameters.Add(new NpgsqlParameter{NpgsqlDbType=NpgsqlTypes.NpgsqlDbType.Text,Value=requested=="Volunteer"?occupation:DBNull.Value});await profile.ExecuteNonQueryAsync();
        }
        await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event(update?"person-update":"person",id)],[]);
        await Sql(c,tx,"INSERT INTO hospitalflow.idempotency_keys(user_id,key,action,request_hash,reference) VALUES($1,$2,$3,$4,$5)",audit.ActorId!,retryKey,update?"person-update":"person",hash,id);
        await tx.CommitAsync();return id;
    }
}
