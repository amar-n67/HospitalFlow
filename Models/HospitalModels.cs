record HospitalContext(string HospitalId,string UserId,string? PatientId);
record HospitalEntry(string Id,string Name,string Address,string City,string State,string PostalCode,bool Active,bool AcceptingReferrals,bool IsDemo);
record NetworkProvider(string Id,string HospitalId,string RegistrationId,string Name,string Department,string Start,string End);
record ReferralEntry(string Id,string PatientId,string PatientName,string PatientCode,string SourceHospitalId,string TargetHospitalId,string? TargetDoctorId,string Reason,string Status,DateTimeOffset CreatedAt,string? ResolutionNote);
