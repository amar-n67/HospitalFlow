CREATE TABLE hospitalflow.idempotency_hash_keys(
 id smallint PRIMARY KEY CHECK(id=1), secret bytea NOT NULL CHECK(octet_length(secret)=32));
