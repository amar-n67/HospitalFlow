using System.Security.Claims;
using Npgsql;

static class EnterpriseOperations {
    public static readonly string[] Commands=["patient-contact","patient-consent","revoke-consent","supplier","purchase-order","approve-purchase-order","receive-purchase-order","hold-batch","release-batch","reserve-prescription","release-reservation","stock-adjustment","service","service-price","service-charge","reverse-payment","provider-session","provider-absence","cancel-absence","grant-patient-access","staff-member","grant-department","ward-department","hospital-profile","discharge-task","complete-discharge-task","follow-up","book-follow-up","clinical-order","clinical-order-status","complete-clinical-order","cancel-prescription","notification-ack"];
    static readonly string[] Tables=["suppliers","purchase_orders","purchase_order_lines","goods_receipts","medicine_batch_holds","stock_reservations","service_catalog","service_prices","payments","payment_reversals","provider_sessions","provider_absences","patient_contacts","patient_consents","patient_access_grants","staff_members","user_departments","discharge_tasks","follow_ups","clinical_orders","encounters","hospital_profile","departments","wards","notifications"];
    public static void Map(WebApplication app,Store store) {
        app.MapGet("/api/clinical/operations",async(HttpContext ctx)=>{
            var id=ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!;var grants=await store.Permissions(id);if(!Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role))&&!grants.Any(p=>p is "Doctor" or "Nurse"))return Results.Forbid();
            var records=new Dictionary<string,System.Text.Json.JsonElement>();await using var c=await store.Open();
            foreach(var table in new[]{"encounters","clinical_orders","follow_ups","service_catalog"}){var scope=table=="encounters"?" WHERE hf_security.can_access_patient(patient_id)":"";await using var cmd=new NpgsqlCommand($"SELECT COALESCE(jsonb_agg(r),'[]'::jsonb)::text FROM(SELECT * FROM hospitalflow.{table}{scope} ORDER BY 1 LIMIT 200)r",c);records[table]=System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>((string)(await cmd.ExecuteScalarAsync())!);}
            return Results.Ok(records);
        }).RequireAuthorization();
        app.MapGet("/api/admin/operations",async(HttpContext ctx)=>{
            if(!Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role)))return Results.Forbid();
            var records=new Dictionary<string,System.Text.Json.JsonElement>();await using var c=await store.Open();await using var tx=await c.BeginTransactionAsync(System.Data.IsolationLevel.RepeatableRead);
            await Store.Sql(c,tx,"SELECT set_config('hospitalflow.actor_id',$1,true)",ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            foreach(var table in Tables) {
                // Identifiers come exclusively from the fixed list above. Never accept a table name from a request.
                await using var cmd=new NpgsqlCommand($"SELECT COALESCE(jsonb_agg(r),'[]'::jsonb)::text FROM (SELECT * FROM hospitalflow.{table} ORDER BY 1 LIMIT 200) r",c,tx);
                records[table]=System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>((string)(await cmd.ExecuteScalarAsync())!);
            }
            await tx.CommitAsync();return Results.Ok(records);
        }).RequireAuthorization();
    }
}
