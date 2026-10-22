#!/usr/bin/env bash
# 本地启动 Go 后端：读取 deploy/.env，把容器服务地址改成 127.0.0.1。
# 用法：bash scripts/dev-server.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/deploy/.env}"
GO_BIN="${GO_BIN:-go}"

if [ ! -f "$ENV_FILE" ]; then
	echo "缺少 $ENV_FILE，请先运行：bash scripts/dev-setup.sh" >&2
	exit 1
fi

set -a
. "$ENV_FILE"
set +a

if [ "${JWT_SECRET:-}" = "replace-with-at-least-32-bytes" ] || [ "${POSTGRES_PASSWORD:-}" = "replace-with-a-strong-password" ]; then
	echo "$ENV_FILE 仍是模板占位值，请先运行：bash scripts/dev-setup.sh" >&2
	exit 1
fi

mkdir -p "$ROOT/.data/server" "$ROOT/.data/backups"

export SERVER_ADDR="${SERVER_ADDR:-127.0.0.1:8080}"
export DATABASE_URL="${DEV_DATABASE_URL:-postgres://${POSTGRES_USER:-life}:${POSTGRES_PASSWORD}@127.0.0.1:5432/${POSTGRES_DB:-life}?sslmode=disable}"
export REDIS_URL="${DEV_REDIS_URL:-redis://127.0.0.1:6379}"
export OBJECT_ENDPOINT="${DEV_OBJECT_ENDPOINT:-127.0.0.1:9000}"
export OBJECT_USE_SSL="${DEV_OBJECT_USE_SSL:-false}"
export OBJECT_CREATE_BUCKET="${DEV_OBJECT_CREATE_BUCKET:-false}"
export DATA_DIR="${DATA_DIR:-$ROOT/.data/server}"
export BACKUP_DIR="${BACKUP_DIR:-$ROOT/.data/backups}"
export ADMIN_DIR="${ADMIN_DIR:-$ROOT/admin/dist}"

cd "$ROOT/server"
exec "$GO_BIN" run ./cmd/server
