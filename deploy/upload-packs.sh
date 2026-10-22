#!/bin/sh
# 把 contentbuilder 产物按清单版本上传到 S3 兼容存储。
# 用法：upload-packs.sh <manifest.json> <build-dir> <alias/bucket>
# 例：upload-packs.sh build/content/manifest.json build/content lifetext/lifetext
set -eu

if [ "$#" -ne 3 ]; then
  echo "用法: $0 <manifest.json> <build-dir> <alias/bucket>" >&2
  exit 2
fi
MANIFEST=$1
BUILD_DIR=$2
TARGET=${3%/}

for bin in mc python3 sha256sum; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "缺少命令: $bin" >&2
    exit 1
  }
done
[ -f "$MANIFEST" ] || {
  echo "清单不存在: $MANIFEST" >&2
  exit 1
}

python3 - "$MANIFEST" "$BUILD_DIR" "$TARGET" <<'PY' | while IFS="$(printf '\t')" read -r src dst hash; do
import json
import sys
from pathlib import Path

manifest_path, build_dir, target = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
for pack in manifest.get("packs", []):
    name = pack["name"]
    version = pack["version"]
    src = build_dir / f"{name}.ltpack"
    dst = f"{target}/packs/{name}/{version}.ltpack"
    print(f"{src}\t{dst}\t{pack['hash']}")
PY
  [ -f "$src" ] || {
    echo "内容包不存在: $src" >&2
    exit 1
  }
  actual="sha256:$(sha256sum "$src" | cut -d' ' -f1)"
  if [ "$actual" != "$hash" ]; then
    echo "哈希不一致: $src" >&2
    echo "  期望 $hash" >&2
    echo "  实际 $actual" >&2
    exit 1
  fi
  echo "上传 $src -> $dst"
  mc cp "$src" "$dst"
done

echo "上传清单 -> $TARGET/manifests/manifest.json"
mc cp "$MANIFEST" "$TARGET/manifests/manifest.json"
echo "完成"
