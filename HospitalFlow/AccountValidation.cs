using System.Net.Mail;
using System.Text.RegularExpressions;

static class AccountValidation {
    public const string PasswordHelp="Use 6–128 characters, including an uppercase letter, a lowercase letter and a symbol. Do not use common passwords, your name, username or email.";
    public static string Email(string value) {
        value=value.Trim().ToLowerInvariant();
        if(value.Length>150||!Regex.IsMatch(value,@"^[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$")||value.Split('@')[0].Length>64||!MailAddress.TryCreate(value,out var address)||address.Address!=value)
            throw new RuleException("Enter a valid email address, such as name@gmail.com. Include @ and a complete domain.");
        return value;
    }
    static string Normalized(string value)=>string.Concat(value.Where(char.IsLetterOrDigit)).ToLowerInvariant();
    public static void Password(string value,string name="",string email="") {
        if(value.Length is <6 or >128)throw new RuleException("Password must contain 6–128 characters.");
        if(!value.Any(c=>c is >= 'A' and <= 'Z'))throw new RuleException("Password must contain an uppercase letter (A–Z).");
        if(!value.Any(c=>c is >= 'a' and <= 'z'))throw new RuleException("Password must contain a lowercase letter (a–z).");
        if(!value.Any(c=>char.IsPunctuation(c)||char.IsSymbol(c)))throw new RuleException("Password must contain a symbol, such as @, # or !.");
        var normalized=Normalized(value);var letters=string.Concat(normalized.Where(char.IsLetter));
        if(normalized.Contains("password")||new[]{"pass","passwords","qwerty","admin","administrator","welcome","letmein","changeme","abc","abcdef"}.Contains(letters))
            throw new RuleException("Choose a less common password. Password, passwords and pass variations are not allowed.");
        var identities=Regex.Split(name,@"\s+").Append(name).Append(email.Split('@')[0]).Append(email);
        if(identities.Select(Normalized).Any(identity=>identity.Length>0&&(normalized==identity||(identity.Length>=3&&normalized.Contains(identity)))))
            throw new RuleException("Password must not contain your name, username or email address.");
    }
}
