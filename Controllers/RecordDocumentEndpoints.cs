using System.Net;
using System.Security.Claims;
using System.Globalization;
using Npgsql;
static class RecordDocumentEndpoints {
    public static void Map(WebApplication app,Store store){
        app.MapGet("/api/documents/{kind}/{id}",async(string kind,string id,string? mode,HttpContext ctx)=>{
            if(kind is not("appointment" or "prescription" or "invoice" or "admission" or "discharge-summary")||id.Length>100)return Results.NotFound();
            if(mode is not("print" or "download" or "pdf"))return Results.BadRequest();
            var userId=ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)!;var patient=await store.PatientAccount(userId)!=null;
            if(!patient&&!Access.Full(ctx.User.FindFirstValue(ClaimTypes.Role))){
                var grants=await store.Permissions(userId);var allowed=kind switch{"appointment"=>new[]{"Reception","Doctor","Nurse"},"prescription"=>new[]{"Doctor","Nurse","Pharmacist"},"invoice"=>new[]{"Reception","Billing","Pharmacist","Doctor","Nurse"},_=>new[]{"Doctor","Nurse"}};
                if(!allowed.Any(grants.Contains))return Results.Forbid();
                if(kind=="invoice"){await using var c=await store.Open();await using var cmd=new NpgsqlCommand("SELECT hf_security.can_read_invoice($1)",c);cmd.Parameters.AddWithValue(id);if(!(bool)(await cmd.ExecuteScalarAsync())!)return Results.Forbid();}
            }
            var copy=await store.RecordDocument(kind,id,userId,patient);if(copy==null)return Results.NotFound();
            await store.Log(new AuditContext(ctx.User.Identity!.Name!,userId,ctx.TraceIdentifier,ctx.Connection.RemoteIpAddress?.ToString(),ctx.Request.Method).Event("document-"+mode,kind+":"+id));
            return Results.Ok(copy);
        }).RequireAuthorization();
    }
}
