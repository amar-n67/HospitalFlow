# Separate Admin and Doctor roles

HospitalFlow uses separate **Admin** and **Doctor** primary roles. Create accounts from **People & registrations → Add person**, choosing the appropriate type. Doctor registration includes department and consultation hours and creates a linked provider record with a D-prefixed registration ID. Admin registration uses the A prefix. Existing accounts, patient records, prescriptions and audit authors are retained.

| Capability | Admin | Doctor | Developer |
| --- | --- | --- | --- |
| Hospital management, accounts, billing, inventory and operational controls | Yes, within authorised hospitals | No administrative account or finance access | Yes |
| Patient registration, appointment booking and referrals | Yes | Yes, with existing department and hospital booking restrictions | Yes |
| Clinical record viewing | Read-only management access | Clinical access | Yes |
| Prescriptions and treatment documentation | No | Yes | Yes |
| Clinical orders and follow-up instructions | No | Yes, subject to existing patient/encounter permissions | Yes |
| Attendance, leave and employee administration | Assigned hospital administration | Own attendance/leave and shared hospital leave calendar | Both, with applicable hospital membership checks |

Nursing documentation remains available to Nurse accounts; nurses cannot prescribe. Existing authorised non-privileged registration workflows for doctors are preserved. Patient and Volunteer access stays restricted. Administrative discharge stores its reason in admission-event history and does not create a clinical discharge note under an Admin identity. Clinical staff continue to create clinical discharge notes.

A Doctor permission checkbox cannot be used to combine clinical prescribing with another primary role. Choose the Doctor role explicitly. Older limited staff accounts with a Doctor grant are migrated to the Doctor role, and redundant Doctor grants are removed. Department/provider linkage for an incomplete legacy clinician can be completed by an administrator using the person editor. Developer retains combined access as requested.

The API denies Admin clinical-authoring actions. PostgreSQL guards clinical table writes and the native command gateway, including attempts that bypass the normal browser. The Admin clinical workspace is read-only and its Operations page omits clinical mutations. Doctor and nursing clinical operations are available through the Clinical workspace with matching API permissions.

Migration `021_admin_doctor_separation.sql` applies the policy. `tests/role_separation.py` verifies Admin rejection, Doctor/Nurse clinical operations, Developer combined access, native SQL enforcement and mixed-role permission rejection in a disposable database. No Doctor login or password is invented for a live hospital; create the person with their actual details through the registration workflow.
