CREATE TABLE hf_ops.worker_heartbeats(worker text PRIMARY KEY,last_seen_at timestamptz NOT NULL,status text NOT NULL CHECK(status IN ('Started','Succeeded','Failed')));
CREATE PROCEDURE hf_ops.refresh_alerts() LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_ops,pg_temp AS $$
DECLARE v_alerts jsonb;BEGIN PERFORM pg_advisory_xact_lock(74192301);
 SELECT COALESCE(jsonb_agg(to_jsonb(a)),'[]'::jsonb) INTO v_alerts FROM(
 SELECT 'low-stock'::text rule,id reference,'Low stock needs attention'::text title,name||': '||quantity||' units remaining (reorder at '||reorder||').' message,'pharmacy'::text target FROM hospitalflow.medicine_batches WHERE quantity<=reorder
 UNION ALL SELECT 'expiry',id,'Medicine approaching expiry',name||' · '||batch||' · '||expiry,'pharmacy' FROM hospitalflow.medicine_batches WHERE expiry<=hf_api.hospital_today()+30
 UNION ALL SELECT 'cleaning',id,'Bed awaiting turnaround',id||' needs cleaning confirmation before reuse.','beds' FROM hospitalflow.beds WHERE status='Cleaning'
 UNION ALL SELECT 'queue',id,'Queue waiting time','A checked-in appointment has waited over 30 minutes.','appointments' FROM hospitalflow.appointments WHERE status='Checked in' AND checked_in<now()-interval '30 minutes')a;
 UPDATE hospitalflow.notifications n SET resolved_at=now() WHERE resolved_at IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_to_recordset(v_alerts) a(rule text,reference text) WHERE a.rule=n.rule AND a.reference=n.reference);
 INSERT INTO hospitalflow.notifications(id,rule,reference,title,message,target) SELECT gen_random_uuid()::text,rule,reference,title,message,target FROM jsonb_to_recordset(v_alerts) a(rule text,reference text,title text,message text,target text)
 ON CONFLICT(rule,reference) WHERE resolved_at IS NULL DO UPDATE SET message=EXCLUDED.message,title=EXCLUDED.title;
