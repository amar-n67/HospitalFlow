using Microsoft.AspNetCore.Identity;
using Npgsql;
sealed partial class Store {
 public async Task<DateTimeOffset?> StaffOnboardingExpiry(string id){await using var c=await Open();await using var cmd=new NpgsqlCommand("SELECT expires_at FROM hospitalflow.staff_onboarding WHERE user_id=$1 AND must_change_password",c);cmd.Parameters.AddWithValue(id);var value=await cmd.ExecuteScalarAsync();return value is DateTime time?new DateTimeOffset(time,TimeSpan.Zero):null;}
 async Task<bool> CompleteStaffOnboarding(string token,string dob,string password,AuditContext audit){
  await using var c=await Open();await using var tx=await c.BeginTransactionAsync();await Sql(c,tx,"SELECT pg_advisory_xact_lock(74192301)");
  await using var cmd=new NpgsqlCommand("SELECT t.user_id,p.dob::text FROM hospitalflow.patient_login_challenges t JOIN hospitalflow.staff_onboarding s ON s.user_id=t.user_id JOIN hospitalflow.person_profiles p ON p.user_id=t.user_id JOIN hospitalflow.users u ON u.id=t.user_id WHERE t.token_hash=$1 AND t.consumed_at IS NULL AND t.expires_at>now() AND t.attempts<5 AND s.must_change_password AND s.expires_at>now() AND u.active FOR UPDATE OF t,s,u",c,tx);cmd.Parameters.AddWithValue(Hash(token));string id,expected;
  await using(var reader=await cmd.ExecuteReaderAsync()){if(!await reader.ReadAsync())return false;id=reader.GetString(0);expected=reader.GetString(1);}
  if(dob!=expected){await Sql(c,tx,"UPDATE hospitalflow.patient_login_challenges SET attempts=attempts+1 WHERE token_hash=$1",Hash(token));await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("staff-verification",id,"Rejected")],[]);await tx.CommitAsync();throw new RuleException("Verification failed. Check the date of birth entered during registration.");}
  var user=(await new RowMap<User>("users").Read(c,tx,"WHERE id=$1",id)).Single();AccountValidation.Password(password,user.Name,user.Email);
  if(new PasswordHasher<User>().VerifyHashedPassword(user,user.PasswordHash,password)!=PasswordVerificationResult.Failed)throw new RuleException("Choose a new password different from the temporary password.");
  await Sql(c,tx,"SELECT set_config('hospitalflow.actor_id',$1,true),set_config('hospitalflow.correlation_id',$2,true)",id,audit.CorrelationId);
  await Sql(c,tx,"UPDATE hospitalflow.users SET password_hash=$1 WHERE id=$2",new PasswordHasher<User>().HashPassword(user,password),id);
  await Sql(c,tx,"UPDATE hospitalflow.staff_onboarding SET must_change_password=false,activated_at=now() WHERE user_id=$1",id);
  await Sql(c,tx,"UPDATE hospitalflow.patient_login_challenges SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",id);
  await Sql(c,tx,"UPDATE hospitalflow.account_tokens SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL",id);
  await Sql(c,tx,"DELETE FROM hospitalflow.sessions WHERE user_id=$1",id);
  await new RowMap<Audit>("activity_log").Save(c,tx,[audit.Event("staff-access-activated",id)],[]);await tx.CommitAsync();return true;
 }
}
