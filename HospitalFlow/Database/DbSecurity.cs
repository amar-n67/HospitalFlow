using System.Security.Claims;
using System.Xml.Linq;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.DataProtection.Repositories;
using Npgsql;

sealed class DbKeyRepository(Store store) : IXmlRepository
{
    public IReadOnlyCollection<XElement> GetAllElements()
    {
        using var c=store.Open().AsTask().GetAwaiter().GetResult();
        using var cmd=new NpgsqlCommand("SELECT xml FROM hospitalflow.data_protection_keys ORDER BY id",c);
        using var r=cmd.ExecuteReader();var list=new List<XElement>();while(r.Read())list.Add(XElement.Parse(r.GetString(0)));return list;
    }
    public void StoreElement(XElement element,string friendlyName)
    {
        using var c=store.Open().AsTask().GetAwaiter().GetResult();
        using var cmd=new NpgsqlCommand("INSERT INTO hospitalflow.data_protection_keys(friendly_name,xml) VALUES($1,$2)",c);
        cmd.Parameters.AddWithValue(friendlyName);cmd.Parameters.AddWithValue(element.ToString(SaveOptions.DisableFormatting));cmd.ExecuteNonQuery();
    }
}
sealed class DbTicketStore(Store store,IDataProtectionProvider protection) : ITicketStore
{
    readonly IDataProtector protector=protection.CreateProtector("HospitalFlow.DatabaseSessions.v1");
    public async Task<string> StoreAsync(AuthenticationTicket ticket)
    {
        var key=Guid.NewGuid().ToString("N");await Write(key,ticket);return key;
    }
    public Task RenewAsync(string key,AuthenticationTicket ticket)=>Write(key,ticket);
    async Task Write(string key,AuthenticationTicket ticket)
    {
        var userId=ticket.Principal.FindFirstValue(ClaimTypes.NameIdentifier)??throw new InvalidOperationException("Session requires user identity.");
        var bytes=protector.Protect(TicketSerializer.Default.Serialize(ticket));
        await using var c=await store.Open();
        await Store.Sql(c,null,"DELETE FROM hospitalflow.sessions WHERE expires_at<now()");
        await Store.Sql(c,null,"INSERT INTO hospitalflow.sessions(id,user_id,ticket,expires_at) VALUES($1,$2,$3,$4) ON CONFLICT(id) DO UPDATE SET ticket=EXCLUDED.ticket,expires_at=EXCLUDED.expires_at",key,userId,bytes,(ticket.Properties.ExpiresUtc??DateTimeOffset.UtcNow.AddHours(4)).ToUniversalTime());
    }
    public async Task<AuthenticationTicket?> RetrieveAsync(string key)
    {
        await using var c=await store.Open();await using var cmd=new NpgsqlCommand("SELECT s.ticket FROM hospitalflow.sessions s JOIN hospitalflow.users u ON u.id=s.user_id WHERE s.id=$1 AND s.expires_at>now() AND u.active",c);
        cmd.Parameters.AddWithValue(key);var bytes=await cmd.ExecuteScalarAsync() as byte[];
        if(bytes==null)return null;
        try {return TicketSerializer.Default.Deserialize(protector.Unprotect(bytes));}catch(System.Security.Cryptography.CryptographicException){return null;}
    }
    public async Task RemoveAsync(string key) {await using var c=await store.Open();await Store.Sql(c,null,"DELETE FROM hospitalflow.sessions WHERE id=$1",key);}
}
