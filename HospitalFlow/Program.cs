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

var appArgs=new List<string>();string? legacyPath=null;
for(var i=0;i<args.Length;i++) {if(args[i]=="--migrate")continue;if(args[i]=="--import-legacy"){legacyPath=args[++i];continue;}appArgs.Add(args[i]);}
var builder=WebApplication.CreateBuilder(appArgs.ToArray());
if(builder.Environment.IsDevelopment())builder.Configuration.AddJsonFile("appsettings.Local.json",optional:true,reloadOnChange:false);
builder.Configuration.AddEnvironmentVariables().AddCommandLine(appArgs.ToArray());
builder.WebHost.UseUrls(builder.Configuration["Urls"]??"http://localhost:5136");
builder.WebHost.ConfigureKestrel(o=>o.Limits.MaxRequestBodySize=64*1024);
builder.Services.AddSingleton<Store>();
builder.Services.AddHostedService<AccountMailWorker>();
builder.Services.AddHostedService<PatientSmsWorker>();
builder.Services.AddSingleton<DbKeyRepository>();
builder.Services.AddSingleton<DbTicketStore>();
var dp=builder.Services.AddDataProtection().SetApplicationName("HospitalFlow");
builder.Services.AddOptions<KeyManagementOptions>().Configure<DbKeyRepository>((o,r)=>o.XmlRepository=r);
var certPath=builder.Configuration["Security:KeyEncryptionCertificate"];
if(!string.IsNullOrEmpty(certPath))dp.ProtectKeysWithCertificate(X509CertificateLoader.LoadPkcs12FromFile(certPath,builder.Configuration["Security:KeyEncryptionCertificatePassword"]));
else if(builder.Environment.IsProduction()&&!args.Contains("--migrate"))throw new InvalidOperationException("Production requires Security:KeyEncryptionCertificate to encrypt database-held data-protection keys.");
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme).AddCookie(o=>{
    o.Cookie.Name="HospitalFlow.Session";o.Cookie.HttpOnly=true;o.Cookie.SameSite=SameSiteMode.Strict;
    o.Cookie.SecurePolicy=builder.Environment.IsDevelopment()?CookieSecurePolicy.SameAsRequest:CookieSecurePolicy.Always;
    o.ExpireTimeSpan=TimeSpan.FromHours(4);o.SlidingExpiration=true;
    o.Events.OnRedirectToLogin=c=>{c.Response.StatusCode=401;return Task.CompletedTask;};
    o.Events.OnRedirectToAccessDenied=c=>{c.Response.StatusCode=403;return Task.CompletedTask;};
    o.Events.OnValidatePrincipal=async c=>{
        var u=await c.HttpContext.RequestServices.GetRequiredService<Store>().UserById(c.Principal!.FindFirstValue(ClaimTypes.NameIdentifier)!);
        if(u is not {Active:true}||u.Role!=c.Principal!.FindFirstValue(ClaimTypes.Role)||(await c.HttpContext.RequestServices.GetRequiredService<Store>().PatientAccount(u.Id)) is {MustChangePassword:true}){c.RejectPrincipal();await c.HttpContext.SignOutAsync();}
    };
});
builder.Services.AddOptions<CookieAuthenticationOptions>(CookieAuthenticationDefaults.AuthenticationScheme).Configure<DbTicketStore>((o,s)=>o.SessionStore=s);
builder.Services.AddAuthorization();
var app=builder.Build();
var store=app.Services.GetRequiredService<Store>();
if(args.Contains("--migrate")) {
    await store.Migrate();
    await store.Bootstrap(legacyPath);
    Console.WriteLine("HospitalFlow relational migrations and initialization completed.");return;
}
if(builder.Environment.IsProduction()) {
    if(!Uri.TryCreate(builder.Configuration["Accounts:PublicOrigin"],UriKind.Absolute,out var origin)||origin.Scheme!="https"||origin.AbsolutePath!="/")throw new InvalidOperationException("Accounts:PublicOrigin requires the public HTTPS origin.");
    if(string.IsNullOrWhiteSpace(builder.Configuration["Mail:Smtp:Host"])||string.IsNullOrWhiteSpace(builder.Configuration["Mail:From"]))throw new InvalidOperationException("Production account recovery requires Mail:Smtp:Host and Mail:From.");
}
await store.Initialize();
await store.Log(new AuditContext("System",null,Guid.NewGuid().ToString("N"),null,null).Event("application-start","HospitalFlow"));
if(!app.Environment.IsDevelopment()){app.UseHsts();app.UseHttpsRedirection();}
app.Use(async(ctx,next)=>{
    ctx.Response.Headers["X-Content-Type-Options"]="nosniff";
    ctx.Response.Headers["Referrer-Policy"]="same-origin";
    ctx.Response.Headers["Content-Security-Policy"]="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";
    if(ctx.Request.Path.StartsWithSegments("/api"))ctx.Response.Headers.CacheControl="no-store";
    try{await next();}
    catch(RuleException e){ctx.Response.StatusCode=409;await ctx.Response.WriteAsJsonAsync(new{error=e.Message,correlationId=ctx.TraceIdentifier});}
    catch(PostgresException e) when(e.SqlState is "23505" or "23503" or "23514" or "23502" or "P0002" or "22P02" or "22007" or "22008" or "22003") {
        ctx.Response.StatusCode=409;await ctx.Response.WriteAsJsonAsync(new{error="This change conflicts with a database integrity rule. Refresh the records and try again.",correlationId=ctx.TraceIdentifier});
    }
    catch(PostgresException e) when(e.SqlState=="42501"){ctx.Response.StatusCode=403;await ctx.Response.WriteAsJsonAsync(new{error="This database operation is not permitted for your account.",correlationId=ctx.TraceIdentifier});}
    catch(Exception e) when(e is JsonException or BadHttpRequestException or FormatException){ctx.Response.StatusCode=400;await ctx.Response.WriteAsJsonAsync(new{error="Invalid request. Check the entered values.",correlationId=ctx.TraceIdentifier});}
    catch(Exception e){app.Logger.LogError(e,"Request failed: {CorrelationId}",ctx.TraceIdentifier);if(!ctx.Response.HasStarted){ctx.Response.StatusCode=503;await ctx.Response.WriteAsJsonAsync(new{error="The operation is unavailable. Please try again later.",correlationId=ctx.TraceIdentifier});}}
});
app.UseDefaultFiles();app.UseStaticFiles();app.UseRouting();app.UseAuthentication();
app.Use(async(ctx,next)=>{
    if(!ctx.Request.Path.StartsWithSegments("/api")){await next();return;}
    var audit=Context(ctx);var route=ctx.GetEndpoint()?.DisplayName?.Split(" => ")[0]??"Unknown API route";
    if(ctx.Request.RouteValues.TryGetValue("action",out var operation)&&operation is string name&&new[]{"patient","patient-update","appointment","appointment-status","admit","transfer","discharge","bed-status","medicine","stock","dispense","bill","payment","adjustment","prescription","note","doctor","bed","user","user-status"}.Contains(name))route+=" · "+name;
    // Durable start event prevents an unlogged patient-data read when audit storage is unavailable.
    await store.Log(audit.Event("request-start",route,"Started"));
    var status=500;
    try {
        if(HttpMethods.IsPost(ctx.Request.Method)&&ctx.Request.Headers["X-HospitalFlow"]!="1") {
            ctx.Response.StatusCode=400;await ctx.Response.WriteAsJsonAsync(new{error="Missing request verification header."});
        }else await next();
        status=ctx.Response.StatusCode;
    }catch(RuleException){status=409;throw;}catch(Exception e) when(e is JsonException or BadHttpRequestException or FormatException){status=400;throw;}
    catch(PostgresException e) when(e.SqlState is "23505" or "23503" or "23514" or "23502" or "P0002" or "22P02" or "22007" or "22008" or "22003"){status=409;throw;}
    catch(PostgresException e) when(e.SqlState=="42501"){status=403;throw;}
    catch{status=503;throw;}
    finally {
        try{await store.Log(Context(ctx).Event("request-complete",route,status<400?"Success":"Rejected",status));}
        catch(Exception e){app.Logger.LogCritical(e,"Could not record completion for {CorrelationId}; request-start is retained",ctx.TraceIdentifier);}
    }
});
app.UseAuthorization();
app.MapGet("/api/health",()=>new{status="ok",storage=store.Mode});
var loginHasher=new PasswordHasher<User>();var dummyUser=new User();var dummyHash=loginHasher.HashPassword(dummyUser,Convert.ToHexString(RandomNumberGenerator.GetBytes(32)));
app.MapPost("/api/login",async(Login input,HttpContext ctx)=>{
    var audit=Context(ctx);var key=ctx.Connection.RemoteIpAddress?.ToString()??"local";
    var accountKey="signin:"+store.RequestHash((input.Email??"").Trim().ToLowerInvariant());
    if(await store.IsBlocked(key)||await store.IsBlocked(accountKey)){await store.Log(audit.Event("login","Account sign-in","Rate limited",429));return Results.Json(new{error="Too many attempts. Try again in 15 minutes."},statusCode:429);}
    var valid=!string.IsNullOrWhiteSpace(input.Email)&&!string.IsNullOrEmpty(input.Password)&&input.Email.Length<=150&&input.Password.Length<=128;
    User? user=null;if(valid)try{user=await store.UserByLogin(input.Email!);}catch(RuleException){}
    var verified=loginHasher.VerifyHashedPassword(user??dummyUser,user?.PasswordHash??dummyHash,valid?input.Password:"");
    var patientAccess=user==null?null:await store.PatientAccount(user.Id);
    var success=user is {Active:true}&&verified!=PasswordVerificationResult.Failed&&!(patientAccess is {MustChangePassword:true}&&patientAccess.TemporaryExpiresAt<=DateTimeOffset.UtcNow);
    await store.LoginAttempt(key,success);await store.LoginAttempt(accountKey,success);
    if(!success){await store.Log(audit.Event("login","Account sign-in","Rejected",401));return Results.Json(new{error="Email or password is incorrect."},statusCode:401);}
    if(patientAccess is {MustChangePassword:true}) {
        await ctx.SignOutAsync();var challenge=await store.CreatePatientChallenge(user!.Id);await store.Log(audit.Event("patient-first-signin",patientAccess.PatientId,"Verification required"));
        return Results.Ok(new{requiresOnboarding=true,challenge,message="Verify your date of birth and set a new password to continue."});
    }
    var principal=new ClaimsPrincipal(new ClaimsIdentity(new[]{new Claim(ClaimTypes.NameIdentifier,user!.Id),new Claim(ClaimTypes.Name,user.Name),new Claim(ClaimTypes.Role,user.Role)},CookieAuthenticationDefaults.AuthenticationScheme));
    ctx.User=principal;await ctx.SignInAsync(principal);
    await store.Log(Context(ctx).Event("login",user.Id));return Results.Ok(new{user.Name,user.Role});
});
app.MapPost("/api/logout",async(HttpContext ctx)=>{await store.Log(Context(ctx).Event("logout",ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!));await ctx.SignOutAsync();return Results.Ok();}).RequireAuthorization();
app.MapGet("/api/me",async(HttpContext ctx)=>new{id=ctx.User.FindFirstValue(ClaimTypes.NameIdentifier),name=ctx.User.Identity!.Name,email=(await store.UserById(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!))?.Email,theme=await store.UserTheme(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!),role=ctx.User.FindFirstValue(ClaimTypes.Role),permissions=await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!),patientId=(await store.PatientAccount(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!))?.PatientId,storage=store.Mode,demoData=await store.DemoMode()}).RequireAuthorization();
app.MapGet("/api/state",async(HttpContext ctx)=>{
    var patientAccess=await store.PatientAccount(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    if(patientAccess!=null)return Results.Ok(await store.PatientState(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!));
    var emails=await store.PatientEmails();
    var s=await store.Current();var full=Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role));var grants=await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    bool Has(params string[] permissions)=>full||permissions.Any(grants.Contains);
    var operational=full||grants.Length>0;
    var patients=s.Patients.Where(_=>operational).Select(p=>new{p.Id,p.Name,p.Dob,p.Sex,Phone=Has("Reception","Doctor")?p.Phone:"Restricted",Email=emails.GetValueOrDefault(p.Id,""),p.Created});
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
        if(reference is not("patient-home" or "patient-appointments" or "patient-billing"))return Results.Forbid();
        await store.Log(Context(ctx).Event(action,reference!));return Results.Ok();
    }
    var allowed=new[]{"dashboard","patients","appointments","doctors","beds","admissions","clinical","pharmacy","billing","reports","alerts","admin","operations","bills"};
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
    var permissions=action switch {
        "patient" or "patient-update"=>new[]{"Reception","Doctor"},
        "appointment" or "appointment-status"=>new[]{"Reception"},
        "admit" or "transfer" or "discharge" or "bed-status"=>new[]{"Nurse"},
        "medicine" or "stock" or "dispense"=>new[]{"Pharmacist"},
        "bill" or "payment" or "adjustment"=>new[]{"Billing"},"prescription"=>new[]{"Doctor"},"note"=>new[]{"Doctor","Nurse"},
        "doctor" or "bed" or "user" or "user-status"=>Array.Empty<string>(),_=>null
    };
    if(permissions==null&&EnterpriseOperations.Commands.Contains(action))permissions=[];
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
AccountEndpoints.Map(app,store);
EnterpriseOperations.Map(app,store);
PatientEndpoints.Map(app,store);
app.Run();
static AuditContext Context(HttpContext c)=>new(c.User.Identity?.Name??"Anonymous",c.User.FindFirstValue(ClaimTypes.NameIdentifier),c.TraceIdentifier,c.Connection.RemoteIpAddress?.ToString(),c.Request.Method);
