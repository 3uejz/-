#!/usr/bin/env bash
# 本地服务管理：PostgreSQL 与 Redis（容器内无 systemd，用 pg_ctlcluster / redis-server）
set -u
action="${1:-status}"

start() {
  if command -v redis-server >/dev/null 2>&1; then
    redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes
    echo "redis: $(redis-cli ping 2>/dev/null || echo down)"
  fi
  if command -v pg_ctlcluster >/dev/null 2>&1; then
    pg_lsclusters 2>/dev/null | tail -n +2 | while read -r ver name _rest; do
      pg_ctlcluster "$ver" "$name" start 2>/dev/null || true
    done
    echo "postgres:"; pg_lsclusters 2>/dev/null || true
  fi
}

stop() {
  redis-cli shutdown nosave >/dev/null 2>&1 || true
  if command -v pg_ctlcluster >/dev/null 2>&1; then
    pg_lsclusters 2>/dev/null | tail -n +2 | while read -r ver name _rest; do
      pg_ctlcluster "$ver" "$name" stop 2>/dev/null || true
    done
  fi
}

status() {
  echo "redis: $(redis-cli ping 2>/dev/null || echo down)"
  command -v pg_lsclusters >/dev/null 2>&1 && pg_lsclusters 2>/dev/null || echo "postgres: n/a"
}

case "$action" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  *) echo "用法: $0 start|stop|status"; exit 1 ;;
esac
