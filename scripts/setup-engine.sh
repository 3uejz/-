#!/usr/bin/env bash
# 拉取引擎源码到 engine/。默认使用本项目的 Godot fork（lifetext 分支，
# 基于官方 4.7.2-stable），以便承载 engine-modules/ 的 overlay 模块。
# 需要临时切回官方源码时用环境变量覆盖：
#   GODOT_REPO=https://github.com/godotengine/godot.git GODOT_TAG=4.7.2-stable bash scripts/setup-engine.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_DIR="$ROOT/engine"
GODOT_REPO="${GODOT_REPO:-https://github.com/3uejz/godot.git}"
GODOT_TAG="${GODOT_TAG:-lifetext}"

if [ -d "$ENGINE_DIR/.git" ]; then
	echo "engine/ 已存在，跳过克隆：$ENGINE_DIR"
else
	echo "克隆引擎源码：$GODOT_REPO @ $GODOT_TAG"
	git clone --depth 1 --branch "$GODOT_TAG" "$GODOT_REPO" "$ENGINE_DIR"
fi

echo "引擎源码就绪：$ENGINE_DIR"
echo "下一步：bash scripts/build-engine.sh editor"
