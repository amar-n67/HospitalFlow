using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Npgsql;
static class PeopleEndpoints{
    public static void Map(WebApplication app,Store store){
        app.MapGet("/api/people",async(HttpContext ctx)=>{
            var role=ctx.User.FindFirstValue(ClaimTypes.Role)!;if(!Access.Full(role)&&role!="Doctor"&&!(await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!)).Contains("Doctor"))return Results.Forbid();
            // Legacy Doctor grants receive the same constrained directory as a Doctor role.
            return Results.Ok(await store.People(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!,Access.Full(role)?role:"Doctor"));
        }).RequireAuthorization();
        app.MapPost("/api/people/{operation}",async(string operation,JsonElement body,HttpContext ctx)=>{
            if(operation is not("register" or "update"))return Results.NotFound();
            var role=ctx.User.FindFirstValue(ClaimTypes.Role)!;if(!Access.Full(role)&&!(await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!)).Contains("Doctor"))return Results.Forbid();
            if(!Access.Full(role)&&body.TryGetProperty("role",out var requested)&&requested.ValueKind==JsonValueKind.String&&(requested.GetString() is "Admin" or "Developer"))return Results.Forbid();
            var id=await store.SavePerson(body,new(ctx.User.Identity!.Name!,ctx.User.FindFirstValue(ClaimTypes.NameIdentifier),ctx.TraceIdentifier,ctx.Connection.RemoteIpAddress?.ToString(),ctx.Request.Method),ctx.Request.Headers["Idempotency-Key"].ToString(),operation=="update");return Results.Ok(new{reference=id,message="Person saved."});
        }).RequireAuthorization();
    }
}
