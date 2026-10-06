CREATE TABLE IF NOT EXISTS audit_log (
    id         bigserial PRIMARY KEY,
    actor_id   text NOT NULL DEFAULT '',
    action     text NOT NULL,
    target     text NOT NULL DEFAULT '',
    detail     jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
