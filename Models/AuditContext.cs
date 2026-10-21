record AuditContext(string Actor,string? ActorId,string CorrelationId,string? SourceIp,string? Method)
{
    public Audit Event(string action,string reference,string outcome="Success",int? status=null)=>new(Guid.NewGuid().ToString("N"),Actor,action,reference,DateTimeOffset.UtcNow,outcome,ActorId,CorrelationId,SourceIp,Method,status);
}
