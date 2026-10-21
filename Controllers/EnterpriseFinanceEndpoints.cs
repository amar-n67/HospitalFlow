using System.Security.Claims;
using System.Text.Json;
using Npgsql;
static class EnterpriseFinanceEndpoints {
 public static void Map(WebApplication app,Store store){
  app.MapGet("/api/finance",async()=>{await store.BookingQuery("SELECT '{}'::text FROM (SELECT hf_api.refresh_finance_charges()) refreshed");return Results.Ok(new{data=await store.BookingQuery("SELECT hf_api.finance_state()::text"),paymentMode=store.TestPayments?"Test":"Disabled"});}).RequireAuthorization();
  app.MapGet("/api/calendar/{year:int}",async(int year)=>Results.Ok(await store.BookingQuery("SELECT hf_api.year_calendar($1)::text",year))).RequireAuthorization();
  app.MapGet("/api/admin/versions",async(HttpContext ctx)=>{
   if(!Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role)))return Results.Forbid();
   return Results.Ok(new{current=ApplicationRelease.CurrentVersion,commit=ApplicationRelease.Commit,workingTree=ApplicationRelease.WorkingTree,releases=await store.BookingQuery("SELECT COALESCE(jsonb_agg(r ORDER BY installed_at DESC),'[]'::jsonb)::text FROM hospitalflow.application_releases r")});
  }).RequireAuthorization();
  app.MapPost("/api/enterprise/{action}",async(string action,JsonElement body,HttpContext ctx)=>{
   if(body.ValueKind!=JsonValueKind.Object||!Guid.TryParse(ctx.Request.Headers["Idempotency-Key"],out var key))throw new RuleException("Enter the details with a valid retry key.");
   await using var c=await store.Open();await using var tx=await c.BeginTransactionAsync();await Store.Sql(c,tx,"SELECT set_config('hospitalflow.correlation_id',$1,true)",ctx.TraceIdentifier);
   await using var cmd=new NpgsqlCommand("SELECT hf_api.enterprise_command($1,$2::jsonb,$3,$4,$5)",c,tx);cmd.Parameters.AddWithValue(action);cmd.Parameters.AddWithValue(body.GetRawText());cmd.Parameters.AddWithValue(key);cmd.Parameters.AddWithValue(store.RequestHash(action+body.GetRawText()));cmd.Parameters.AddWithValue(store.TestPayments);
   try{var reference=(string)(await cmd.ExecuteScalarAsync())!;await tx.CommitAsync();return Results.Ok(new{reference});}
   catch(PostgresException e) when(e.SqlState=="23514"&&e.ConstraintName==null&&e.TableName==null){throw new RuleException(e.MessageText);}
  }).RequireAuthorization();
 }
}
