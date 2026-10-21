record AccountInfo(string Id,string Name,string Email,string Role,bool Active,bool EmailConfirmed,string[] Permissions,string? RegistrationId=null);
record MailMessageData(string To,string Subject,string Body);
