using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Npgsql;
static class HospitalNetworkEndpoints {
    public static void Map(WebApplication app,Store store){
        AuditContext Audit(HttpContext c)=>new(c.User.Identity!.Name!,c.User.FindFirstValue(ClaimTypes.NameIdentifier),c.TraceIdentifier,c.Connection.RemoteIpAddress?.ToString(),c.Request.Method);
        app.MapGet("/api/network/workspaces",async(HttpContext c)=>{return Results.Ok(await store.NetworkState(c.User.FindFirstValue(ClaimTypes.NameIdentifier)!));}).RequireAuthorization();
        app.MapGet("/api/network",async(HttpContext c)=>{if(c.User.FindFirstValue(ClaimTypes.Role)=="Nurse")return Results.Forbid();return Results.Ok(await store.NetworkState(c.User.FindFirstValue(ClaimTypes.NameIdentifier)!));}).RequireAuthorization();
        app.MapPost("/api/network/hospitals",async(JsonElement b,HttpContext c)=>{if(!await store.NetworkOperator(c.User.FindFirstValue(ClaimTypes.NameIdentifier)!))return Results.Forbid();await store.SaveHospital(b,Audit(c));return Results.Ok();}).RequireAuthorization();
        app.MapPost("/api/network/select",async(JsonElement b,HttpContext c)=>{await store.SelectHospital(b.GetProperty("hospitalId").GetString()!,Audit(c));return Results.Ok();}).RequireAuthorization();
        app.MapGet("/api/network/access",async(HttpContext c)=>{if(!await store.NetworkOperator(c.User.FindFirstValue(ClaimTypes.NameIdentifier)!))return Results.Forbid();return Results.Ok(await store.NetworkAccounts());}).RequireAuthorization();
        app.MapPost("/api/network/access",async(JsonElement b,HttpContext c)=>{if(!await store.NetworkOperator(c.User.FindFirstValue(ClaimTypes.NameIdentifier)!))return Results.Forbid();await store.GrantHospital(b,Audit(c));return Results.Ok();}).RequireAuthorization();
        app.MapPost("/api/network/referrals",async(JsonElement b,HttpContext c)=>{var role=c.User.FindFirstValue(ClaimTypes.Role)!;if(!Access.Full(role)&&!(await store.Permissions(c.User.FindFirstValue(ClaimTypes.NameIdentifier)!)).Contains("Doctor"))return Results.Forbid();var id=await store.ReferPatient(b,Audit(c),c.Request.Headers["Idempotency-Key"].ToString());return Results.Ok(new{reference=id});}).RequireAuthorization();
        app.MapPost("/api/network/referrals/resolve",async(JsonElement b,HttpContext c)=>{var role=c.User.FindFirstValue(ClaimTypes.Role)!;if(!Access.Full(role)&&!(await store.Permissions(c.User.FindFirstValue(ClaimTypes.NameIdentifier)!)).Contains("Doctor"))return Results.Forbid();await store.ResolveReferral(b,Audit(c));return Results.Ok();}).RequireAuthorization();
        app.MapGet("/api/network/patients/{id}/history",async(string id,HttpContext c)=>{var result=await store.PatientHospitalHistory(id,c.User.FindFirstValue(ClaimTypes.NameIdentifier)!,c.User.FindFirstValue(ClaimTypes.Role)!);await store.Log(Audit(c).Event("patient-history-view",id));return Results.Ok(result);}).RequireAuthorization();
    }
}
