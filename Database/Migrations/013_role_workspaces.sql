CREATE TABLE hospitalflow.email_changes(
 token_hash text PRIMARY KEY,user_id text NOT NULL REFERENCES hospitalflow.users(id),
 email text NOT NULL,password_fingerprint text NOT NULL CHECK(length(password_fingerprint)=64),expires_at timestamptz NOT NULL,consumed_at timestamptz,created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX email_changes_user ON hospitalflow.email_changes(user_id,created_at);
CREATE TABLE hospitalflow.work_tasks(
 id text PRIMARY KEY,assigned_to text NOT NULL REFERENCES hospitalflow.users(id),created_by text NOT NULL REFERENCES hospitalflow.users(id),
 title text NOT NULL CHECK(length(title) BETWEEN 2 AND 150),location text NOT NULL CHECK(length(location) BETWEEN 1 AND 150),
 due_at timestamptz NOT NULL,status text NOT NULL DEFAULT 'Assigned' CHECK(status IN ('Assigned','In progress','Completed')),
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX work_tasks_assignee ON hospitalflow.work_tasks(assigned_to,due_at);
CREATE TRIGGER record_history AFTER INSERT OR UPDATE OR DELETE ON hospitalflow.work_tasks FOR EACH ROW EXECUTE FUNCTION hospitalflow.record_row_history();
REVOKE ALL ON hospitalflow.email_changes,hospitalflow.work_tasks FROM PUBLIC;
