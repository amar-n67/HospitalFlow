record PatientAccount(string PatientId,bool MustChangePassword,DateTimeOffset TemporaryExpiresAt);
record SmsMessageData(string To,string Body);
