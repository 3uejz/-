CREATE TABLE IF NOT EXISTS legacy_docs (
    account_id text PRIMARY KEY,
    doc        bytea NOT NULL,
    version    integer NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT now()
);
