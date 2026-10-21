using System.Security.Claims;
using System.Text.Json;
using Npgsql;
static class CareFlowEndpoints {
 public static void Map(WebApplication app,Store store){
 app.MapGet("/api/care/flow",async(HttpContext ctx)=>{
  await using var c=await store.Open();await using var tx=await c.BeginTransactionAsync(System.Data.IsolationLevel.RepeatableRead);
  await using var permission=new NpgsqlCommand("SELECT hf_security.care_role(ARRAY['Admin','Doctor','Nurse']),hf_security.care_role(ARRAY['Billing','Pharmacist']),COALESCE(hf_security.own_patient(COALESCE(current_setting('hospitalflow.patient_id',true),'')),false)",c,tx);bool clinical,financial,patient;await using(var r=await permission.ExecuteReaderAsync()){await r.ReadAsync();clinical=r.GetBoolean(0);financial=r.GetBoolean(1);patient=r.GetBoolean(2);}
  financial=financial&&!clinical&&!patient;
  if(!clinical&&!financial&&!patient)return Results.Forbid();
  var records=new Dictionary<string,JsonElement>();
  var queries=new Dictionary<string,string>{
   ["plans"]=$"SELECT {(clinical||patient?"to_jsonb(p)":"to_jsonb(p)-ARRAY['diagnosis','instructions','nursing_notes']")}||jsonb_build_object('doctor_name',d.name,'nurse_name',n.name) item FROM hospitalflow.care_plans p JOIN hospitalflow.users d ON d.id=p.doctor_id LEFT JOIN hospitalflow.users n ON n.id=p.nurse_id WHERE p.hospital_id=hf_security.current_hospital() AND ({(financial?"true":"hf_security.can_read_care(p.patient_id)")})",
   ["admissions"]="SELECT jsonb_array_elements(hf_api.care_stays()) item",
   ["beds"]=clinical?"SELECT to_jsonb(b) item FROM hospitalflow.beds b WHERE b.hospital_id=hf_security.current_hospital()":"SELECT '{}'::jsonb item WHERE false",
   ["patients"]=$"SELECT jsonb_build_object('id',p.id,'name',p.name,'code',p.registration_id) item FROM hospitalflow.patients p WHERE hf_security.enrolled_patient(p.id) AND ({(financial?"true":"hf_security.can_read_care(p.id)")})",
   ["staff"]="SELECT jsonb_build_object('id',u.id,'name',u.name,'role',u.role,'code',u.registration_id) item FROM hospitalflow.users u JOIN hospitalflow.hospital_memberships m ON m.user_id=u.id WHERE m.hospital_id=hf_security.current_hospital() AND m.active AND u.active AND u.role IN ('Doctor','Nurse','Developer')",
   ["encounters"]=clinical||patient?"SELECT to_jsonb(e) item FROM hospitalflow.encounters e WHERE e.hospital_id=hf_security.current_hospital() AND hf_security.can_read_care(e.patient_id)":"SELECT '{}'::jsonb item WHERE false",
   ["services"]="SELECT to_jsonb(s) item FROM hospitalflow.service_catalog s WHERE s.hospital_id=hf_security.current_hospital() AND s.active",
   ["orders"]=clinical||patient?"SELECT jsonb_array_elements(hf_api.care_lab_orders()) item":"SELECT '{}'::jsonb item WHERE false",
   ["rates"]="SELECT to_jsonb(r) item FROM hospitalflow.care_rates r WHERE r.hospital_id=hf_security.current_hospital()",
   ["observations"]=clinical||patient?"SELECT to_jsonb(r)||jsonb_build_object('nurse_name',u.name) item FROM hospitalflow.care_observations r JOIN hospitalflow.users u ON u.id=r.recorded_by WHERE r.hospital_id=hf_security.current_hospital() AND hf_security.can_read_care(r.patient_id)":"SELECT '{}'::jsonb item WHERE false",
   ["doses"]=clinical||patient?"SELECT to_jsonb(r)||jsonb_build_object('recorded_name',u.name) item FROM hospitalflow.medication_doses r LEFT JOIN hospitalflow.users u ON u.id=r.recorded_by WHERE r.hospital_id=hf_security.current_hospital() AND hf_security.can_read_care(r.patient_id)":"SELECT '{}'::jsonb item WHERE false",
   ["discharges"]=clinical||patient?"SELECT to_jsonb(r)||jsonb_build_object('doctor_name',d.name,'nurse_name',n.name) item FROM hospitalflow.care_discharge_reviews r JOIN hospitalflow.users n ON n.id=r.nurse_id LEFT JOIN hospitalflow.users d ON d.id=r.doctor_id WHERE r.hospital_id=hf_security.current_hospital() AND hf_security.can_read_care(r.patient_id)":"SELECT '{}'::jsonb item WHERE false",
   ["pharmacyRequests"]=$"SELECT to_jsonb(r)||jsonb_build_object('requested_name',u.name) item FROM hospitalflow.pharmacy_requests r JOIN hospitalflow.users u ON u.id=r.requested_by WHERE r.hospital_id=hf_security.current_hospital() AND ({(financial?"true":"hf_security.can_read_care(r.patient_id)")})",
   ["events"]=$"SELECT (to_jsonb(r)-'details'){(financial?"||jsonb_build_object('comments',CASE WHEN r.activity IN ('Ward / bed assignment','Discharged') THEN 'Hospital stay updated' ELSE r.comments END)":"")} item FROM hospitalflow.care_events r WHERE r.hospital_id=hf_security.current_hospital() AND ({(financial?"r.activity IN ('Medicine issued','Daily charge','Ward / bed assignment','Discharged','Send Pharmacy')":"hf_security.can_read_care(r.patient_id)")}) ORDER BY r.at DESC,r.id",
   ["charges"]=$"SELECT jsonb_build_object('id',l.id,'patient_id',b.patient_id,'invoice',b.id,'day',COALESCE(e.charge_day,(l.created_at AT TIME ZONE 'Asia/Kolkata')::date),'category',COALESCE(e.category,xc.category,hf_api.care_line_category(l.id),CASE WHEN x.medicine_id IS NOT NULL THEN 'Pharmacy' ELSE 'Other' END),'description',l.description,'amount',l.amount) item FROM hospitalflow.bill_lines l JOIN hospitalflow.bills b ON b.id=l.bill_id LEFT JOIN hospitalflow.care_charge_entries e ON e.line_id=l.id LEFT JOIN hospitalflow.care_extra_categories xc ON xc.line_id=l.id LEFT JOIN hospitalflow.invoice_line_context x ON x.line_id=l.id WHERE b.hospital_id=hf_security.current_hospital() AND ({(financial?"true":"hf_security.can_read_care(b.patient_id)")}) UNION ALL SELECT jsonb_build_object('id',b.id,'patient_id',b.patient_id,'invoice',b.appointment_id,'day',(b.paid_at AT TIME ZONE 'Asia/Kolkata')::date,'category','Consultation booking','description',b.visit_type||' · '||b.payment_mode,'amount',CASE WHEN b.state='Refunded' THEN 0 ELSE b.amount END) item FROM hospitalflow.appointment_bookings b WHERE b.hospital_id=hf_security.current_hospital() AND b.paid_at IS NOT NULL AND ({(financial?"true":"hf_security.can_read_care(b.patient_id)")})"
  };
  foreach(var entry in queries){await using var cmd=new NpgsqlCommand("SELECT COALESCE(jsonb_agg(q.item),'[]'::jsonb)::text FROM ("+entry.Value+")q",c,tx);records[entry.Key]=JsonSerializer.Deserialize<JsonElement>((string)(await cmd.ExecuteScalarAsync())!);}
  await tx.CommitAsync();return Results.Ok(records);
 }).RequireAuthorization();
 app.MapPost("/api/care/flow/{action}",async(string action,JsonElement body,HttpContext ctx)=>{
  if(!Guid.TryParse(ctx.Request.Headers["Idempotency-Key"],out var key)||body.ValueKind!=JsonValueKind.Object)throw new RuleException("Enter the care details and a valid retry key.");
  await using var c=await store.Open();await using var tx=await c.BeginTransactionAsync();await Store.Sql(c,tx,"SELECT set_config('hospitalflow.correlation_id',$1,true)",ctx.TraceIdentifier);
  await using var cmd=new NpgsqlCommand("SELECT hf_api.care_command($1,$2::jsonb,$3,$4)",c,tx);cmd.Parameters.AddWithValue(action);cmd.Parameters.AddWithValue(body.GetRawText());cmd.Parameters.AddWithValue(key);cmd.Parameters.AddWithValue(store.RequestHash(body.GetRawText()));try{var reference=(string)(await cmd.ExecuteScalarAsync())!;await tx.CommitAsync();return Results.Ok(new{reference});}
  catch(PostgresException error) when(error.SqlState=="23514"&&error.ConstraintName==null&&error.TableName==null){throw new RuleException(error.MessageText);}
 }).RequireAuthorization();
 }
}
