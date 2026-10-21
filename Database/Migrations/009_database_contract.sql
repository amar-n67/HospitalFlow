ALTER TABLE hospitalflow.activity_log ADD COLUMN database_user text,ADD COLUMN transaction_id bigint;
ALTER TABLE hospitalflow.activity_log ALTER COLUMN database_user SET DEFAULT session_user,ALTER COLUMN transaction_id SET DEFAULT txid_current();
ALTER TABLE hospitalflow.row_history ADD COLUMN database_user text,ADD COLUMN transaction_id bigint;
ALTER TABLE hospitalflow.row_history ALTER COLUMN database_user SET DEFAULT session_user,ALTER COLUMN transaction_id SET DEFAULT txid_current();
COMMENT ON COLUMN hospitalflow.row_history.database_user IS 'Actual PostgreSQL session login for new events. NULL means the historical event predates this field.';
COMMENT ON COLUMN hospitalflow.activity_log.actor_id IS 'Application identity established by the trusted authenticated backend; database_user separately records the SQL login.';
CREATE OR REPLACE VIEW hf_ops.object_inventory AS
 SELECT n.nspname AS schema_name,CASE c.relkind WHEN 'r' THEN 'TABLE' WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'S' THEN 'SEQUENCE' WHEN 'i' THEN 'INDEX' END AS object_type,c.relname AS object_name
 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops') AND c.relkind IN ('r','v','m','S','i')
 UNION ALL SELECT n.nspname,CASE p.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,p.proname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops')
 UNION ALL SELECT n.nspname,'TRIGGER',c.relname||'.'||t.tgname FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN ('hospitalflow','hf_ops')
 UNION ALL SELECT n.nspname,'POLICY',c.relname||'.'||p.polname FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid=p.polrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hospitalflow'
 UNION ALL SELECT n.nspname,'TYPE',t.typname FROM pg_catalog.pg_type t JOIN pg_catalog.pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='hospitalflow' AND t.typtype IN ('d','e')
 UNION ALL SELECT 'hf_ops','EVENT TRIGGER',evtname FROM pg_catalog.pg_event_trigger WHERE evtname IN ('hospitalflow_ddl_audit','hospitalflow_drop_audit');
