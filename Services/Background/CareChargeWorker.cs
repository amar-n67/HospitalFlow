using System.Security.Claims;
using System.Text.Json;
using Npgsql;
sealed class CareChargeWorker(Store store,ILogger<CareChargeWorker> logger):BackgroundService {
 protected override async Task ExecuteAsync(CancellationToken stop){
  using var timer=new PeriodicTimer(TimeSpan.FromMinutes(5));
  while(await timer.WaitForNextTickAsync(stop))try{await using var c=await store.Open();await using var tx=await c.BeginTransactionAsync();await using var cmd=new NpgsqlCommand("SELECT hf_api.accrue_due_care_charges()",c,tx);await cmd.ExecuteScalarAsync(stop);await tx.CommitAsync(stop);}catch(OperationCanceledException) when(stop.IsCancellationRequested){break;}catch(Exception e){logger.LogWarning("Care charge accrual did not complete ({ErrorType}). It will retry.",e.GetType().Name);}
 }
}
