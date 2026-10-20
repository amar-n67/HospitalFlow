using System.Security.Claims;
using System.Text.Json;
using Npgsql;
static class MedicationCareEndpoints {
 public static void Map(WebApplication app,Store store){
  app.MapGet("/api/care/medications",async()=>{await using var c=await store.Open();await using var cmd=new NpgsqlCommand("SELECT hf_api.medication_care()::text",c);return Results.Content((string)(await cmd.ExecuteScalarAsync())!,"application/json");}).RequireAuthorization();
  app.MapPost("/api/care/prescribe-visit",async(JsonElement body,HttpContext ctx)=>{
   if(ctx.User.FindFirstValue(ClaimTypes.Role) is not ("Doctor" or "Developer"))return Results.Forbid();
   if(!body.TryGetProperty("appointmentId",out var appointment)||appointment.ValueKind!=JsonValueKind.String||!Guid.TryParse(ctx.Request.Headers["Idempotency-Key"],out var key))throw new RuleException("Select an appointment and retry key.");
   await using var c=await store.Open();await using var tx=await c.BeginTransactionAsync();
   await Store.Sql(c,tx,"SELECT set_config('hospitalflow.correlation_id',$1,true)",ctx.TraceIdentifier);
   await using var cmd=new NpgsqlCommand("SELECT hf_api.prescribe_visit($1,$2::jsonb,$3,$4)",c,tx);cmd.Parameters.AddWithValue(appointment.GetString()!);cmd.Parameters.AddWithValue(body.GetRawText());cmd.Parameters.AddWithValue(key);cmd.Parameters.AddWithValue(store.RequestHash(body.GetRawText()));var reference=(string)(await cmd.ExecuteScalarAsync())!;await tx.CommitAsync();return Results.Ok(new{reference});
  }).RequireAuthorization();
  app.MapPost("/api/care/medications/provide",async(JsonElement body,HttpContext ctx)=>{
   if(ctx.User.FindFirstValue(ClaimTypes.Role) is not ("Nurse" or "Developer"))return Results.Forbid();
   if(!body.TryGetProperty("prescriptionId",out var rx)||rx.ValueKind!=JsonValueKind.String||!body.TryGetProperty("quantity",out var q)||q.ValueKind!=JsonValueKind.Number||!q.TryGetInt32(out var quantity)||!body.TryGetProperty("note",out var note)||note.ValueKind!=JsonValueKind.String||!Guid.TryParse(ctx.Request.Headers["Idempotency-Key"],out var key))throw new RuleException("Prescription, whole quantity, note and retry key are required.");
   await using var c=await store.Open();await using var tx=await c.BeginTransactionAsync();
   await using var cmd=new NpgsqlCommand("SELECT hf_api.provide_medication($1,$2,$3,$4)::text",c,tx);cmd.Parameters.AddWithValue(rx.GetString()!);cmd.Parameters.AddWithValue(quantity);cmd.Parameters.AddWithValue(note.GetString()!);cmd.Parameters.AddWithValue(key);var id=(string)(await cmd.ExecuteScalarAsync())!;
   var audit=new AuditContext(ctx.User.Identity?.Name??"Nurse",ctx.User.FindFirstValue(ClaimTypes.NameIdentifier),ctx.TraceIdentifier,ctx.Connection.RemoteIpAddress?.ToString(),ctx.Request.Method);
   await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("medication-provided",id)],[]);
   await tx.CommitAsync();return Results.Ok(new{reference=id});
  }).RequireAuthorization();
 }
}
