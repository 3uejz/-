#!/usr/bin/env bash
# 应用核心 patch 并以 overlay 模块构建引擎。
# 用法：
#   bash scripts/build-engine.sh editor            # 编辑器（可 --headless 运行）
#   bash scripts/build-engine.sh headless          # 同 editor，用于服务器/CI
#   bash scripts/build-engine.sh template_release  # 导出模板
#   PLATFORM=windows bash scripts/build-engine.sh template_release
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_DIR="$ROOT/engine"
MODULES_DIR="$ROOT/engine-modules"
PATCHES_DIR="$ROOT/engine-patches"

TARGET="${1:-editor}"
PLATFORM="${PLATFORM:-linuxbsd}"
SCONS="${SCONS_BIN:-scons}"
if command -v nproc >/dev/null 2>&1; then
	JOBS="${JOBS:-$(nproc)}"
else
	JOBS="${JOBS:-4}"
fi

if [ ! -d "$ENGINE_DIR/.git" ]; then
	echo "缺少 engine/ 源码，请先运行：bash scripts/setup-engine.sh" >&2
	exit 1
fi
if ! command -v "$SCONS" >/dev/null 2>&1; then
	echo "缺少 scons。请安装：python3 -m pip install 'scons>=4.8'" >&2
	exit 1
fi

# 应用核心 patch（按文件名顺序，可为空）。
shopt -s nullglob
patches=("$PATCHES_DIR"/*.patch)
shopt -u nullglob
for patch_file in "${patches[@]}"; do
	echo "应用 patch：$(basename "$patch_file")"
	git -C "$ENGINE_DIR" apply --3way "$patch_file"
done

common_args=(platform="$PLATFORM" custom_modules="$MODULES_DIR" -j"$JOBS")

case "$TARGET" in
editor | headless)
	"$SCONS" -C "$ENGINE_DIR" target=editor "${common_args[@]}"
	;;
template_release | template)
	"$SCONS" -C "$ENGINE_DIR" target=template_release "${common_args[@]}"
	;;
template_debug)
	"$SCONS" -C "$ENGINE_DIR" target=template_debug "${common_args[@]}"
	;;
*)
	echo "未知目标：$TARGET（可选：editor headless template_release template_debug）" >&2
	exit 1
	;;
esac

echo "构建完成：target=$TARGET platform=$PLATFORM"