CREATE FUNCTION hf_ops.validate_database() RETURNS TABLE(check_name text,severity text,violations bigint,definition text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_ops,pg_temp AS $$
 SELECT 'stock-reconciliation','Error',count(*),'Batch quantity equals its movement ledger' FROM hospitalflow.medicine_batches m WHERE quantity<>(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_movements WHERE medicine_id=m.id)
 UNION ALL SELECT 'negative-invoice-balance','Error',count(*),'Net charges cannot be less than retained payments' FROM hospitalflow.invoice_balances WHERE balance<0
 UNION ALL SELECT 'bed-occupancy','Error',count(*),'Occupied status agrees with the active admission' FROM hospitalflow.beds b WHERE(b.status='Occupied') IS DISTINCT FROM EXISTS(SELECT 1 FROM hospitalflow.admissions a WHERE a.bed_id=b.id AND a.status='Admitted')
 UNION ALL SELECT 'assignment-history','Error',count(*),'Each active admission has the matching open assignment' FROM hospitalflow.admissions a WHERE a.status='Admitted' AND NOT EXISTS(SELECT 1 FROM hospitalflow.bed_assignments b WHERE b.admission_id=a.id AND b.bed_id=a.bed_id AND b.to_time IS NULL)
 UNION ALL SELECT 'reservation-capacity','Error',count(*),'Active reservations do not exceed physical stock' FROM hospitalflow.medicine_batches m WHERE quantity<(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_reservations WHERE medicine_id=m.id AND status='Active')
 UNION ALL SELECT 'payment-reversal-limit','Error',count(*),'Cumulative reversals do not exceed the original payment' FROM hospitalflow.payments p WHERE amount<(SELECT COALESCE(sum(amount),0) FROM hospitalflow.payment_reversals WHERE payment_id=p.id)
 UNION ALL SELECT 'invalid-constraints','Error',count(*),'All installed constraints are validated' FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname IN ('hospitalflow','hf_ops') AND NOT c.convalidated
 UNION ALL SELECT 'invalid-indexes','Error',count(*),'All installed indexes are valid and ready' FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('hospitalflow','hf_ops','hf_reporting') AND(NOT i.indisvalid OR NOT i.indisready)
 UNION ALL SELECT 'disabled-triggers','Error',count(*),'User-defined integrity/audit triggers remain enabled' FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('hospitalflow','hf_ops') AND NOT t.tgisinternal AND t.tgenabled='D'
 UNION ALL SELECT 'tables-without-primary-key','Error',count(*),'Every operational table has a primary key' FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('hospitalflow','hf_ops') AND c.relkind='r' AND NOT EXISTS(SELECT 1 FROM pg_constraint k WHERE k.conrelid=c.oid AND k.contype='p')
 UNION ALL SELECT 'public-routine-execution','Error',count(*),'Application/operations routines are not executable by PUBLIC' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner)))a WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_ops') AND a.grantee=0 AND a.privilege_type='EXECUTE'
 UNION ALL SELECT 'runtime-superuser-or-bypass','Error',count(*),'The application login is neither superuser nor BYPASSRLS' FROM pg_roles WHERE rolname='hospitalflow_app' AND(rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb)
 UNION ALL SELECT 'runtime-owned-objects','Error',count(*),'The runtime login does not own schema objects' FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_roles r ON r.oid=c.relowner WHERE n.nspname IN ('hospitalflow','hf_api','hf_security','hf_reporting','hf_ops') AND r.rolname='hospitalflow_app'
 UNION ALL SELECT 'maintenance-worker-freshness','Warning',CASE WHEN EXISTS(SELECT 1 FROM hf_ops.worker_heartbeats WHERE worker='maintenance' AND last_seen_at>now()-interval '3 minutes' AND status<>'Failed') THEN 0 ELSE 1 END::bigint,'External scheduler heartbeat should be recent'
 UNION ALL SELECT 'backup-freshness','Warning',CASE WHEN EXISTS(SELECT 1 FROM hf_ops.backup_runs WHERE status='Succeeded' AND completed_at>now()-interval '48 hours') THEN 0 ELSE 1 END::bigint,'A successful recorded backup should be newer than 48 hours'
 UNION ALL SELECT 'restore-drill-evidence','Warning',CASE WHEN EXISTS(SELECT 1 FROM hf_ops.restore_drills WHERE outcome='Passed' AND performed_at>now()-interval '90 days') THEN 0 ELSE 1 END::bigint,'Production recovery requires a periodically evidenced restore drill'
$$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hospitalflow,hf_api,hf_security,hf_ops FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA hf_api,hf_ops FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hf_ops.validate_database() TO hospitalflow_job_runner;
COMMENT ON SCHEMA hf_api IS 'Schema-grouped operational functions and procedures: PostgreSQL package equivalent.';
COMMENT ON SCHEMA hf_reporting IS 'Read-only reporting aliases and refreshable materialized reports.';
COMMENT ON SCHEMA hf_security IS 'Trusted-backend actor validation and scoped access policies. The service must derive actor IDs from authenticated sessions.';
COMMENT ON SCHEMA hf_ops IS 'Durable maintenance schedules, job evidence, backup metadata, DDL history and readiness checks. Requires an external scheduler when pg_cron is unavailable.';
COMMENT ON TABLE hospitalflow.integration_outbox IS 'Immutable integration events containing identifiers only. No external messages are sent by database maintenance.';
COMMENT ON TABLE hospitalflow.outbox_delivery IS 'Leased delivery state with retry/backoff and dead-letter status; adapters require a separately authorized integration worker.';
COMMENT ON TABLE hospitalflow.admission_events IS 'Preserves admission/transfer/discharge reasons and actor identity; clinical text stays out of generic audit payloads.';
COMMENT ON TABLE hospitalflow.prescription_dispensations IS 'Auditable linkage between prescription, stock movement, patient invoice and dispenser.';
COMMENT ON TABLE hospitalflow.payment_reversals IS 'Append-only local accounting reversals. Does not execute an external payment-provider refund.';
COMMENT ON VIEW hf_ops.object_inventory IS 'Installed PostgreSQL object inventory; packages/synonyms are represented by grouped schemas and read-only view aliases.';
