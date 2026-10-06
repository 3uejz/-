CREATE TABLE IF NOT EXISTS telemetry_events (
    event_id    text PRIMARY KEY,
    account_id  text NOT NULL DEFAULT '',
    event_type  text NOT NULL,
    occurred_at timestamptz NOT NULL,
    payload     jsonb NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
