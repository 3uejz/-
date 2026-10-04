#!/usr/bin/env bash
# 运行客户端与后端的测试，含跨语言一致性测试。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/workspace/.toolchain/godot}"
GO_BIN="${GO_BIN:-/usr/local/go/bin/go}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

echo "== 共享 schema 校验 =="
"$PYTHON_BIN" "$ROOT/scripts/validate_schemas.py"

echo "== Godot 客户端测试 =="
# 先导入以生成全局类缓存与资源索引（.godot/ 不入库，CI 首次运行必需）
"$GODOT_BIN" --headless --path "$ROOT/client" --import >/dev/null 2>&1 || true
for t in "$ROOT"/client/tests/*_test.gd; do
  name="$(basename "$t")"
  echo "-- $name"
  "$GODOT_BIN" --headless --path "$ROOT/client" --script "res://tests/$name"
done

echo "== Go 后端测试 =="
(
  cd "$ROOT/server"
  "$GO_BIN" test ./...
)

echo "== 全部测试通过 =="
