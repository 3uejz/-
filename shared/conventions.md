# 共享约定（client / server）

本文件是《浮生录》客户端（GDScript）与后端（Go）之间的**单一事实来源**之一，定义 ID、时间、命名、金额、错误码、分页、鉴权等横切约定。所有 Schema 与 OpenAPI 均遵循本文件。

- 版本：`/api/v1`
- 编码：`application/json; charset=utf-8`，支持 `gzip`
- 相关文件：
  - `schemas/*.schema.json`：JSON Schema 2020-12，数据结构定义
  - `openapi/openapi.yaml`：OpenAPI 3.1，REST 接口定义
  - `consistency/`：跨语言一致性测试向量
  - `../.monkeycode/specs/life-text-sandbox/design.md`：系统语义与数值基线

## 1. 版本策略

- REST 前缀固定为 `/api/v1`。
- 破坏性变更升版本号（`/api/v2`）；向后兼容的新增字段不升版本。
- 响应头返回 `X-Api-Version: 1`。
- 内容包、存档、协议各自独立版本：
  - 内容包：`content_version`（整数递增）
  - 存档：`schema_version`（整数递增，驱动迁移）
  - 协议：`/api/v1`

## 2. ID 约定

- 所有实体 ID 使用 **UUIDv7**（时间有序），以字符串表示，36 字符小写带连字符。
- 客户端本地新建、离线创建的实体同样生成 UUIDv7，联网合并时不冲突。
- 玩家账号 ID、存档 ID、传承 ID、NPC ID、事件实例 ID 全部采用 UUIDv7。
- 例外：内容条目的稳定标识使用**内容键**（`content_key`，如 `occupation.engineer`、`item.phone.smart`），源自内容包，非 UUID；存档中引用内容一律用 `content_key`。

## 3. 时间约定

- 传输时间：UTC，RFC3339 / ISO8601，带 `Z`，秒级或毫秒级（示例 `2026-10-04T07:35:00Z`）。
- 世界时间：以**绝对分钟**（`absolute_minutes`，自世界纪元起的整数分钟）为唯一权威，跨端一致。
- 派生字段（年/月/日/星期/季节/昼夜）由绝对分钟按**真实公历**计算，不单独存储，避免漂移（见 design「全局数值基线·时间」）。
- 时长：整数分钟，字段名以 `_minutes` 结尾。
- 时区：世界采用多国设定，但存储统一 UTC；展示层再按地点时区换算。

## 4. 字段命名与类型

- 字段名统一 `snake_case`。
- 布尔用 `true/false`；禁止用 `0/1`。
- 金额（`money`）：对象 `{ "amount": <integer 最小货币单位>, "currency": "<ISO 4217>" }`；不用浮点表示货币本体。
- 比例/概率：用 `0..1` 的浮点或整数基点（`_bps`，万分之几）；在 Schema 中标注含义。
- 属性/关系/技能：区间见 design 全局数值基线（属性 `0..100`、关系含负区间、技能 `0..20`）。
- 枚举：字符串小写下划线；新增值视为兼容变更，客户端须忽略未知值。
- 可选字段省略而非置 `null`；`null` 仅用于确实需要表达空语义的场景。
- 未知字段：客户端与后端均须容忍并忽略未知字段（向前兼容）。
- 数组：无特殊说明时不保证有序；有序列表字段以 `_ordered` 后缀或明确说明。

## 5. 鉴权

- 登录返回 **access token（JWT）** 与 **refresh token**。
  - access：JWT，短期（默认 30 分钟），`Authorization: Bearer <token>`。
  - refresh：不透明随机串，长期（默认 30 天），存 Redis，可撤销；仅用于 `/api/v1/auth/refresh`。
