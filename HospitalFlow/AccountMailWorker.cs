using System.Net;
using System.Net.Mail;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Npgsql;

// The queue stores only protected messages. No reset link is returned by an API or written to logs.
sealed class AccountMailWorker(Store store,IDataProtectionProvider protection,IConfiguration config,IWebHostEnvironment env,ILogger<AccountMailWorker> log):BackgroundService {
    protected override async Task ExecuteAsync(CancellationToken stoppingToken) {
        while(!stoppingToken.IsCancellationRequested) {
            try {for(var i=0;i<10&&await Deliver(stoppingToken);i++){} }
            catch(OperationCanceledException)when(stoppingToken.IsCancellationRequested){break;}
            catch(Exception){log.LogError("Account email queue unavailable; pending messages will be retried.");}
            try{await Task.Delay(TimeSpan.FromSeconds(5),stoppingToken);}catch(OperationCanceledException){break;}
        }
    }
    async Task<bool> Deliver(CancellationToken ct) {
        await using var c=await store.Open();await using var tx=await c.BeginTransactionAsync(ct);
        await using var cmd=new NpgsqlCommand("SELECT m.id,m.encrypted_message FROM hospitalflow.account_mail m WHERE status='Pending' AND next_attempt_at<=now() ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1",c,tx);
        Guid id;string ciphertext;
        await using(var r=await cmd.ExecuteReaderAsync(ct)){if(!await r.ReadAsync(ct))return false;id=r.GetGuid(0);ciphertext=r.GetString(1);}
        try {
            var message=JsonSerializer.Deserialize<MailMessageData>(protection.CreateProtector("HospitalFlow.AccountMail.v1").Unprotect(ciphertext))!;
            var host=config["Mail:Smtp:Host"];
            if(!string.IsNullOrEmpty(host)) {
                using var smtp=new SmtpClient(host,config.GetValue<int?>("Mail:Smtp:Port")??587){EnableSsl=true,Timeout=15000};
                if(!string.IsNullOrEmpty(config["Mail:Smtp:Username"]))smtp.Credentials=new NetworkCredential(config["Mail:Smtp:Username"],config["Mail:Smtp:Password"]);
                using var mail=new MailMessage(config["Mail:From"]??throw new InvalidOperationException(),message.To,message.Subject,message.Body);
                await smtp.SendMailAsync(mail,ct);
            } else if(env.IsDevelopment()) {
                var path=Path.GetFullPath(config["Mail:PickupDirectory"]??Path.Combine(env.ContentRootPath,"..",".local","mail"));Directory.CreateDirectory(path);
                if(!OperatingSystem.IsWindows())File.SetUnixFileMode(path,UnixFileMode.UserRead|UnixFileMode.UserWrite|UnixFileMode.UserExecute);
                var file=Path.Combine(path,id+".json");
                var options=new FileStreamOptions{Mode=FileMode.Create,Access=FileAccess.Write};
                if(!OperatingSystem.IsWindows())options.UnixCreateMode=UnixFileMode.UserRead|UnixFileMode.UserWrite;
                await using var stream=new FileStream(file,options);
                await JsonSerializer.SerializeAsync(stream,message,cancellationToken:ct);
            } else throw new InvalidOperationException();
            await Store.Sql(c,tx,"UPDATE hospitalflow.account_mail SET status='Sent',sent_at=now(),attempts=attempts+1,error_code=NULL WHERE id=$1",id);
        }catch(OperationCanceledException)when(ct.IsCancellationRequested){throw;}
        catch(Exception) {
            await Store.Sql(c,tx,"UPDATE hospitalflow.account_mail SET attempts=attempts+1,status=CASE WHEN attempts>=4 THEN 'Failed' ELSE 'Pending' END,next_attempt_at=now()+interval '5 minutes',error_code='DELIVERY_FAILED' WHERE id=$1",id);
            log.LogWarning("Account email delivery failed; check mail configuration. Message {MessageId}",id);
        }
        await tx.CommitAsync(ct);return true;
    }
}