END $$;
CREATE PROCEDURE hf_ops.run_due_jobs(IN p_limit integer DEFAULT 5) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hospitalflow,hf_ops,pg_temp AS $$
DECLARE j hf_ops.job_definitions%ROWTYPE;run uuid;failed boolean;code text;violations bigint;BEGIN
 IF p_limit NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'Job limit must be between 1 and 20' USING ERRCODE='23514';END IF;
 FOR j IN SELECT * FROM hf_ops.job_definitions WHERE enabled AND next_run_at<=clock_timestamp() ORDER BY next_run_at,name LIMIT p_limit FOR UPDATE SKIP LOCKED LOOP
 run:=gen_random_uuid();failed:=false;code:=NULL;
 INSERT INTO hf_ops.job_runs(id,job_name,status) VALUES(run,j.name,'Running');
 UPDATE hf_ops.job_definitions SET last_started_at=clock_timestamp() WHERE name=j.name;
 BEGIN
 CASE j.task
 WHEN 'refresh_alerts' THEN CALL hf_ops.refresh_alerts();
 WHEN 'session_cleanup' THEN DELETE FROM hospitalflow.sessions WHERE expires_at<now();DELETE FROM hospitalflow.auth_attempts WHERE blocked_until<now()-interval '1 day';
 WHEN 'integrity_check' THEN
 INSERT INTO hf_ops.integrity_findings(run_id,check_name,violations)
 SELECT run,'stock-reconciliation',count(*) FROM hospitalflow.medicine_batches m WHERE quantity<>(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_movements WHERE medicine_id=m.id)
 UNION ALL SELECT run,'negative-invoice-balance',count(*) FROM hospitalflow.invoice_balances WHERE balance<0
 UNION ALL SELECT run,'bed-occupancy',count(*) FROM hospitalflow.beds b WHERE(b.status='Occupied') IS DISTINCT FROM EXISTS(SELECT 1 FROM hospitalflow.admissions a WHERE a.bed_id=b.id AND a.status='Admitted')
 UNION ALL SELECT run,'stock-reservations',count(*) FROM hospitalflow.medicine_batches m WHERE quantity<(SELECT COALESCE(sum(quantity),0) FROM hospitalflow.stock_reservations WHERE medicine_id=m.id AND status='Active');
 SELECT sum(f.violations) INTO violations FROM hf_ops.integrity_findings f WHERE f.run_id=run;
 IF violations>0 THEN failed:=true;code:='INTEGRITY_FINDINGS';END IF;
 WHEN 'daily_snapshot' THEN INSERT INTO hf_ops.daily_snapshots(day,ward,staffed_beds,occupied_beds,available_beds)
 SELECT hf_api.hospital_today(),ward,staffed_beds,occupied_beds,available_beds FROM hospitalflow.bed_occupancy
 ON CONFLICT(day,ward) DO UPDATE SET staffed_beds=EXCLUDED.staffed_beds,occupied_beds=EXCLUDED.occupied_beds,available_beds=EXCLUDED.available_beds,captured_at=now();
 WHEN 'refresh_reports' THEN REFRESH MATERIALIZED VIEW hf_reporting.daily_collections;
 WHEN 'recover_outbox_leases' THEN UPDATE hospitalflow.outbox_delivery SET status=CASE WHEN attempts>=5 THEN 'Dead letter' ELSE 'Pending' END,lease_token=NULL,lease_until=NULL,next_attempt_at=now(),last_error_code='LEASE_EXPIRED' WHERE status='Leased' AND lease_until<now();
 WHEN 'backup_monitor' THEN INSERT INTO hf_ops.integrity_findings(run_id,check_name,violations) VALUES(run,'backup-freshness',CASE WHEN EXISTS(SELECT 1 FROM hf_ops.backup_runs WHERE status='Succeeded' AND completed_at>now()-interval '48 hours') THEN 0 ELSE 1 END);
 WHEN 'analyze_tables' THEN ANALYZE hospitalflow.patients;ANALYZE hospitalflow.appointments;ANALYZE hospitalflow.admissions;ANALYZE hospitalflow.medicine_batches;ANALYZE hospitalflow.stock_movements;ANALYZE hospitalflow.bills;ANALYZE hospitalflow.bill_lines;ANALYZE hospitalflow.payments;ANALYZE hospitalflow.activity_log;
 END CASE;
 EXCEPTION WHEN OTHERS THEN failed:=true;code:=SQLSTATE;
 END;
 UPDATE hf_ops.job_runs SET finished_at=clock_timestamp(),status=CASE WHEN failed THEN 'Failed' ELSE 'Succeeded' END,error_code=code WHERE id=run;
 UPDATE hf_ops.job_definitions SET last_finished_at=clock_timestamp(),last_status=CASE WHEN failed THEN 'Failed' ELSE 'Succeeded' END,failures=CASE WHEN failed THEN failures+1 ELSE 0 END,
 next_run_at=clock_timestamp()+make_interval(secs=>CASE WHEN failed THEN least(21600,j.interval_seconds*power(2,least(j.failures+1,8)))::integer ELSE j.interval_seconds END) WHERE name=j.name;
 INSERT INTO hospitalflow.activity_log(id,actor,action,reference,at,outcome,correlation_id,method) VALUES(gen_random_uuid()::text,'Database scheduler','job-run',j.name,clock_timestamp(),CASE WHEN failed THEN 'Failed' ELSE 'Success' END,run::text,'JOB');
 END LOOP;END $$;
