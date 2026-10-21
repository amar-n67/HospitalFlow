static class Access {
    public static readonly string[] Permissions=["Reception","Doctor","Nurse","Pharmacist","Billing"];
    public static readonly string[] ClinicalActions=["prescription","cancel-prescription","note","clinical-order","clinical-order-status","complete-clinical-order","follow-up"];
    public static bool Full(string? role)=>role is "Admin" or "Developer";
}
