-- Apply after schema-only installation or a --no-acl restore. Role creation is separate.
REVOKE ALL ON SCHEMA hospitalflow,hf_api,hf_security,hf_reporting,hf_ops FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hospitalflow,hf_api,hf_security,hf_ops FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA hf_api,hf_ops FROM PUBLIC;
GRANT USAGE ON SCHEMA hf_ops TO hospitalflow_job_runner;
GRANT EXECUTE ON PROCEDURE hf_ops.run_due_jobs(integer),hf_ops.worker_heartbeat(text,text),hf_ops.start_backup(uuid),hf_ops.finish_backup(uuid,boolean,text,bigint,text) TO hospitalflow_job_runner;
GRANT EXECUTE ON FUNCTION hf_ops.validate_database() TO hospitalflow_job_runner;
GRANT SELECT ON hf_ops.job_health,hf_ops.latest_integrity_findings,hf_ops.outbox_health TO hospitalflow_job_runner;
GRANT USAGE ON SCHEMA hf_reporting TO hospitalflow_report_reader;
GRANT SELECT ON hf_reporting.daily_collections TO hospitalflow_report_reader;
