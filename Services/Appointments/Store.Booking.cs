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
