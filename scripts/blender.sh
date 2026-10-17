#!/usr/bin/env bash
# Blender LTS 包装器：统一入口，避免脚本散落绝对路径。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${BLENDER_BIN:-}" ]; then
  BLENDER_BIN="$(ls -d "$ROOT"/.toolchain/blender-*/blender 2>/dev/null | head -n1 || true)"
fi

if [ -z "$BLENDER_BIN" ] || [ ! -x "$BLENDER_BIN" ]; then
  echo "Blender 未安装：请先运行 bash scripts/setup-blender.sh" >&2
  exit 1
fi

exec "$BLENDER_BIN" "$@"
