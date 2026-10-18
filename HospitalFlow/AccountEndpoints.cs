using System.Security.Claims;
using Microsoft.AspNetCore.DataProtection;
using System.Text.Json;

static class AccountEndpoints {
    public static void Map(WebApplication app,Store store) {
        var protector=app.Services.GetRequiredService<IDataProtectionProvider>().CreateProtector("HospitalFlow.AccountMail.v1");
        static AuditContext Audit(HttpContext c)=>new(c.User.Identity?.Name??"Anonymous",c.User.FindFirstValue(ClaimTypes.NameIdentifier),c.TraceIdentifier,c.Connection.RemoteIpAddress?.ToString(),c.Request.Method);
        static string Text(JsonElement body,string key)=>body.ValueKind==JsonValueKind.Object&&body.TryGetProperty(key,out var value)&&value.ValueKind==JsonValueKind.String?value.GetString()!:throw new RuleException("Check the required account fields.");
        async Task<bool> Throttled(HttpContext c,string operation) {
            var key="account:"+operation+":"+(c.Connection.RemoteIpAddress?.ToString()??"local");if(await store.IsBlocked(key))return true;await store.LoginAttempt(key,false);return false;
        }
        app.MapPost("/api/signup",async(JsonElement body,HttpContext ctx)=>{
            if(await Throttled(ctx,"signup"))return Results.Json(new{error="Too many requests. Try again in 15 minutes."},statusCode:429);
            await store.Register(Text(body,"name"),Text(body,"email"),Text(body,"password"),Audit(ctx),protector);
            return Results.Ok(new{message="If this address is eligible, a verification link will be sent. After verification, an administrator must approve your account."});
        });
        foreach(var route in new[]{"forgot-password","resend-verification"}) {
            var purpose=route=="forgot-password"?"reset":"verify";
            app.MapPost("/api/"+route,async(JsonElement body,HttpContext ctx)=>{
                if(await Throttled(ctx,"links"))return Results.Json(new{error="Too many requests. Try again in 15 minutes."},statusCode:429);
                await store.RequestToken(Text(body,"email"),purpose,Audit(ctx),protector);
                return Results.Ok(new{message="If this address is eligible, an email will arrive with the next steps."});
            });
        }
        app.MapPost("/api/verify-email",async(JsonElement body,HttpContext ctx)=>{
            if(await Throttled(ctx,"tokens"))return Results.StatusCode(429);
            await store.ConsumeToken(Text(body,"token"),"verify",null,Audit(ctx));return Results.Ok(new{message="Email verified. An administrator must now approve your account and assign access."});
        });
        app.MapPost("/api/reset-password",async(JsonElement body,HttpContext ctx)=>{
            if(await Throttled(ctx,"tokens"))return Results.StatusCode(429);
            await store.ConsumeToken(Text(body,"token"),"reset",Text(body,"password"),Audit(ctx));return Results.Ok(new{message="Password reset. Sign in with your new password."});
        });
        app.MapPost("/api/admin/account",async(JsonElement body,HttpContext ctx)=>{
            if(!Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role)))return Results.Forbid();
            if(body.ValueKind!=JsonValueKind.Object||!body.TryGetProperty("active",out var status)||status.ValueKind is not (JsonValueKind.True or JsonValueKind.False)||!body.TryGetProperty("permissions",out var grants)||grants.ValueKind!=JsonValueKind.Array||grants.EnumerateArray().Any(x=>x.ValueKind!=JsonValueKind.String))return Results.BadRequest(new{error="Provide account status and a permission list."});
            var active=status.GetBoolean();var permissions=grants.Deserialize<string[]>()??[];
            await store.ManageAccount(new(Text(body,"id"),"","",Text(body,"role"),active,false,permissions),Audit(ctx));return Results.Ok(new{message="Account access updated. Existing sessions have been revoked."});
        }).RequireAuthorization();
        app.MapGet("/api/admin/health",async(HttpContext ctx)=>{
            if(!Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role)))return Results.Forbid();
            await using var c=await store.Open();await using var cmd=new Npgsql.NpgsqlCommand("SELECT jsonb_build_object('checks',(SELECT jsonb_agg(v) FROM hf_ops.validate_database() v),'mail',(SELECT jsonb_build_object('pending',count(*) FILTER(WHERE status='Pending'),'failed',count(*) FILTER(WHERE status='Failed')) FROM hospitalflow.account_mail))::text",c);
            return Results.Text((string)(await cmd.ExecuteScalarAsync())!,"application/json");
        }).RequireAuthorization();
    }
}
