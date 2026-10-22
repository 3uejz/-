#!/usr/bin/env bash
# 用 Godot 4.7.2 编辑器打开客户端工程。
# 用法：bash scripts/dev-client.sh [额外参数]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$ROOT/.toolchain/godot}"

if [ ! -x "$GODOT_BIN" ]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	else
		echo "缺少 Godot 4.7.2：$GODOT_BIN" >&2
		echo "请把引擎放到 .toolchain/godot，或设置 GODOT_BIN。" >&2
		exit 1
	fi
fi

exec "$GODOT_BIN" --path "$ROOT/client" --editor "$@"