CREATE PROCEDURE hf_ops.worker_heartbeat(IN p_worker text,IN p_status text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
BEGIN IF p_worker!~'^[a-z0-9_-]{1,64}$' OR p_status NOT IN ('Started','Succeeded','Failed') THEN RAISE EXCEPTION 'Invalid heartbeat' USING ERRCODE='23514';END IF;
 INSERT INTO hf_ops.worker_heartbeats(worker,last_seen_at,status) VALUES(p_worker,clock_timestamp(),p_status) ON CONFLICT(worker) DO UPDATE SET last_seen_at=EXCLUDED.last_seen_at,status=EXCLUDED.status;END $$;
CREATE PROCEDURE hf_ops.start_backup(INOUT p_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
BEGIN p_id:=gen_random_uuid();INSERT INTO hf_ops.backup_runs(id,status) VALUES(p_id,'Running');END $$;
CREATE PROCEDURE hf_ops.finish_backup(IN p_id uuid,IN p_success boolean,IN p_reference text,IN p_bytes bigint,IN p_sha256 text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
BEGIN IF p_success AND(p_reference IS NULL OR p_reference!~'^[a-zA-Z0-9._-]{1,200}$' OR p_bytes<=0 OR p_sha256!~'^[A-Fa-f0-9]{64}$') THEN RAISE EXCEPTION 'Invalid backup evidence' USING ERRCODE='23514';END IF;
 UPDATE hf_ops.backup_runs SET status=CASE WHEN p_success THEN 'Succeeded' ELSE 'Failed' END,completed_at=clock_timestamp(),file_reference=CASE WHEN p_success THEN p_reference END,bytes=CASE WHEN p_success THEN p_bytes END,sha256=CASE WHEN p_success THEN p_sha256 END,error_code=CASE WHEN NOT p_success THEN 'BACKUP_FAILED' END WHERE id=p_id AND status='Running';
 IF NOT FOUND THEN RAISE EXCEPTION 'Backup run is not active' USING ERRCODE='23514';END IF;END $$;
CREATE VIEW hf_ops.job_health AS SELECT j.name,j.enabled,j.next_run_at,j.last_started_at,j.last_finished_at,j.last_status,j.failures,
 CASE WHEN NOT j.enabled THEN 'Disabled' WHEN j.last_status='Failed' THEN 'Failed' WHEN j.next_run_at<now()-make_interval(secs=>greatest(180,j.interval_seconds)) THEN 'Overdue' ELSE 'Ready' END health FROM hf_ops.job_definitions j;
CREATE VIEW hf_ops.latest_integrity_findings AS SELECT DISTINCT ON(check_name) check_name,violations,checked_at,run_id FROM hf_ops.integrity_findings ORDER BY check_name,checked_at DESC,id;
CREATE VIEW hf_ops.outbox_health AS SELECT status,count(*) event_count,min(next_attempt_at) oldest_due FROM hospitalflow.outbox_delivery GROUP BY status;
CREATE FUNCTION hf_api.claim_outbox(p_limit integer,p_lease_seconds integer) RETURNS TABLE(event_id uuid,event_type text,aggregate_id text,payload jsonb,lease_token uuid) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,hf_api,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY[]::text[]);
 IF p_limit NOT BETWEEN 1 AND 100 OR p_lease_seconds NOT BETWEEN 30 AND 900 THEN RAISE EXCEPTION 'Invalid outbox claim limits' USING ERRCODE='23514';END IF;
 RETURN QUERY WITH candidates AS(SELECT d.event_id FROM hospitalflow.outbox_delivery d WHERE d.status='Pending' AND d.next_attempt_at<=now() ORDER BY d.next_attempt_at,d.event_id LIMIT p_limit FOR UPDATE SKIP LOCKED),
 claimed AS(UPDATE hospitalflow.outbox_delivery d SET status='Leased',attempts=attempts+1,lease_token=gen_random_uuid(),lease_until=now()+make_interval(secs=>p_lease_seconds) FROM candidates c WHERE d.event_id=c.event_id RETURNING d.event_id,d.lease_token)
 SELECT e.id,e.event_type,e.aggregate_id,e.payload,c.lease_token FROM claimed c JOIN hospitalflow.integration_outbox e ON e.id=c.event_id;
END $$;
CREATE PROCEDURE hf_api.complete_outbox(IN p_event uuid,IN p_token uuid,IN p_success boolean,IN p_error_code text) LANGUAGE plpgsql SET search_path=pg_catalog,hospitalflow,pg_temp AS $$
BEGIN PERFORM hf_security.require_actor(ARRAY[]::text[]);
 IF NOT p_success AND(p_error_code IS NULL OR p_error_code!~'^[A-Z0-9_]{1,64}$') THEN RAISE EXCEPTION 'A safe error code is required' USING ERRCODE='23514';END IF;
 UPDATE hospitalflow.outbox_delivery SET status=CASE WHEN p_success THEN 'Delivered' WHEN attempts>=5 THEN 'Dead letter' ELSE 'Pending' END,delivered_at=CASE WHEN p_success THEN now() END,lease_token=NULL,lease_until=NULL,
 last_error_code=CASE WHEN NOT p_success THEN p_error_code END,next_attempt_at=now()+make_interval(secs=>least(3600,30*power(2,least(attempts,8)))::integer) WHERE event_id=p_event AND lease_token=p_token AND status='Leased' AND lease_until>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'Outbox lease is missing, expired or belongs to another worker' USING ERRCODE='23514';END IF;
 PERFORM hf_security.audit('outbox-completion',p_event::text);END $$;
CREATE FUNCTION hf_ops.prevent_history_change() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Operational evidence cannot be deleted or rewritten' USING ERRCODE='23514';END $$;
CREATE TRIGGER immutable_findings BEFORE UPDATE OR DELETE ON hf_ops.integrity_findings FOR EACH ROW EXECUTE FUNCTION hf_ops.prevent_history_change();
CREATE TRIGGER immutable_ddl_audit BEFORE UPDATE OR DELETE ON hf_ops.schema_change_events FOR EACH ROW EXECUTE FUNCTION hf_ops.prevent_history_change();
CREATE TRIGGER immutable_restore_evidence BEFORE UPDATE OR DELETE ON hf_ops.restore_drills FOR EACH ROW EXECUTE FUNCTION hf_ops.prevent_history_change();
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hf_ops,hf_api FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA hf_ops,hf_api FROM PUBLIC;
GRANT USAGE ON SCHEMA hf_ops TO hospitalflow_job_runner;
GRANT EXECUTE ON PROCEDURE hf_ops.run_due_jobs(integer),hf_ops.worker_heartbeat(text,text),hf_ops.start_backup(uuid),hf_ops.finish_backup(uuid,boolean,text,bigint,text) TO hospitalflow_job_runner;
GRANT SELECT ON hf_ops.job_health,hf_ops.latest_integrity_findings,hf_ops.outbox_health TO hospitalflow_job_runner;
CREATE FUNCTION hf_ops.protect_run_evidence() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE allowed text[];BEGIN
 IF TG_OP='DELETE' OR OLD.status<>'Running' OR NEW.status NOT IN ('Succeeded','Failed','Skipped') THEN RAISE EXCEPTION 'Completed operational evidence is immutable' USING ERRCODE='23514';END IF;
 allowed:=CASE WHEN TG_TABLE_NAME='job_runs' THEN ARRAY['status','finished_at','error_code'] ELSE ARRAY['status','completed_at','file_reference','bytes','sha256','error_code'] END;
 IF(to_jsonb(NEW)-allowed) IS DISTINCT FROM(to_jsonb(OLD)-allowed) THEN RAISE EXCEPTION 'Only final result fields can change' USING ERRCODE='23514';END IF;
 RETURN NEW;END $$;
CREATE TRIGGER immutable_completed_run BEFORE UPDATE OR DELETE ON hf_ops.job_runs FOR EACH ROW EXECUTE FUNCTION hf_ops.protect_run_evidence();
CREATE TRIGGER immutable_completed_backup BEFORE UPDATE OR DELETE ON hf_ops.backup_runs FOR EACH ROW EXECUTE FUNCTION hf_ops.protect_run_evidence();
CREATE TRIGGER audit_job_configuration AFTER INSERT OR UPDATE OR DELETE ON hf_ops.job_definitions FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
CREATE PROCEDURE hf_ops.record_restore_drill(IN p_backup uuid,IN p_passed boolean,IN p_evidence text,IN p_seconds integer) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hf_ops,pg_temp AS $$
BEGIN IF length(trim(p_evidence)) NOT BETWEEN 1 AND 300 OR p_seconds<0 OR NOT EXISTS(SELECT 1 FROM hf_ops.backup_runs WHERE id=p_backup AND status='Succeeded') THEN RAISE EXCEPTION 'Completed backup and restore evidence required' USING ERRCODE='23514';END IF;
 INSERT INTO hf_ops.restore_drills(backup_id,outcome,evidence_reference,recovery_seconds) VALUES(p_backup,CASE WHEN p_passed THEN 'Passed' ELSE 'Failed' END,p_evidence,p_seconds);END $$;
REVOKE ALL ON FUNCTION hf_ops.protect_run_evidence() FROM PUBLIC;
REVOKE ALL ON PROCEDURE hf_ops.record_restore_drill(uuid,boolean,text,integer) FROM PUBLIC;
