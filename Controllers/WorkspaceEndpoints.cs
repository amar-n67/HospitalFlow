using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.DataProtection;
using Npgsql;

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
