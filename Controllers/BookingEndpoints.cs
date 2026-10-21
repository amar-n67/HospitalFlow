using System.Security.Claims;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
static class BookingEndpoints {
 public static void Map(WebApplication app,Store store){
  app.MapGet("/api/booking",async()=>{return Results.Ok(new{data=await store.BookingQuery("SELECT hf_api.booking_state()::text"),paymentMode=store.TestPayments?"Test":"Disabled"});}).RequireAuthorization();
  app.MapGet("/api/leave/calendar",async()=>{return Results.Ok(await store.BookingQuery("SELECT hf_api.hospital_leave_calendar()::text"));}).RequireAuthorization();
  app.MapGet("/api/booking/slots",async(string doctorId,DateOnly day,string? exclude)=>{return Results.Ok(await store.BookingQuery("SELECT hf_api.booking_slots($1,$2,$3)::text",doctorId,day,exclude??""));}).RequireAuthorization();
  app.MapPost("/api/booking/hospital",async(JsonElement body,HttpContext ctx)=>{
   if(body.ValueKind!=JsonValueKind.Object||!body.TryGetProperty("hospitalId",out var selected)||selected.ValueKind!=JsonValueKind.String)throw new RuleException("Choose a hospital.");var hospital=selected.GetString();if(string.IsNullOrWhiteSpace(hospital)||hospital.Length>100)throw new RuleException("Choose a hospital.");
   await store.BookingQuery("SELECT '{}'::text FROM (SELECT hf_api.select_booking_hospital($1)) selected",hospital);
   var audit=new AuditContext(ctx.User.Identity!.Name!,ctx.User.FindFirstValue(ClaimTypes.NameIdentifier),ctx.TraceIdentifier,ctx.Connection.RemoteIpAddress?.ToString(),ctx.Request.Method);
   await store.SelectHospital(hospital,audit);return Results.Ok();
  }).RequireAuthorization();
  app.MapPost("/api/booking/{action}",async(string action,JsonElement body,HttpContext ctx)=>{
   var audit=new AuditContext(ctx.User.Identity!.Name!,ctx.User.FindFirstValue(ClaimTypes.NameIdentifier),ctx.TraceIdentifier,ctx.Connection.RemoteIpAddress?.ToString(),ctx.Request.Method);
   return Results.Ok(await store.BookingCommand(action,body,audit));
  }).RequireAuthorization();
 }
}
