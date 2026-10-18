using System.Text.Json;
using System.Security.Claims;
static class PatientEndpoints {
    public static void Map(WebApplication app,Store store) {
        app.MapPost("/api/patient/invitation",async(JsonElement body,HttpContext ctx)=>{
            var full=Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role));var permissions=await store.Permissions(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            if(!full&&!permissions.Any(p=>p is "Reception" or "Doctor"))return Results.Forbid();
            if(!body.TryGetProperty("patientId",out var value)||value.ValueKind!=JsonValueKind.String)return Results.BadRequest();
            await store.ReissuePatientInvitation(value.GetString()!,new(ctx.User.Identity!.Name!,ctx.User.FindFirstValue(ClaimTypes.NameIdentifier),ctx.TraceIdentifier,ctx.Connection.RemoteIpAddress?.ToString(),ctx.Request.Method),app.Services.GetRequiredService<Microsoft.AspNetCore.DataProtection.IDataProtectionProvider>());return Results.Ok(new{message="A new temporary invitation has been queued. Previous temporary credentials are invalid."});
        }).RequireAuthorization();
        app.MapPost("/api/account/theme",async(JsonElement body,HttpContext ctx)=>{
            if(!body.TryGetProperty("theme",out var value)||value.ValueKind!=JsonValueKind.String)return Results.BadRequest();
            await store.SaveTheme(value.GetString()!,new(ctx.User.Identity!.Name!,ctx.User.FindFirstValue(ClaimTypes.NameIdentifier),ctx.TraceIdentifier,ctx.Connection.RemoteIpAddress?.ToString(),ctx.Request.Method));return Results.Ok();
        }).RequireAuthorization();
        app.MapPost("/api/patient/onboarding",async(JsonElement body,HttpContext ctx)=>{
            var key="patient-onboarding:"+(ctx.Connection.RemoteIpAddress?.ToString()??"local");if(await store.IsBlocked(key))return Results.Json(new{error="Too many attempts. Try again in 15 minutes."},statusCode:429);
            await store.LoginAttempt(key,false);
            string Text(string field)=>body.ValueKind==JsonValueKind.Object&&body.TryGetProperty(field,out var value)&&value.ValueKind==JsonValueKind.String?value.GetString()!:throw new RuleException("Complete all verification and password fields.");
            await store.CompletePatientOnboarding(Text("challenge"),Text("dob"),Text("password"),new("Patient onboarding",null,ctx.TraceIdentifier,ctx.Connection.RemoteIpAddress?.ToString(),ctx.Request.Method));
            await store.LoginAttempt(key,true);return Results.Ok(new{message="Identity verified and password changed. Sign in with your email or patient ID and new password."});
        });
    }
}
