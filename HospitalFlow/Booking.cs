using System.Security.Claims;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
sealed partial class Store {
    public bool TestPayments=>environment.IsDevelopment()&&config["Payments:Mode"]=="Test";
    public async Task<JsonElement> BookingQuery(string sql,params object[] args){
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();
        await using var cmd=new NpgsqlCommand(sql,c,tx);
        foreach(var arg in args)cmd.Parameters.AddWithValue(arg);
        var result=JsonSerializer.Deserialize<JsonElement>((string)(await cmd.ExecuteScalarAsync())!);await tx.CommitAsync();return result;
    }
    public async Task<JsonElement> BookingCommand(string action,JsonElement body,AuditContext audit){
        if(body.ValueKind!=JsonValueKind.Object)throw new RuleException("Expected booking details.");
        await using var c=await Open();await using var tx=await c.BeginTransactionAsync();
        await Sql(c,tx,"SELECT set_config('hospitalflow.correlation_id',$1,true)",audit.CorrelationId);
        await using var cmd=new NpgsqlCommand("SELECT hf_api.booking_command($1,$2,$3)::text",c,tx);cmd.Parameters.AddWithValue(action);cmd.Parameters.AddWithValue(NpgsqlDbType.Jsonb,body.GetRawText());cmd.Parameters.AddWithValue(TestPayments);
        try{var result=JsonSerializer.Deserialize<JsonElement>((string)(await cmd.ExecuteScalarAsync())!);await tx.CommitAsync();return result;}
        catch(PostgresException e) when(e.SqlState=="23514"&&e.ConstraintName==null){throw new RuleException(e.MessageText);}
    }
}
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
