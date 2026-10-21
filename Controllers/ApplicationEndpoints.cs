using System.Security.Claims;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.DataProtection.KeyManagement;
using Microsoft.AspNetCore.Identity;
using Npgsql;

static class ApplicationEndpoints {
 public static void Map(WebApplication app,Store store){
app.MapGet("/api/health",()=>new{status="ok",storage=store.Mode,version=ApplicationRelease.CurrentVersion,commit=ApplicationRelease.Commit,workingTree=ApplicationRelease.WorkingTree});
var loginHasher=new PasswordHasher<User>();var dummyUser=new User();var dummyHash=loginHasher.HashPassword(dummyUser,Convert.ToHexString(RandomNumberGenerator.GetBytes(32)));
app.MapPost("/api/login",async(Login input,HttpContext ctx)=>{
    var audit=Context(ctx);var key=ctx.Connection.RemoteIpAddress?.ToString()??"local";
    var accountKey="signin:"+store.RequestHash((input.Email??"").Trim().ToLowerInvariant());
    if(await store.IsBlocked(key)||await store.IsBlocked(accountKey)){await store.Log(audit.Event("login","Account sign-in","Rate limited",429));return Results.Json(new{error="Too many attempts. Try again in 15 minutes."},statusCode:429);}
    var valid=!string.IsNullOrWhiteSpace(input.Email)&&!string.IsNullOrEmpty(input.Password)&&input.Email.Length<=150&&input.Password.Length<=128;
    User? user=null;if(valid)try{user=await store.UserByLogin(input.Email!);}catch(RuleException){}
    var verified=loginHasher.VerifyHashedPassword(user??dummyUser,user?.PasswordHash??dummyHash,valid?input.Password:"");
    var patientAccess=user==null?null:await store.PatientAccount(user.Id);
    var staffExpiry=user==null?null:await store.StaffOnboardingExpiry(user.Id);
    var success=!(staffExpiry.HasValue&&staffExpiry.Value<=DateTimeOffset.UtcNow)&&user is {Active:true}&&verified!=PasswordVerificationResult.Failed&&!(patientAccess is {MustChangePassword:true}&&patientAccess.TemporaryExpiresAt<=DateTimeOffset.UtcNow);
    await store.LoginAttempt(key,success);await store.LoginAttempt(accountKey,success);
    if(!success){await store.Log(audit.Event("login","Account sign-in","Rejected",401));return Results.Json(new{error="Email or password is incorrect."},statusCode:401);}
    Store.SetHospitalContext(await store.ResolveHospital(user!.Id,null));
    if(patientAccess is {MustChangePassword:true}||staffExpiry.HasValue) {
        await ctx.SignOutAsync();var challenge=await store.CreatePatientChallenge(user!.Id);await store.Log(audit.Event("patient-first-signin",patientAccess?.PatientId??user.Id,"Verification required"));
        return Results.Ok(new{requiresOnboarding=true,challenge,message="Verify your date of birth and set a new password to continue."});
    }
    var principal=new ClaimsPrincipal(new ClaimsIdentity(new[]{new Claim(ClaimTypes.NameIdentifier,user!.Id),new Claim(ClaimTypes.Name,user.Name),new Claim(ClaimTypes.Role,user.Role)},CookieAuthenticationDefaults.AuthenticationScheme));
    ctx.User=principal;await ctx.SignInAsync(principal);
    await store.Log(Context(ctx).Event("login",user.Id));return Results.Ok(new{user.Name,user.Role});
});
app.MapPost("/api/logout",async(HttpContext ctx)=>{await store.Log(Context(ctx).Event("logout",ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!));await ctx.SignOutAsync();return Results.Ok();}).RequireAuthorization();
app.MapGet("/api/me",async(HttpContext ctx)=>new{id=ctx.User.FindFirstValue(ClaimTypes.NameIdentifier),name=ctx.User.Identity!.Name,email=(await store.UserById(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!))?.Email,theme=await store.UserTheme(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!),role=ctx.User.FindFirstValue(ClaimTypes.Role),registrationId=(await store.UserById(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!))?.RegistrationId,profile=(await store.People(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!,ctx.User.FindFirstValue(ClaimTypes.Role)!,true)).FirstOrDefault(),permissions=await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!),hospitalId=Store.ContextHospital?.HospitalId,canManageNetwork=await store.NetworkOperator(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!),patientId=(await store.PatientAccount(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!))?.PatientId,storage=store.Mode,version=ApplicationRelease.CurrentVersion,commit=ApplicationRelease.Commit,workingTree=ApplicationRelease.WorkingTree,demoData=await store.DemoMode()}).RequireAuthorization();
app.MapGet("/api/state",async(HttpContext ctx)=>{
    var patientAccess=await store.PatientAccount(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    if(patientAccess!=null)return Results.Ok(await store.PatientState(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!));
    var s=await store.Current();var full=Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role));var grants=await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    bool Has(params string[] permissions)=>full||permissions.Any(grants.Contains);
    var operational=full||grants.Length>0;
    var patients=s.Patients.Where(_=>operational).Select(p=>new{p.Id,p.Name,p.Dob,p.Sex,Phone=Has("Reception","Doctor","Nurse")?p.Phone:"Restricted",p.Email,p.RegistrationId,p.Address,p.EmergencyContact,p.Created});
    return Results.Ok(new{patients,doctors=operational?s.Doctors:[],appointments=Has("Reception","Doctor","Nurse")?s.Appointments:[],beds=Has("Nurse")?s.Beds:[],admissions=Has("Nurse","Doctor")?s.Admissions:[],
        medicines=Has("Pharmacist","Doctor")?s.Medicines:[],prescriptions=Has("Pharmacist","Doctor")?s.Prescriptions:[],bills=Has("Billing")?s.Bills:[],notes=Has("Doctor","Nurse")?s.Notes:[],
        audit=full?s.Audit:s.Audit.Where(x=>x.ActorId==ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)).ToList(),
        users=full?await store.Accounts():[],movements=Has("Pharmacist")?s.Movements:[],serverTime=DateTimeOffset.UtcNow});
}).RequireAuthorization();
app.MapGet("/api/activity",async(HttpContext ctx,int? offset,int? limit)=>Results.Ok(await store.Activity(Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role))?null:ctx.User.FindFirstValue(ClaimTypes.NameIdentifier),Math.Max(0,offset??0),Math.Clamp(limit??100,1,500)))).RequireAuthorization();
app.MapGet("/api/notifications",async(HttpContext ctx)=>{
    var list=await store.Notifications();var full=Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role));var grants=await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    return Results.Ok(list.Where(a=>full||(a.Link=="pharmacy"&&grants.Contains("Pharmacist"))||(a.Link=="appointments"&&grants.Contains("Reception"))||(a.Link=="beds"&&grants.Contains("Nurse"))));
}).RequireAuthorization();
app.MapPost("/api/activity",async(JsonElement body,HttpContext ctx)=>{
    if(body.ValueKind!=JsonValueKind.Object||!body.TryGetProperty("event",out var evt)||evt.ValueKind!=JsonValueKind.String)return Results.BadRequest();
    var action=evt.GetString();if(action is not("page-view" or "report-export" or "record-view"))return Results.BadRequest();
    var reference=body.TryGetProperty("reference",out var r)&&r.ValueKind==JsonValueKind.String?r.GetString():null;
    if(action=="record-view") {
        if(reference==null||reference.Length>100||!body.TryGetProperty("entity",out var entity)||entity.ValueKind!=JsonValueKind.String)return Results.BadRequest();
        var kind=entity.GetString();if(kind is not("patient" or "invoice"))return Results.BadRequest();
        if(await store.PatientAccount(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!)!=null) {
            if(!await store.PatientOwns(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!,kind!,reference))return Results.Forbid();
            await store.Log(Context(ctx).Event("record-view",kind+":"+reference));return Results.Ok();
        }
        if(kind=="patient"&&!Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role))&&(await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!)).Length==0)return Results.Forbid();
        if(kind=="invoice"&&!Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role))&&!(await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!)).Contains("Billing"))return Results.Forbid();
        if(!await store.RecordExists(kind,reference))return Results.NotFound();
        await store.Log(Context(ctx).Event("record-view",kind+":"+reference));return Results.Ok();
    }
    if(await store.PatientAccount(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!)!=null) {
        if(reference is not("patient-home" or "patient-appointments" or "patient-billing" or "patient-care" or "profile" or "hospitals" or "referrals" or "hospital-history"))return Results.Forbid();
        await store.Log(Context(ctx).Event(action,reference!));return Results.Ok();
    }
    var allowed=new[]{"dashboard","patients","appointments","doctors","beds","admissions","clinical","pharmacy","billing","reports","alerts","admin","operations","people","bills","profile","tasks","nursing","hospitals","referrals","hospital-history","hospital-access","attendance","hospital-leave"};
    if(reference==null||!allowed.Contains(reference))return Results.BadRequest();
    if((reference is "billing" or "bills")&&!Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role))&&!(await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!)).Contains("Billing"))return Results.Forbid();
    await store.Log(Context(ctx).Event(action,reference));return Results.Ok();
}).RequireAuthorization();
app.MapPost("/api/account/password",async(JsonElement body,HttpContext ctx)=>{
    if(!body.TryGetProperty("currentPassword",out var current)||current.ValueKind!=JsonValueKind.String||!body.TryGetProperty("newPassword",out var next)||next.ValueKind!=JsonValueKind.String)return Results.BadRequest();
    var throttle="password-change:"+ctx.User.FindFirstValue(ClaimTypes.NameIdentifier);if(await store.IsBlocked(throttle))return Results.StatusCode(429);await store.LoginAttempt(throttle,false);
    await store.ChangePassword(Context(ctx),current.GetString()!,next.GetString()!);await store.LoginAttempt(throttle,true);await ctx.SignOutAsync();return Results.Ok();
}).RequireAuthorization();
app.MapPost("/api/actions/{action}",async(string action,JsonElement input,HttpContext ctx)=>{
    var role=ctx.User.FindFirstValue(ClaimTypes.Role)!;
    if(role=="Admin"&&Access.ClinicalActions.Contains(action))return Results.Forbid();
    var permissions=action switch {
        "patient" or "patient-update"=>new[]{"Reception","Doctor"},
        "appointment"=>new[]{"Reception"},"appointment-status"=>new[]{"Reception","Doctor"},
        "admit" or "transfer" or "discharge" or "bed-status"=>new[]{"Nurse"},
        "medicine" or "stock" or "dispense"=>new[]{"Pharmacist"},
        "bill" or "payment" or "adjustment"=>new[]{"Billing"},"prescription"=>new[]{"Doctor"},"note"=>new[]{"Doctor","Nurse"},
        "doctor" or "bed" or "user" or "user-status"=>Array.Empty<string>(),_=>null
    };
    if(permissions==null&&EnterpriseOperations.Commands.Contains(action))permissions=Access.ClinicalActions.Contains(action)?(action=="cancel-prescription"?new[]{"Doctor"}:new[]{"Doctor","Nurse"}):[];
    if(permissions==null)return Results.NotFound();
    if(!Access.Full(role)&&!permissions.Any((await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!)).Contains))return Results.Forbid();
    if(input.ValueKind!=JsonValueKind.Object)return Results.BadRequest(new{error="Expected a request object."});
    if(action=="user-status"&&input.TryGetProperty("id",out var u)&&u.GetString()==ctx.User.FindFirstValue(ClaimTypes.NameIdentifier))throw new RuleException("You cannot disable your own account.");
    // Do not persist a fast hash of user passwords in the idempotency ledger.
    var hashInput=input.GetRawText();
    var requestHash=store.RequestHash(hashInput);
    var reference=await store.Change(action,input,Context(ctx),ctx.Request.Headers["Idempotency-Key"],requestHash,app.Services.GetRequiredService<IDataProtectionProvider>());
    return Results.Ok(new{message="Saved successfully",reference});
}).RequireAuthorization();
 }
 static AuditContext Context(HttpContext c)=>new(c.User.Identity?.Name??"Anonymous",c.User.FindFirstValue(ClaimTypes.NameIdentifier),c.TraceIdentifier,c.Connection.RemoteIpAddress?.ToString(),c.Request.Method);
}
