REVOKE ALL ON SCHEMA hospitalflow FROM PUBLIC;
GRANT USAGE ON SCHEMA hospitalflow TO hospitalflow_app;
GRANT SELECT ON ALL TABLES IN SCHEMA hospitalflow TO hospitalflow_app;
GRANT INSERT,UPDATE ON hospitalflow.users,hospitalflow.patients,hospitalflow.doctors,hospitalflow.departments,hospitalflow.wards,hospitalflow.appointments,hospitalflow.beds,hospitalflow.admissions,hospitalflow.medicine_batches,hospitalflow.prescriptions,hospitalflow.bills,hospitalflow.notes,hospitalflow.notifications TO hospitalflow_app;
GRANT INSERT ON hospitalflow.activity_log,hospitalflow.stock_movements,hospitalflow.bill_lines,hospitalflow.payments,hospitalflow.idempotency_keys,hospitalflow.data_protection_keys TO hospitalflow_app;
GRANT INSERT,UPDATE,DELETE ON hospitalflow.sessions,hospitalflow.auth_attempts TO hospitalflow_app;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA hospitalflow TO hospitalflow_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hospitalflow TO hospitalflow_app;
REVOKE ALL ON hospitalflow.schema_versions FROM hospitalflow_app;
GRANT SELECT ON hospitalflow.schema_versions TO hospitalflow_app;
-- Schema-grouped database API and read-only aliases. No grants to PUBLIC.
GRANT USAGE ON SCHEMA hf_api,hf_security,hf_reporting,hf_ops TO hospitalflow_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hf_api,hf_security TO hospitalflow_app;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA hf_api TO hospitalflow_app;
GRANT EXECUTE ON PROCEDURE hf_ops.refresh_alerts() TO hospitalflow_app;
GRANT SELECT ON ALL TABLES IN SCHEMA hf_reporting TO hospitalflow_app;
GRANT SELECT ON hf_api.inventory,hf_ops.object_inventory,hf_ops.job_health,hf_ops.latest_integrity_findings,hf_ops.outbox_health TO hospitalflow_app;
GRANT INSERT,UPDATE ON hospitalflow.staff_members,hospitalflow.user_departments,hospitalflow.patient_access_grants,hospitalflow.patient_contacts,hospitalflow.patient_consents,hospitalflow.provider_absences,hospitalflow.provider_sessions,hospitalflow.service_catalog,hospitalflow.service_prices,hospitalflow.clinical_orders,hospitalflow.discharge_tasks,hospitalflow.follow_ups,hospitalflow.suppliers,hospitalflow.purchase_orders,hospitalflow.purchase_order_lines,hospitalflow.medicine_batch_holds,hospitalflow.stock_reservations,hospitalflow.outbox_delivery TO hospitalflow_app;
GRANT INSERT ON hospitalflow.invoice_line_context,hospitalflow.payment_reversals,hospitalflow.goods_receipts,hospitalflow.goods_receipt_lines,hospitalflow.prescription_dispensations,hospitalflow.prescription_authors,hospitalflow.admission_events,hospitalflow.notification_acknowledgements TO hospitalflow_app;
GRANT USAGE ON SCHEMA hf_reporting TO hospitalflow_report_reader;
GRANT SELECT ON hf_reporting.daily_collections TO hospitalflow_report_reader;
GRANT UPDATE(name,updated_at) ON hospitalflow.hospital_profile TO hospitalflow_app;
GRANT EXECUTE ON FUNCTION hf_ops.validate_database() TO hospitalflow_app;

-- Account lifecycle secrets are available only to the trusted application identity.
GRANT SELECT,INSERT,UPDATE ON hospitalflow.account_tokens,hospitalflow.account_mail TO hospitalflow_app;
GRANT SELECT,INSERT,DELETE ON hospitalflow.user_permissions TO hospitalflow_app;
GRANT EXECUTE ON FUNCTION hf_security.protect_account() TO hospitalflow_app;
GRANT SELECT,INSERT,UPDATE ON hospitalflow.patient_accounts,hospitalflow.patient_login_challenges,hospitalflow.patient_sms TO hospitalflow_app;
GRANT EXECUTE ON FUNCTION hf_security.guard_patient_account() TO hospitalflow_app;
GRANT SELECT,INSERT,UPDATE ON hospitalflow.user_preferences TO hospitalflow_app;
GRANT SELECT,INSERT,UPDATE ON hospitalflow.person_profiles TO hospitalflow_app;
GRANT EXECUTE ON FUNCTION hf_api.person_id(text),hf_security.registration_identity(),hf_security.validate_person_profile(),hf_security.patient_email_guard() TO hospitalflow_app;
GRANT SELECT,INSERT,UPDATE ON hospitalflow.email_changes,hospitalflow.work_tasks TO hospitalflow_app;
GRANT SELECT,INSERT,UPDATE ON hospitalflow.hospitals,hospitalflow.hospital_memberships,hospitalflow.patient_hospitals,hospitalflow.referrals TO hospitalflow_app;
GRANT SELECT ON hospitalflow.network_operators TO hospitalflow_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hf_security TO hospitalflow_app;
REVOKE EXECUTE ON FUNCTION hf_api.booking_command_base(text,jsonb,boolean),hf_api.booking_state_base() FROM hospitalflow_app;
GRANT SELECT,INSERT,UPDATE ON hospitalflow.staff_onboarding TO hospitalflow_app;
