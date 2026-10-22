#!/usr/bin/env bash
# 本地启动 React 管理后台，/api 由 Vite 代理到 127.0.0.1:8080。
# 用法：bash scripts/dev-web.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/admin"
exec npm run dev -- --host 127.0.0.1
