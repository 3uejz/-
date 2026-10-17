#!/usr/bin/env bash
# 安装定点版本 Blender LTS 到 .toolchain/（不入库），供 tools/meshgen 生成 3D 模型。
# 用法：bash scripts/setup-blender.sh [版本号]
#   默认 4.5.14；设置 BLENDER_VERSION 或传参可覆盖。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${BLENDER_VERSION:-4.5.14}}"
DEST="$ROOT/.toolchain/blender-$VERSION-linux-x64"
TARBALL="$ROOT/.toolchain/downloads/blender-$VERSION-linux-x64.tar.xz"
URL="https://download.blender.org/release/Blender${VERSION%.*}/blender-$VERSION-linux-x64.tar.xz"

if [ -x "$DEST/blender" ]; then
  echo "Blender 已安装：$DEST"
  "$DEST/blender" --version | head -1
  exit 0
fi

mkdir -p "$ROOT/.toolchain/downloads"
if [ ! -f "$TARBALL" ]; then
  echo "下载 $URL"
  curl -fL --retry 3 --max-time 1500 -o "$TARBALL" "$URL"
fi

echo "解压到 $ROOT/.toolchain/"
tar -xJf "$TARBALL" -C "$ROOT/.toolchain/"
"$DEST/blender" --version | head -1
if ldd "$DEST/blender" 2>/dev/null | grep -q "not found"; then
  echo "警告：Blender 缺少运行库，headless 同样需要 X11/GL 库。" >&2
  echo "  apt-get install -y libx11-6 libxi6 libxxf86vm1 libxfixes3 libxrender1 libgl1 libegl1 libxkbcommon0 libsm6 libice6 libxcb1 libxcb-glx0 libxcb-shm0 libxcb-sync1 libxcb-present0 libxcb-dri2-0 libxcb-dri3-0" >&2
fi
echo "完成。运行 bash scripts/blender.sh --version 验证。"
