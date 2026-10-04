#!/usr/bin/env python3
"""共享 JSON Schema 完整性校验。

校验 shared/schemas/ 下每个 schema：
  1. JSON 语法合法；
  2. 顶层为对象且含 $schema / $id；
  3. 所有 $ref（本地 #/$defs/... 与跨文件 file.json#/...）均可解析。

只用标准库，不依赖网络或第三方包，可接入 CI 与 scripts/test.sh。
退出码：0 全部通过，1 存在错误。
"""

from __future__ import annotations

import glob
import json
import os
import sys
from typing import Any

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA_DIR = os.path.join(REPO_ROOT, "shared", "schemas")
DRAFT_2020_12 = "https://json-schema.org/draft/2020-12/schema"


def unescape(part: str) -> str:
    return part.replace("~1", "/").replace("~0", "~")


def resolve_pointer(doc: Any, pointer: str) -> bool:
    """解析 JSON Pointer（不含前导 #），存在返回 True。"""
    cur = doc
    for raw in pointer.strip("/").split("/") if pointer.strip("/") else []:
        part = unescape(raw)
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        elif isinstance(cur, list) and part.isdigit() and int(part) < len(cur):
            cur = cur[int(part)]
        else:
            return False
    return True


def iter_refs(node: Any):
    if isinstance(node, dict):
        if isinstance(node.get("$ref"), str):
            yield node["$ref"]
        for value in node.values():
            yield from iter_refs(value)
    elif isinstance(node, list):
        for value in node:
            yield from iter_refs(value)


def validate_top(name: str, doc: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(doc, dict):
        return [f"{name}: 顶层必须是对象"]
    if doc.get("$schema") != DRAFT_2020_12:
        errors.append(f"{name}: $schema 必须为 {DRAFT_2020_12}")
    if not doc.get("$id"):
        errors.append(f"{name}: 缺少 $id")
    return errors


def validate_refs(name: str, doc: Any, docs: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for ref in iter_refs(doc):
        if ref.startswith("#"):
            if not resolve_pointer(doc, ref[1:]):
                errors.append(f"{name}: 本地 $ref 无法解析：{ref}")
            continue
        target_file, _, fragment = ref.partition("#")
        if target_file not in docs:
            errors.append(f"{name}: 跨文件 $ref 目标缺失：{ref}")
            continue
        if fragment and not resolve_pointer(docs[target_file], fragment):
            errors.append(f"{name}: 跨文件 $ref 片段无法解析：{ref}")
    return errors


def main() -> int:
    if not os.path.isdir(SCHEMA_DIR):
        print(f"[schema] 目录不存在：{SCHEMA_DIR}", file=sys.stderr)
        return 1

    paths = sorted(glob.glob(os.path.join(SCHEMA_DIR, "*.json")))
    if not paths:
        print("[schema] 未找到任何 schema", file=sys.stderr)
        return 1

    docs: dict[str, Any] = {}
    errors: list[str] = []

    # 第一遍：语法；坏文件不入 docs，后续引用它即报缺失。
    for path in paths:
        name = os.path.basename(path)
        try:
            with open(path, encoding="utf-8") as handle:
                docs[name] = json.load(handle)
        except json.JSONDecodeError as exc:
            errors.append(f"{name}: JSON 语法错误：{exc}")

    # 第二遍：逐文件顶层约定与 $ref 解析，PASS/FAIL 各归其位。
    for path in paths:
        name = os.path.basename(path)
        if name not in docs:
            print(f"[schema] {name} FAIL")
            continue
        file_errors = validate_top(name, docs[name]) + validate_refs(name, docs[name], docs)
        if file_errors:
            print(f"[schema] {name} FAIL")
            errors.extend(file_errors)
        else:
            print(f"[schema] {name} PASS")

    if errors:
        print(f"[schema] 发现 {len(errors)} 个错误：", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(f"[schema] 全部通过（{len(docs)} 个 schema）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
