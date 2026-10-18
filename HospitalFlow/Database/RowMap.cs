using System.Reflection;
using System.Text.RegularExpressions;
using Npgsql;
using NpgsqlTypes;

// Explicit table names, reflected record properties, typed parameters: no user-supplied SQL identifiers.
sealed class RowMap<T>(string table) where T : class
{
    readonly PropertyInfo[] properties = typeof(T).GetProperties(BindingFlags.Instance | BindingFlags.Public);
    static string Column(string name) => Regex.Replace(name, "([a-z0-9])([A-Z])", "$1_$2").ToLowerInvariant();
    string Columns => string.Join(",", properties.Select(p => $"\"{Column(p.Name)}\""));
    public async Task<List<T>> Read(NpgsqlConnection c, NpgsqlTransaction? tx = null, string suffix = "", params object[] args)
    {
        await using var cmd = new NpgsqlCommand($"SELECT {Columns} FROM hospitalflow.{table} {suffix}", c, tx);
        foreach (var arg in args) cmd.Parameters.AddWithValue(arg);
        await using var r = await cmd.ExecuteReaderAsync();
        var result = new List<T>();
        while (await r.ReadAsync())
        {
            var values = properties.Select((p, i) => ReadValue(r, i, p)).ToArray();
            var ctor = typeof(T).GetConstructors().FirstOrDefault(x => x.GetParameters().Length == properties.Length);
            if (ctor != null) result.Add((T)ctor.Invoke(values));
            else
            {
                var item = Activator.CreateInstance<T>();
                for (var i = 0; i < properties.Length; i++) properties[i].SetValue(item, values[i]);
                result.Add(item);
            }
        }
        return result;
    }
    static object? ReadValue(NpgsqlDataReader r, int i, PropertyInfo p)
    {
        if (r.IsDBNull(i)) return null;
        var type = Nullable.GetUnderlyingType(p.PropertyType) ?? p.PropertyType;
        if (type == typeof(DateTimeOffset)) return new DateTimeOffset(DateTime.SpecifyKind(r.GetDateTime(i), DateTimeKind.Utc));
        if (type == typeof(DateOnly)) return r.GetFieldValue<DateOnly>(i);
        if (p.Name == "Dob") return r.GetFieldValue<DateOnly>(i).ToString("yyyy-MM-dd");
        if (typeof(T) == typeof(Doctor) && p.Name is "Start" or "End") return r.GetFieldValue<TimeOnly>(i).ToString("HH:mm");
        return Convert.ChangeType(r.GetValue(i), type);
    }
    public async Task Save(NpgsqlConnection c, NpgsqlTransaction tx, IEnumerable<T> items, IEnumerable<T> old, string? parentColumn = null, string? parent = null)
    {
        var previous = old.ToDictionary(x => properties[0].GetValue(x)!.ToString()!);
        foreach (var item in items)
        {
            var id = properties[0].GetValue(item)!.ToString()!;
            var exists = previous.TryGetValue(id, out var before);
            if (exists && properties.All(p => Equals(p.GetValue(item), p.GetValue(before)))) continue;
            var cols = Columns + (parentColumn == null ? "" : $",{parentColumn}");
            var count = properties.Length + (parentColumn == null ? 0 : 1);
            var vals = string.Join(",", Enumerable.Range(1, count).Select(i => "$" + i));
            var updates = string.Join(",", properties.Skip(1).Select(p => $"\"{Column(p.Name)}\"=EXCLUDED.\"{Column(p.Name)}\""));
            var sql = exists ? $"INSERT INTO hospitalflow.{table} ({cols}) VALUES({vals}) ON CONFLICT(id) DO UPDATE SET {updates}" : $"INSERT INTO hospitalflow.{table} ({cols}) VALUES({vals})";
            await using var cmd = new NpgsqlCommand(sql, c, tx);
            foreach (var p in properties)
            {
                var value = p.GetValue(item);
                if (value is DateTimeOffset at) value = at.ToUniversalTime();
                if (p.Name == "Dob") value = DateOnly.Parse((string)value!);
                if (typeof(T) == typeof(Doctor) && p.Name is "Start" or "End") value = TimeOnly.Parse((string)value!);
                var type = Nullable.GetUnderlyingType(p.PropertyType) ?? p.PropertyType;
                var dbType = type == typeof(DateTimeOffset) ? NpgsqlDbType.TimestampTz : type == typeof(int) ? NpgsqlDbType.Integer : NpgsqlDbType.Text;
                cmd.Parameters.Add(value == null ? new NpgsqlParameter { NpgsqlDbType = dbType, Value = DBNull.Value } : new NpgsqlParameter { Value = value });
            }
            if (parent != null) cmd.Parameters.AddWithValue(parent);
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
