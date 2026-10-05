# content/ — 内容源

职业、技能、物品、事件、地图、异常等内容的源数据，由 `tools/contentbuilder` 校验、打包为轻量二进制内容包（`.ltpack`）并生成 `manifest.json` 差量清单。

内容全表见 `当前工作区/.monkeycode/specs/life-text-sandbox/content-catalog.md`。

## 目录

- `catalog/`：按类别拆分的源数据，支持 JSON（`<category>.json`）与 CSV（`<category>.csv`）。
  - JSON 结构：`{ "category": "<name>", "entries": [ { "content_key": "...", ... } ] }`
  - `content_key` 为稳定主键（点分小写，如 `occupation.engineer`），全局唯一，存档一律引用它。
  - 类别字段 schema 与跨引用规则定义于 `当前工作区/tools/contentbuilder/schema.go`。

## 已建类别骨架

jobs、skills、items、certificates、diseases、finance、events、achievements、codex、manufacturing、activities、entertainment、transport、awards、organizations、languages、festivals、anomalies。

## 构建与校验

```bash
cd tools/contentbuilder
go run . validate --catalog ../../content/catalog
go run . build --catalog ../../content/catalog --out ../../build/content
```

`validate` 为硬阻断式校验：必填字段、类型、`content_key` 格式与全局重复、跨类别引用完整性（如 `jobs.skills` → `skills`）、`name`（i18n 键）非空，错误精确到 `文件#content_key`。

> 内容填充（职业 200、技能 140、物品 1000 等）按 `content-catalog.md` 逐步补齐，不阻塞管线。
