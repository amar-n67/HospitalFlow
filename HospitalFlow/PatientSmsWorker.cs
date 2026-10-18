using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Npgsql;
// Explicit local-only transport. Production messages remain pending until a provider is implemented.
sealed class PatientSmsWorker(Store store,IDataProtectionProvider protection,IConfiguration config,IWebHostEnvironment env,ILogger<PatientSmsWorker> log):BackgroundService {
    protected override async Task ExecuteAsync(CancellationToken ct) {
        if(!env.IsDevelopment())return;
        while(!ct.IsCancellationRequested){try{for(var i=0;i<10&&await Deliver(ct);i++){} }catch(OperationCanceledException)when(ct.IsCancellationRequested){break;}catch(Exception){log.LogWarning("Local patient SMS pickup unavailable; pending messages remain queued.");}
            try{await Task.Delay(1000,ct);}catch(OperationCanceledException){break;}}
    }
    async Task<bool> Deliver(CancellationToken ct) {
        await using var c=await store.Open();await using var tx=await c.BeginTransactionAsync(ct);
        await using var cmd=new NpgsqlCommand("SELECT id,encrypted_message FROM hospitalflow.patient_sms WHERE status='Pending' ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1",c,tx);
        Guid id;string ciphertext;await using(var r=await cmd.ExecuteReaderAsync(ct)){if(!await r.ReadAsync(ct))return false;id=r.GetGuid(0);ciphertext=r.GetString(1);}
        var message=JsonSerializer.Deserialize<SmsMessageData>(protection.CreateProtector("HospitalFlow.PatientSms.v1").Unprotect(ciphertext));
        var path=Path.GetFullPath(config["Sms:PickupDirectory"]??Path.Combine(env.ContentRootPath,"..",".local","sms"));Directory.CreateDirectory(path);
        if(!OperatingSystem.IsWindows())File.SetUnixFileMode(path,UnixFileMode.UserRead|UnixFileMode.UserWrite|UnixFileMode.UserExecute);
        var options=new FileStreamOptions{Mode=FileMode.Create,Access=FileAccess.Write};if(!OperatingSystem.IsWindows())options.UnixCreateMode=UnixFileMode.UserRead|UnixFileMode.UserWrite;
        await using(var stream=new FileStream(Path.Combine(path,id+".json"),options))await JsonSerializer.SerializeAsync(stream,message,cancellationToken:ct);
        await Store.Sql(c,tx,"UPDATE hospitalflow.patient_sms SET status='Local pickup',completed_at=now() WHERE id=$1",id);await tx.CommitAsync(ct);return true;
    }
}