- 刷新采用**轮换**：每次刷新签发新 refresh 并作废旧的；检测到旧 token 重放即撤销该设备全部会话。
- JWT 声明：`sub`（账号 UUID）、`iat`、`exp`、`jti`、`ver`（令牌版本，改密后递增使旧 token 失效）。
- 登出撤销当前 refresh；改密撤销该账号全部 refresh。
- 离线：客户端可在无网络下完整游玩；遥测与云同步事件本地缓存，恢复后补传。
- 权限：账号为普通玩家；`/api/v1/admin/*` 需 `role=admin`。

## 6. 错误模型

统一错误体：

```json
{
  "code": "SAVE_VERSION_UNSUPPORTED",
  "message": "存档 schema 版本过新，请升级客户端",
  "details": { "schema_version": 9, "supported": 7 },
  "request_id": "018f...uuidv7..."
}
```

- `code`：机器可读，稳定不变，见下表。
- `message`：面向用户/开发者的中文可读文本，可本地化。
- `details`：可选，结构化上下文。
- `request_id`：服务端生成的追踪 ID，日志可检索。
- HTTP 状态码与业务错误码解耦：同一 HTTP 状态可对应多业务码。

| 错误码 | HTTP | 含义 |
|--------|------|------|
| `VALIDATION_FAILED` | 400 | 请求体/参数校验失败 |
| `UNAUTHENTICATED` | 401 | 缺少或无效 access token |
| `TOKEN_EXPIRED` | 401 | access 过期，需刷新 |
| `FORBIDDEN` | 403 | 无权限（如非 admin） |
| `NOT_FOUND` | 404 | 资源不存在 |
| `CONFLICT` | 409 | 通用冲突 |
| `SAVE_VERSION_UNSUPPORTED` | 409 | 存档 schema 版本不支持 |
| `SAVE_CONFLICT` | 409 | 本地/云端存档冲突，需玩家选择 |
| `SAVE_HASH_MISMATCH` | 409 | 存档哈希校验失败 |
| `CONTENT_VERSION_UNSUPPORTED` | 409 | 内容版本不兼容 |
| `IDEMPOTENCY_REPLAY` | 409 | 幂等键重复，返回首次结果 |
| `RATE_LIMITED` | 429 | 触发限流/配额 |
| `INTERNAL` | 500 | 服务端内部错误 |
| `UPSTREAM_UNAVAILABLE` | 503 | 依赖不可用（如对象存储/DB） |

## 7. 分页、幂等与并发

- 列表分页采用**游标**：请求 `?limit=<1..200>&cursor=<opaque>`，响应 `{ "items": [...], "next_cursor": "..." | null }`。
- 不提供 offset 分页（避免深层翻页性能问题）。
- 写操作幂等：客户端可携带 `Idempotency-Key: <UUIDv7>`，服务端在 24h 窗口内按键去重，重复请求返回首次结果并置 `IDEMPOTENCY_REPLAY`。
- 并发更新（存档、配置）使用**乐观锁**：`ETag` 或 `expected_version` 字段；不匹配返回 `409 CONFLICT` 与最新摘要。

## 8. 缓存与条件请求

- 内容清单、远程配置返回 `ETag`；客户端可带 `If-None-Match`，服务端返回 `304`。
- 内容包与存档走对象存储签名 URL 下载，URL 有过期时间；下载后校验 `sha256`。

## 9. 幂等与离线补传语义

- 遥测事件：客户端生成 UUIDv7 `event_id`，服务端按 `event_id` 去重。
- 批量上报：`POST /api/v1/telemetry/events`，请求体为事件数组，响应逐条返回接收结果；失败项客户端保留重试。
- 存档同步：以分块（`player`/`world`/`history`）哈希对齐，仅上传变动块；冲突按 design「存档 Schema 与体积」处理。

## 10. 内容键与命名空间

内容键格式：`<domain>.<name>[.<sub>]`，全小写点分，例如：

- `occupation.engineer`
- `skill.cooking`
- `item.food.rice`
- `event.random.windfall`
- `disease.mental.depression`
- `goldfinger.info.appraisal`

约束：全局唯一、稳定不随版本改变；废弃只标记不删除，避免存档引用失效。
