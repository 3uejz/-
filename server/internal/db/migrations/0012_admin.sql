-- 管理后台新增表，对应 admin.md 第 6 节数据模型。
-- 注：0010 的 audit_log 为历史占位，管理后台审计使用本文件的 admin_audit_logs。

CREATE TABLE IF NOT EXISTS admin_audit_logs (
    id               text PRIMARY KEY,
    actor_account_id text NOT NULL,
    action           text NOT NULL,
    target_type      text NOT NULL DEFAULT '',
    target_id        text NOT NULL DEFAULT '',
    before           jsonb NOT NULL DEFAULT '{}'::jsonb,
    after            jsonb NOT NULL DEFAULT '{}'::jsonb,
    result           text NOT NULL DEFAULT 'ok',
    ip               text NOT NULL DEFAULT '',
    user_agent       text NOT NULL DEFAULT '',
    created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS admin_audit_logs_created_idx ON admin_audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS admin_audit_logs_action_idx ON admin_audit_logs (action);

CREATE TABLE IF NOT EXISTS content_releases (
    id               text PRIMARY KEY,
    pack_name        text NOT NULL,
    pack_version     text NOT NULL,
    strategy         text NOT NULL DEFAULT 'all',
    rollout_percent  int NOT NULL DEFAULT 100,
    account_list     jsonb NOT NULL DEFAULT '[]'::jsonb,
    status           text NOT NULL DEFAULT 'rolling',
    manifest_version int NOT NULL DEFAULT 0,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS config_versions (
    id         text PRIMARY KEY,
    version    int NOT NULL UNIQUE,
    values     jsonb NOT NULL DEFAULT '{}'::jsonb,
    revision   int NOT NULL,
    created_by text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS announcements (
    id           text PRIMARY KEY,
    title        text NOT NULL,
    body         text NOT NULL DEFAULT '',
    audience     text NOT NULL DEFAULT 'all',
    account_list jsonb NOT NULL DEFAULT '[]'::jsonb,
    start_at     timestamptz,
    end_at       timestamptz,
    status       text NOT NULL DEFAULT 'draft',
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
