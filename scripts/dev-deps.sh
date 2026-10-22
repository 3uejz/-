#!/usr/bin/env bash
# 本地依赖服务管理：PostgreSQL / Redis / MinIO 容器。
# 用法：bash scripts/dev-deps.sh start|stop|status|logs
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/deploy/.env"
ACTION="${1:-status}"

if [ ! -f "$ENV_FILE" ]; then
	echo "缺少 $ENV_FILE，请先运行：bash scripts/dev-setup.sh" >&2
	exit 1
fi

compose=(docker compose --env-file "$ENV_FILE" -f "$ROOT/deploy/docker-compose.yml")

case "$ACTION" in
start)
	"${compose[@]}" up -d postgres redis minio
	"${compose[@]}" up minio-init
	;;
stop)
	"${compose[@]}" stop
	;;
status)
	"${compose[@]}" ps
	;;
logs)
	"${compose[@]}" logs --tail=200
	;;
*)
	echo "用法：$0 start|stop|status|logs" >&2
	exit 1
	;;
esac
