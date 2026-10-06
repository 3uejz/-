CREATE TABLE IF NOT EXISTS save_slots (
    account_id     text NOT NULL,
    slot           integer NOT NULL,
    latest_version integer NOT NULL,
    hash           text NOT NULL,
    playthrough_id text NOT NULL DEFAULT '',
    idem_key       text NOT NULL DEFAULT '',
    updated_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, slot)
);
