CREATE TABLE IF NOT EXISTS accounts (
    id            text PRIMARY KEY,
    username      text NOT NULL UNIQUE,
    password_hash text NOT NULL,
    role          text NOT NULL DEFAULT 'player',
    created_at    timestamptz NOT NULL DEFAULT now()
);
