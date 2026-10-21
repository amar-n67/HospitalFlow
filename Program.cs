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
builder.Services.AddHostedService<CareChargeWorker>();
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
        if(u is not {Active:true}||await c.HttpContext.RequestServices.GetRequiredService<Store>().StaffOnboardingExpiry(u.Id)!=null||u.Role!=c.Principal!.FindFirstValue(ClaimTypes.Role)||(await c.HttpContext.RequestServices.GetRequiredService<Store>().PatientAccount(u.Id)) is {MustChangePassword:true}){c.RejectPrincipal();await c.HttpContext.SignOutAsync();}
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
await ApplicationRelease.Register(store);
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
app.UseDefaultFiles();app.UseStaticFiles(new StaticFileOptions{OnPrepareResponse=ctx=>ctx.Context.Response.Headers.CacheControl="no-cache, must-revalidate"});app.UseRouting();app.UseAuthentication();
app.Use(async(ctx,next)=>{
 if(ctx.User.Identity?.IsAuthenticated==true){
  var selected=ctx.Request.Headers["X-HospitalFlow-Hospital"].FirstOrDefault();
  var scope=await store.ResolveHospital(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!,string.IsNullOrWhiteSpace(selected)?null:selected);
  if(scope==null){
   Store.SetHospitalContext(await store.ResolveHospital(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!,null));
   try{await store.Log(Context(ctx).Event("hospital-access-denied","Hospital workspace","Rejected",403));}finally{Store.SetHospitalContext(null);}
   ctx.Response.StatusCode=403;await ctx.Response.WriteAsJsonAsync(new{error="Hospital access is unavailable. Contact your network administrator.",code="HOSPITAL_ACCESS_DENIED"});return;
  }
  Store.SetHospitalContext(scope);
 }
 try{await next();}finally{Store.SetHospitalContext(null);}
});

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
ApplicationEndpoints.Map(app,store);
AccountEndpoints.Map(app,store);
EnterpriseOperations.Map(app,store);
PatientEndpoints.Map(app,store);
PeopleEndpoints.Map(app,store);
WorkspaceEndpoints.Map(app,store);
RecordDocumentEndpoints.Map(app,store);
HospitalNetworkEndpoints.Map(app,store);
BookingEndpoints.Map(app,store);
MedicationCareEndpoints.Map(app,store);
CareFlowEndpoints.Map(app,store);
EnterpriseFinanceEndpoints.Map(app,store);
app.Run();
static AuditContext Context(HttpContext c)=>new(c.User.Identity?.Name??"Anonymous",c.User.FindFirstValue(ClaimTypes.NameIdentifier),c.TraceIdentifier,c.Connection.RemoteIpAddress?.ToString(),c.Request.Method);
