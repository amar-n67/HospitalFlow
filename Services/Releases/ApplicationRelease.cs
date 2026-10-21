using System.Reflection;
using System.Text.RegularExpressions;
using System.Text.Json;
using Npgsql;
static class ApplicationRelease {
 public static string CurrentVersion {get;private set;}="1.0.0";
 public static string? Commit {get;private set;}
 public static string WorkingTree {get;private set;}="unknown";
 public static object BuildInfo()=>new{version=CurrentVersion,commit=Commit,workingTree=WorkingTree};
 public static async Task Register(Store store){
  // Build/publish copies this tracked manifest beside the application binary.
  using var manifest=JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"release.json")));
  var assembly=Assembly.GetExecutingAssembly();
  var info=assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion??throw new InvalidOperationException("Build version metadata is missing.");
  var parts=info.Split('+',2);CurrentVersion=parts[0];
  Commit=parts.Length>1&&Regex.IsMatch(parts[1],"^[a-fA-F0-9]{40,64}$")?parts[1]:null;
  WorkingTree=assembly.GetCustomAttributes<AssemblyMetadataAttribute>().FirstOrDefault(x=>x.Key=="WorkingTreeState")?.Value??"unknown";
  if(manifest.RootElement.GetProperty("version").GetString()!=CurrentVersion)throw new InvalidOperationException("Release manifest does not match the compiled version. Rebuild before starting.");
  await using var c=await store.Open();await using var tx=await c.BeginTransactionAsync();
  foreach(var release in manifest.RootElement.GetProperty("releases").EnumerateArray()){
   await using var cmd=new NpgsqlCommand("SELECT hf_api.record_release($1::jsonb)",c,tx);cmd.Parameters.AddWithValue(release.GetRawText());await cmd.ExecuteNonQueryAsync();
  }
  await tx.CommitAsync();
 }
}
