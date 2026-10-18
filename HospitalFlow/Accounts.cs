using System.Net.Mail;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Npgsql;

static class Access {
    public static readonly string[] Permissions=["Reception","Doctor","Nurse","Pharmacist","Billing"];
    public static bool Full(string? role)=>role is "Admin" or "Developer";
}
record AccountInfo(string Id,string Name,string Email,string Role,bool Active,bool EmailConfirmed,string[] Permissions);
record MailMessageData(string To,string Subject,string Body);
sealed partial class Store {
    public async Task<string[]> Permissions(string id) {
        await using var c=await Open();await using var cmd=new NpgsqlCommand("SELECT permission FROM hospitalflow.user_permissions WHERE user_id=$1 ORDER BY permission",c);cmd.Parameters.AddWithValue(id);
        await using var r=await cmd.ExecuteReaderAsync();var list=new List<string>();while(await r.ReadAsync())list.Add(r.GetString(0));return list.ToArray();
    }
    public async Task<List<AccountInfo>> Accounts() {
        await using var c=await Open();await using var cmd=new NpgsqlCommand("SELECT u.id,u.name,u.email,u.role,u.active,u.email_confirmed,ARRAY(SELECT permission FROM hospitalflow.user_permissions p WHERE p.user_id=u.id ORDER BY permission) FROM hospitalflow.users u ORDER BY u.created_at DESC",c);
        await using var r=await cmd.ExecuteReaderAsync();var result=new List<AccountInfo>();while(await r.ReadAsync())result.Add(new(r.GetString(0),r.GetString(1),r.GetString(2),r.GetString(3),r.GetBoolean(4),r.GetBoolean(5),r.GetFieldValue<string[]>(6)));return result;
    }
    public async Task Register(string name,string email,string password,AuditContext audit,IDataProtector protector) {
        name=name.Trim();email=AccountValidation.Email(email);AccountValidation.Password(password,name,email);if(name.Length is <2 or >100)throw new RuleException("Enter your full name (2–100 characters).");
        var user=new User{Id=Guid.NewGuid().ToString("N"),Name=name,Email=email,Role="User",Active=false};var hash=new PasswordHasher<User>().HashPassword(user,password);
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301)");
        await using var cmd=new NpgsqlCommand("INSERT INTO hospitalflow.users(id,name,email,role,password_hash,active,email_confirmed) VALUES($1,$2,$3,'User',$4,false,false) ON CONFLICT DO NOTHING RETURNING id",c,tx);
        cmd.Parameters.AddWithValue(user.Id);cmd.Parameters.AddWithValue(name);cmd.Parameters.AddWithValue(email);cmd.Parameters.AddWithValue(hash);
        if(await cmd.ExecuteScalarAsync() is string id) {
            await QueueToken(c,tx,id,email,"verify",protector);
            await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("signup",id,"Pending verification")],[]);
        }
        await tx.CommitAsync();
    }
    public async Task RequestToken(string email,string purpose,AuditContext audit,IDataProtector protector) {
        email=AccountValidation.Email(email);await using var c=await Open();await using var tx=await c.BeginTransactionAsync();await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301)");
        await using var cmd=new NpgsqlCommand("SELECT id FROM hospitalflow.users WHERE lower(email)=$1 AND (($2='reset' AND active AND email_confirmed) OR ($2='verify' AND NOT email_confirmed))",c,tx);
        cmd.Parameters.AddWithValue(email);cmd.Parameters.AddWithValue(purpose);
        if(await cmd.ExecuteScalarAsync() is string id)await QueueToken(c,tx,id,email,purpose,protector);
        await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("account-link-request",purpose,"Accepted")],[]);await tx.CommitAsync();
    }
    async Task QueueToken(NpgsqlConnection c,NpgsqlTransaction tx,string id,string email,string purpose,IDataProtector protector) {
        await using(var rate=new NpgsqlCommand("SELECT count(*) FROM hospitalflow.account_tokens WHERE user_id=$1 AND purpose=$2 AND created_at>now()-interval '15 minutes'",c,tx)) {
            rate.Parameters.AddWithValue(id);rate.Parameters.AddWithValue(purpose);if((long)(await rate.ExecuteScalarAsync())!>=3)return;
        }
        var token=Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        await Sql(c,tx,"UPDATE hospitalflow.account_tokens SET consumed_at=now() WHERE user_id=$1 AND purpose=$2 AND consumed_at IS NULL",id,purpose);
        await Sql(c,tx,"INSERT INTO hospitalflow.account_tokens(token_hash,user_id,purpose,expires_at) VALUES($1,$2,$3,now()+$4::interval)",Hash(token),id,purpose,purpose=="verify"?"24 hours":"30 minutes");
        var origin=config["Accounts:PublicOrigin"]??(environment.IsDevelopment()?"http://localhost:5136":throw new InvalidOperationException("Accounts:PublicOrigin is required."));
        var link=origin.TrimEnd('/')+"/#"+purpose+"?token="+token;
        var message=new MailMessageData(email,purpose=="verify"?"Verify your HospitalFlow email":"Reset your HospitalFlow password",purpose=="verify"?$"Verify your email using this link (valid for 24 hours):\n{link}\n\nAn administrator must then approve your account and assign access. If you did not sign up, ignore this email.":$"Reset your password using this link (valid for 30 minutes):\n{link}\n\nIf you did not request this, ignore this email. Your password has not changed.");
        await Sql(c,tx,"INSERT INTO hospitalflow.account_mail(user_id,encrypted_message) VALUES($1,$2)",id,protector.Protect(JsonSerializer.Serialize(message)));
    }
    public async Task ConsumeToken(string token,string purpose,string? password,AuditContext audit) {
        if(token.Length!=64||!token.All(Uri.IsHexDigit))throw new RuleException("This link is invalid or expired. Request a new link.");if(purpose=="reset")AccountValidation.Password(password??"");
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301)");
        await using var cmd=new NpgsqlCommand("SELECT t.user_id FROM hospitalflow.account_tokens t JOIN hospitalflow.users u ON u.id=t.user_id WHERE t.token_hash=$1 AND t.purpose=$2 AND t.consumed_at IS NULL AND t.expires_at>now() AND ($2='verify' OR (u.active AND u.email_confirmed)) FOR UPDATE OF t,u",c,tx);
        cmd.Parameters.AddWithValue(Hash(token));cmd.Parameters.AddWithValue(purpose);var id=await cmd.ExecuteScalarAsync() as string??throw new RuleException("This link is invalid or expired. Request a new link.");
        await Sql(c,tx,"SELECT set_config('hospitalflow.correlation_id',$1,true)",audit.CorrelationId);
        if(purpose=="verify")await Sql(c,tx,"UPDATE hospitalflow.users SET email_confirmed=true WHERE id=$1",id);
        else {
            var user=(await new RowMap<User>("users").Read(c,tx,"WHERE id=$1",id)).Single();
            AccountValidation.Password(password!,user.Name,user.Email);
            await Sql(c,tx,"UPDATE hospitalflow.users SET password_hash=$1 WHERE id=$2",new PasswordHasher<User>().HashPassword(new User(),password!),id);
            await Sql(c,tx,"DELETE FROM hospitalflow.sessions WHERE user_id=$1",id);
        }
        await Sql(c,tx,"UPDATE hospitalflow.account_tokens SET consumed_at=now() WHERE user_id=$1 AND purpose=$2 AND consumed_at IS NULL",id,purpose);
        await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event(purpose=="verify"?"email-verified":"password-reset",id)],[]);await tx.CommitAsync();
    }
    public async Task ManageAccount(AccountInfo input,AuditContext audit) {
        if(input.Id==audit.ActorId)throw new RuleException("Ask another administrator to change your own role or access.");
        if(input.Role is not ("User" or "Admin" or "Developer")||input.Permissions.Any(p=>!Access.Permissions.Contains(p)))throw new RuleException("Choose a valid role and permissions.");
        if(await PatientAccount(input.Id)!=null&&(input.Role!="User"||input.Permissions.Length>0))throw new RuleException("Patient accounts cannot receive staff access. Use a separate staff identity.");
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();
        await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301),set_config('hospitalflow.actor_id',$1,true),set_config('hospitalflow.correlation_id',$2,true)",audit.ActorId!,audit.CorrelationId);
        await Sql(c,tx,"SELECT hf_security.require_actor(ARRAY[]::text[])");
        await using(var exists=new NpgsqlCommand("SELECT EXISTS(SELECT 1 FROM hospitalflow.users WHERE id=$1)",c,tx)){exists.Parameters.AddWithValue(input.Id);if(!(bool)(await exists.ExecuteScalarAsync())!)throw new RuleException("Account not found.");}
        await Sql(c,tx,"UPDATE hospitalflow.users SET role=$1,active=$2 WHERE id=$3",input.Role,input.Active,input.Id);
        await Sql(c,tx,"DELETE FROM hospitalflow.user_permissions WHERE user_id=$1",input.Id);
        if(input.Role=="User")foreach(var permission in input.Permissions.Distinct())await Sql(c,tx,"INSERT INTO hospitalflow.user_permissions VALUES($1,$2)",input.Id,permission);
        await Sql(c,tx,"DELETE FROM hospitalflow.sessions WHERE user_id=$1",input.Id);
        await Sql(c,tx,"UPDATE hospitalflow.account_tokens SET consumed_at=now() WHERE user_id=$1 AND purpose='reset' AND consumed_at IS NULL",input.Id);
        await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("account-access-change",input.Id)],[]);await tx.CommitAsync();
    }
}
