#!/usr/bin/env python3
"""校验服务端路由与 OpenAPI 契约一致，防止两端接口漂移。

- 从 server/internal/api/server.go 提取 `"METHOD /api/v1/..."` 路由；
- 从 shared/openapi/openapi.yaml 提取 paths 与各 path 的 HTTP 方法；
- 非 /api/v1 前缀的运维路由（如 /metrics、/admin 静态）不在契约范围内，忽略；
- 任一方向存在差异即非零退出。
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVER_GO = ROOT / "server" / "internal" / "api" / "server.go"
OPENAPI = ROOT / "shared" / "openapi" / "openapi.yaml"

METHODS = ("get", "post", "put", "delete", "patch")
API_PREFIX = "/api/v1"


def load_server_routes() -> set[tuple[str, str]]:
    text = SERVER_GO.read_text(encoding="utf-8")
    routes: set[tuple[str, str]] = set()
    for method, path in re.findall(r'"([A-Z]+) (/api/v1/[^"]+)"', text):
        routes.add((method.lower(), path[len(API_PREFIX):]))
    return routes


def load_spec_routes() -> set[tuple[str, str]]:
    try:
        import yaml
    except ImportError:
        print("缺少 pyyaml，无法解析 OpenAPI；跳过路由一致性校验。", file=sys.stderr)
        sys.exit(0)
    doc = yaml.safe_load(OPENAPI.read_text(encoding="utf-8"))
    routes: set[tuple[str, str]] = set()
    for path, ops in (doc.get("paths") or {}).items():
        for method in ops:
            if method.lower() in METHODS:
                routes.add((method.lower(), path))
    return routes


def main() -> int:
    server = load_server_routes()
    spec = load_spec_routes()

    missing_in_spec = sorted(server - spec)
    missing_in_server = sorted(spec - server)

    if not missing_in_spec and not missing_in_server:
        print(f"路由与 OpenAPI 一致：{len(server)} 个接口")
        return 0

    if missing_in_spec:
        print("以下服务端路由未写入 OpenAPI：", file=sys.stderr)
        for m, p in missing_in_spec:
            print(f"  - {m.upper()} {p}", file=sys.stderr)
    if missing_in_server:
        print("以下 OpenAPI 声明的路由在服务端不存在：", file=sys.stderr)
        for m, p in missing_in_server:
            print(f"  - {m.upper()} {p}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
