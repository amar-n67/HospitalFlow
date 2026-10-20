using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.DataProtection;
using Npgsql;

sealed partial class Store {
    static string ProfileText(JsonElement body,string key,int max,bool required=true){
        if(!body.TryGetProperty(key,out var v)||v.ValueKind!=JsonValueKind.String){if(required)throw new RuleException("Complete all required profile fields.");return "";}
        var text=v.GetString()!.Trim();if(text.Length>max||(required&&text.Length==0))throw new RuleException("Check the length of "+key+".");return text;
    }
    public async Task SaveOwnProfile(JsonElement body,AuditContext audit,IDataProtector protector){
        if(body.ValueKind!=JsonValueKind.Object)throw new RuleException("Expected profile details.");
        ProfileText(body,"mobile",30);var mobile=Mobile(body.GetProperty("mobile").GetString()!);var address=ProfileText(body,"address",1000,false);var emergency=ProfileText(body,"emergencyContact",200,false);
        var email=AccountValidation.Email(ProfileText(body,"email",150));
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();
        await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301),set_config('hospitalflow.actor_id',$1,true),set_config('hospitalflow.correlation_id',$2,true)",audit.ActorId!,audit.CorrelationId);
        var user=(await new RowMap<User>("users").Read(c,tx,"WHERE id=$1 AND active",audit.ActorId!)).Single();
        if(email!=user.Email){
            var password=body.TryGetProperty("currentPassword",out var pw)&&pw.ValueKind==JsonValueKind.String?pw.GetString()!:"";
            if(new PasswordHasher<User>().VerifyHashedPassword(user,user.PasswordHash,password)==PasswordVerificationResult.Failed)throw new RuleException("Enter your current password to change your email.");
            await using var exists=new NpgsqlCommand("SELECT EXISTS(SELECT 1 FROM hospitalflow.users WHERE lower(email)=$1 UNION ALL SELECT 1 FROM hospitalflow.patients WHERE lower(email)=$1)",c,tx);exists.Parameters.AddWithValue(email);
            if((bool)(await exists.ExecuteScalarAsync())!)throw new RuleException("This email is unavailable.");
            await using var rate=new NpgsqlCommand("SELECT count(*) FROM hospitalflow.email_changes WHERE user_id=$1 AND created_at>now()-interval '15 minutes'",c,tx);rate.Parameters.AddWithValue(user.Id);
            if((long)(await rate.ExecuteScalarAsync())!>=3)throw new RuleException("Wait 15 minutes before requesting another email change.");
            AccountValidation.Password(password,user.Name,email);
            var token=Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
            await Sql(c,tx,"UPDATE hospitalflow.email_changes SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",user.Id);
            await Sql(c,tx,"INSERT INTO hospitalflow.email_changes(token_hash,user_id,email,password_fingerprint,expires_at) VALUES($1,$2,$3,$4,now()+interval '30 minutes')",Hash(token),user.Id,email,Hash(user.PasswordHash));
            var origin=config["Accounts:PublicOrigin"]??"http://localhost:5136";
            await Sql(c,tx,"INSERT INTO hospitalflow.account_mail(user_id,encrypted_message) VALUES($1,$2)",user.Id,protector.Protect(JsonSerializer.Serialize(new MailMessageData(email,"Confirm your HospitalFlow email change",$"Confirm your new email within 30 minutes:\n{origin.TrimEnd('/')}/#email-change?token={token}\nYour current email remains active until confirmation."))));
        }
        await Sql(c,tx,"UPDATE hospitalflow.patients SET phone=$1,address=$2,emergency_contact=$3 WHERE id=(SELECT patient_id FROM hospitalflow.patient_accounts WHERE user_id=$4)",mobile,address,emergency,user.Id);
        await Sql(c,tx,"INSERT INTO hospitalflow.person_profiles(user_id,mobile,address) SELECT $1,$2,$3 WHERE NOT EXISTS(SELECT 1 FROM hospitalflow.patient_accounts WHERE user_id=$1) ON CONFLICT(user_id) DO UPDATE SET mobile=EXCLUDED.mobile,address=EXCLUDED.address,updated_at=now()",user.Id,mobile,address);
        await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("profile-updated",user.Id)],[]);await tx.CommitAsync();
    }
    public async Task ConfirmEmailChange(string token,AuditContext audit){
        if(token.Length!=64||!token.All(Uri.IsHexDigit))throw new RuleException("Invalid or expired email change link.");
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301)");
        string id,email,fingerprint;await using(var cmd=new NpgsqlCommand("SELECT e.user_id,e.email,e.password_fingerprint FROM hospitalflow.email_changes e JOIN hospitalflow.users u ON u.id=e.user_id WHERE e.token_hash=$1 AND e.consumed_at IS NULL AND e.expires_at>now() AND u.active FOR UPDATE OF e,u",c,tx)){
            cmd.Parameters.AddWithValue(Hash(token));await using var r=await cmd.ExecuteReaderAsync();if(!await r.ReadAsync())throw new RuleException("Invalid or expired email change link.");id=r.GetString(0);email=r.GetString(1);fingerprint=r.GetString(2);
        }
        var account=(await new RowMap<User>("users").Read(c,tx,"WHERE id=$1",id)).Single();
        if(Hash(account.PasswordHash)!=fingerprint)throw new RuleException("This email change link expired after your password changed. Request another link.");
        await Sql(c,tx,"SELECT set_config('hospitalflow.actor_id',$1,true),set_config('hospitalflow.correlation_id',$2,true)",id,audit.CorrelationId);
        await Sql(c,tx,"SELECT set_config('hospitalflow.patient_id',COALESCE((SELECT patient_id FROM hospitalflow.patient_accounts WHERE user_id=$1),''),true)",id);
        await Sql(c,tx,"SELECT set_config('hospitalflow.hospital_id',COALESCE((SELECT hospital_id FROM hospitalflow.hospital_memberships WHERE user_id=$1 AND active ORDER BY hospital_id LIMIT 1),hf_security.current_hospital()),true)",id);
        await Sql(c,tx,"UPDATE hospitalflow.users SET email=$1 WHERE id=$2",email,id);
        await Sql(c,tx,"UPDATE hospitalflow.patients SET email=$1 WHERE id=(SELECT patient_id FROM hospitalflow.patient_accounts WHERE user_id=$2)",email,id);
        await Sql(c,tx,"UPDATE hospitalflow.email_changes SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",id);
        await Sql(c,tx,"UPDATE hospitalflow.account_tokens SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",id);
        await Sql(c,tx,"DELETE FROM hospitalflow.sessions WHERE user_id=$1",id);
        await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("profile-email-confirmed",id)],[]);await tx.CommitAsync();
    }
    public async Task<object> WorkTasks(string id,bool full){
        await using var c=await Open();await using var cmd=new NpgsqlCommand("SELECT t.id,t.title,t.location,t.due_at,t.status,u.name,u.registration_id FROM hospitalflow.work_tasks t JOIN hospitalflow.users u ON u.id=t.assigned_to WHERE ($1 OR t.assigned_to=$2) ORDER BY t.due_at,t.id",c);cmd.Parameters.AddWithValue(full);cmd.Parameters.AddWithValue(id);
        await using var r=await cmd.ExecuteReaderAsync();var list=new List<object>();while(await r.ReadAsync())list.Add(new{id=r.GetString(0),title=r.GetString(1),location=r.GetString(2),dueAt=r.GetDateTime(3),status=r.GetString(4),assignee=r.GetString(5),registrationId=r.GetString(6)});return list;
    }
    public async Task SaveWorkTask(JsonElement body,AuditContext audit,bool full){
        if(body.ValueKind!=JsonValueKind.Object)throw new RuleException("Expected task details.");
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301),set_config('hospitalflow.actor_id',$1,true),set_config('hospitalflow.correlation_id',$2,true)",audit.ActorId!,audit.CorrelationId);
        var id=ProfileText(body,"id",100,false);
        if(id.Length==0){
            if(!full)throw new RuleException("Only administration can assign tasks.");
            var target=ProfileText(body,"assignedTo",100);var title=ProfileText(body,"title",150);var location=ProfileText(body,"location",150);if(title.Length<2)throw new RuleException("Enter a task title.");
            if(!DateTimeOffset.TryParse(ProfileText(body,"dueAt",100),out var due))throw new RuleException("Enter a valid due date.");
            id=Guid.NewGuid().ToString("N");await using var cmd=new NpgsqlCommand("INSERT INTO hospitalflow.work_tasks(id,assigned_to,created_by,title,location,due_at) SELECT $1,id,$3,$4,$5,$6 FROM hospitalflow.users WHERE id=$2 AND active AND role IN ('Nurse','Volunteer') AND EXISTS(SELECT 1 FROM hospitalflow.hospital_memberships m WHERE m.user_id=users.id AND m.hospital_id=hf_security.current_hospital() AND m.active)",c,tx);
            cmd.Parameters.AddWithValue(id);cmd.Parameters.AddWithValue(target);cmd.Parameters.AddWithValue(audit.ActorId!);cmd.Parameters.AddWithValue(title);cmd.Parameters.AddWithValue(location);cmd.Parameters.AddWithValue(due.ToUniversalTime());if(await cmd.ExecuteNonQueryAsync()!=1)throw new RuleException("Choose an active nurse or volunteer.");
        }else{
            var status=ProfileText(body,"status",30);if(status is not("In progress" or "Completed"))throw new RuleException("Choose a valid task status.");
            await using var cmd=new NpgsqlCommand("UPDATE hospitalflow.work_tasks SET status=$1,updated_at=now() WHERE id=$2 AND (assigned_to=$3 OR $4) AND ((status='Assigned' AND $1='In progress') OR (status='In progress' AND $1='Completed'))",c,tx);cmd.Parameters.AddWithValue(status);cmd.Parameters.AddWithValue(id);cmd.Parameters.AddWithValue(audit.ActorId!);cmd.Parameters.AddWithValue(full);if(await cmd.ExecuteNonQueryAsync()!=1)throw new RuleException("Task is unavailable or its status has changed.");
        }
        await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("work-task-updated",id)],[]);await tx.CommitAsync();
    }
}
static class WorkspaceEndpoints {
    public static void Map(WebApplication app,Store store){
        AuditContext Audit(HttpContext c)=>new(c.User.Identity?.Name??"Email confirmation",c.User.FindFirstValue(ClaimTypes.NameIdentifier),c.TraceIdentifier,c.Connection.RemoteIpAddress?.ToString(),c.Request.Method);
        app.MapPost("/api/account/profile",async(JsonElement body,HttpContext ctx)=>{
            var key="profile-change:"+ctx.User.FindFirstValue(ClaimTypes.NameIdentifier);if(await store.IsBlocked(key))return Results.StatusCode(429);await store.LoginAttempt(key,false);
            await store.SaveOwnProfile(body,Audit(ctx),app.Services.GetRequiredService<IDataProtectionProvider>().CreateProtector("HospitalFlow.AccountMail.v1"));await store.LoginAttempt(key,true);return Results.Ok(new{message="Profile saved. If your email changed, confirm the link sent to the new address."});
        }).RequireAuthorization();
        app.MapPost("/api/account/confirm-email-change",async(JsonElement body,HttpContext ctx)=>{var key="email-confirm:"+ctx.Connection.RemoteIpAddress;if(await store.IsBlocked(key))return Results.StatusCode(429);await store.LoginAttempt(key,false);await store.ConfirmEmailChange(StoreToken(body),Audit(ctx));await ctx.SignOutAsync();return Results.Ok(new{message="Email updated. Sign in with your new email or registration ID."});});
        app.MapGet("/api/work/tasks",async(HttpContext ctx)=>{await store.Log(Audit(ctx).Event("work-tasks-view","own assignments"));return Results.Ok(await store.WorkTasks(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!,Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role))));}).RequireAuthorization();
        app.MapPost("/api/work/tasks",async(JsonElement body,HttpContext ctx)=>{var role=ctx.User.FindFirstValue(ClaimTypes.Role);if(!Access.Full(role)&&role is not("Nurse" or "Volunteer"))return Results.Forbid();if(!Access.Full(role)&&!body.TryGetProperty("id",out _))return Results.Forbid();await store.SaveWorkTask(body,Audit(ctx),Access.Full(role));return Results.Ok();}).RequireAuthorization();
    }
    static string StoreToken(JsonElement body)=>body.ValueKind==JsonValueKind.Object&&body.TryGetProperty("token",out var t)&&t.ValueKind==JsonValueKind.String?t.GetString()!:"";
}
