CREATE TABLE IF NOT EXISTS save_versions (
    account_id     text NOT NULL,
    slot           integer NOT NULL,
    version        integer NOT NULL,
    hash           text NOT NULL,
    playthrough_id text NOT NULL DEFAULT '',
    object_key     text NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, slot, version)
);
