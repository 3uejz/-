#!/usr/bin/env bash
# 本地开发一键准备：生成 deploy/.env、启动依赖容器、拉取 Go/Node 依赖。
# 用法：bash scripts/dev-setup.sh [--check]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/deploy/.env"
GODOT_BIN="${GODOT_BIN:-$ROOT/.toolchain/godot}"
MODE="${1:-}"

missing=0
need_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "缺少命令：$1"
		missing=1
	fi
}

need_cmd docker
need_cmd go
need_cmd node
need_cmd npm
need_cmd python3

if [ ! -x "$GODOT_BIN" ] && ! command -v godot >/dev/null 2>&1; then
	echo "缺少 Godot 4.7.2：$GODOT_BIN"
	echo "可从 .toolchain/godot 复制，或设置 GODOT_BIN 指向引擎二进制。"
	missing=1
fi

if [ "$missing" -ne 0 ]; then
	echo "请先安装缺少的工具后重试。"
	exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
	echo "缺少 Docker Compose 插件（docker compose）。"
	exit 1
fi
if ! docker info >/dev/null 2>&1; then
	echo "Docker 守护进程未运行，或当前用户没有访问权限。"
	exit 1
fi

if [ "$MODE" = "--check" ]; then
	echo "本地开发依赖检查通过。"
	exit 0
fi

if [ ! -f "$ENV_FILE" ]; then
	cp "$ROOT/deploy/.env.example" "$ENV_FILE"
	python3 - "$ENV_FILE" "$ROOT/.data/minio" <<'PY'
import pathlib
import re
import secrets
import sys

path = pathlib.Path(sys.argv[1])
data_dir = sys.argv[2]
text = path.read_text()
values = {
    "JWT_SECRET": secrets.token_hex(32),
    "ADMIN_PASSWORD": secrets.token_hex(16),
    "POSTGRES_PASSWORD": secrets.token_hex(16),
    "MINIO_ROOT_PASSWORD": secrets.token_hex(20),
    "OBJECT_SECRET_KEY": secrets.token_hex(20),
    "CI_SECRET_KEY": secrets.token_hex(20),
    "MINIO_DATA_DIR": data_dir,
}
for key, value in values.items():
    text = re.sub(rf"(?m)^{re.escape(key)}=.*$", f"{key}={value}", text)
path.write_text(text)
PY
	chmod 600 "$ENV_FILE"
	echo "已生成 $ENV_FILE（本地随机密钥，勿提交）。"
else
	echo "沿用已有 $ENV_FILE。"
fi

mkdir -p "$ROOT/.data/minio" "$ROOT/.data/server" "$ROOT/.data/backups"

compose=(docker compose --env-file "$ENV_FILE" -f "$ROOT/deploy/docker-compose.yml")
echo "== 启动 PostgreSQL / Redis / MinIO =="
"${compose[@]}" up -d postgres redis minio
echo "== 初始化 MinIO 桶与账号 =="
"${compose[@]}" up minio-init

echo "== 下载 Go 依赖 =="
(cd "$ROOT/server" && go mod download)
(cd "$ROOT/tools/contentbuilder" && go mod download)
(cd "$ROOT/tools/genbaseline" && go mod download)

if [ ! -d "$ROOT/admin/node_modules" ]; then
	echo "== 安装管理端依赖 =="
	(cd "$ROOT/admin" && npm ci)
fi

echo
echo "本地开发环境已就绪："
echo "  后端：bash scripts/dev-server.sh"
echo "  管理端：bash scripts/dev-web.sh"
echo "  客户端：bash scripts/dev-client.sh"
echo "  测试：bash scripts/test.sh"
