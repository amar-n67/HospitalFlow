using System.Net;
using System.Security.Claims;
using System.Globalization;
using Npgsql;
static class RecordDocumentEndpoints {
    public static void Map(WebApplication app,Store store){
        app.MapGet("/api/documents/{kind}/{id}",async(string kind,string id,string? mode,HttpContext ctx)=>{
            if(kind is not("appointment" or "prescription" or "invoice" or "admission" or "discharge-summary")||id.Length>100)return Results.NotFound();
            if(mode is not("print" or "download"))return Results.BadRequest();
            var userId=ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!;var patient=await store.PatientAccount(userId)!=null;
            if(!patient&&!Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role))){
                var grants=await store.Permissions(userId);var allowed=kind switch{"appointment"=>new[]{"Reception","Doctor","Nurse"},"prescription"=>new[]{"Doctor","Nurse","Pharmacist"},"invoice"=>new[]{"Billing","Pharmacist"},_=>new[]{"Doctor","Nurse"}};
                if(!allowed.Any(grants.Contains))return Results.Forbid();
                if(kind=="invoice"&&!grants.Contains("Billing")){await using var c=await store.Open();await using var cmd=new NpgsqlCommand("SELECT EXISTS(SELECT 1 FROM hospitalflow.prescription_dispensations WHERE bill_id=$1 AND hospital_id=hf_security.current_hospital())",c);cmd.Parameters.AddWithValue(id);if(!(bool)(await cmd.ExecuteScalarAsync())!)return Results.Forbid();}
            }
            var copy=await store.RecordDocument(kind,id,userId,patient);if(copy==null)return Results.NotFound();
            await store.Log(new AuditContext(ctx.User.Identity!.Name!,userId,ctx.TraceIdentifier,ctx.Connection.RemoteIpAddress?.ToString(),ctx.Request.Method).Event("document-"+mode,kind+":"+id));
            return Results.Ok(copy);
        }).RequireAuthorization();
    }
}
