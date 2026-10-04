# 浮生录 — 管理后台（admin）技术设计

> 对应需求 R38、R39；实施任务 `tasklist.md` 第 25 项。本文件是管理后台的单一真源，`design.md`「后端运营」只保留索引。

## 1. 定位与范围

- 单机单实例私有部署，面向开发者自用（单管理员）。
- 权限模型：**单管理员**，复用账号体系；账号 `is_admin=true` 即具后台权限，不另建登录系统。
- 首发做满 **11 个模块**：登录与鉴权、仪表盘、账号与设备、存档运维、内容管理、远程配置、公告、遥测与统计、审计日志、运营助手（预留）、系统运维。
- 首发不做多角色 RBAC；后台界面仅中文。
- 前端 React 18 + Ant Design 5 + Vite + TypeScript；构建产物由 Go 服务**同源静态托管**于 `/admin`（天然免 CORS）。

## 2. 技术架构与工程结构

### 2.1 技术栈

| 层 | 选型 |
|----|------|
| 构建 | Vite |
| 框架 | React 18 + TypeScript |
| UI | Ant Design 5 + @ant-design/charts |
| 路由 | React Router v6 |
| 数据请求 | TanStack Query v5 |
| 轻量状态 | Zustand |
| HTTP | 原生 fetch 统一封装 |

### 2.2 目录结构

```
admin/
├── src/
│   ├── api/          # 请求封装与各域 API 客户端
│   ├── components/   # 通用组件（表格、抽屉、确认弹窗、脱敏展示）
│   ├── features/     # 按业务域聚合的查询与表单逻辑
│   ├── pages/        # 路由页面，按 11 模块分目录
│   ├── router/       # 路由表与守卫
│   ├── store/        # Zustand：会话、当前用户、主题
│   ├── theme/        # AntD 主题 token
│   └── utils/        # 格式化、错误处理、导出
├── vite.config.ts    # dev proxy /api → Go；allowedHosts 含 .monkeycode-ai.online
└── package.json
```

### 2.3 请求层与鉴权

- 统一 `apiFetch`：基址 `/api/v1`，自动注入 `Authorization: Bearer <access JWT>`。
- 401：用 refresh token 轮换后重试一次；仍失败则跳登录。
- 403：提示无后台权限并登出。
- 错误体对齐 `shared/schemas/common.schema.json` 的 `error`：`{ code, message, details?, request_id }`；UI 用 `request_id` 便于排查。
- 登录复用 `POST /api/v1/auth/login`；登录后由 `GET /api/v1/admin/me` 校验 `is_admin`，非管理员拒绝进入。
- 路由守卫：未登录跳登录页；已登录非 admin 展示无权限页。

### 2.4 部署与本地开发

- 构建：`npm run build` → 产物输出到 Go 可托管的静态目录，由 Go 以 `/admin` 前缀提供，含 SPA fallback（未匹配路径回退 `index.html`）。
- 本地开发：Vite dev server 将 `/api` 反向代理到 Go 后端；`server.allowedHosts` 需含 `.monkeycode-ai.online`。
- 静态资源加哈希指纹，`index.html` 不缓存，其余长缓存。

## 3. 权限、审计与安全

- **权限校验**：所有 `/api/v1/admin/*` 端点经 admin 中间件校验 `is_admin`；非管理员一律 403 `FORBIDDEN`。
- **审计日志**：所有写操作（POST/PUT/PATCH/DELETE）自动记录，字段见第 6.1 节；读操作默认不记录，导出与合规删除例外。
- **危险操作**：封禁账号、回滚存档、回滚内容包/配置、清理对象、合规删除等需二次确认，并要求输入目标名称或 ID 方可提交。
- **脱敏**：密钥、令牌等只展示存在性与掩码，绝不返回明文。
- **限流**：admin 端点独立限流，较玩家端更严格；导出与清理类接口额外并发限制。
- **审计不可篡改**：审计表仅追加，后台不提供修改/删除入口。

## 4. 模块详述

### 4.1 登录与鉴权

- 页面：登录表单（账号、密码）、会话过期提示、无权限页。
- 操作：登录、登出（撤销当前 refresh）。
- 数据：`POST /auth/login`、`POST /auth/refresh`、`POST /auth/logout`、`GET /admin/me`。

### 4.2 仪表盘

- 页面：概览卡片 + 趋势图。
- 指标：在线/总账号数、存档总数与存储占用、全球人口与宏观摘要（来自 `worldsim`）、近 7/30 日遥测事件量、备份最近成功时间、服务健康与告警列表。
- 数据：`GET /admin/dashboard/summary`、`GET /healthz`、`GET /admin/system/status`。

### 4.3 账号与设备

- 列表：分页、按账号/邮箱/状态搜索、排序、导出。
- 详情：基本信息、设备列表、存档数、最近登录、创建时间。
- 操作：封禁/解封、吊销指定设备的 refresh、强制登出全部设备。
- 数据：`GET /admin/accounts`、`GET /admin/accounts/{id}`、`POST /admin/accounts/{id}/disable`、`POST /admin/accounts/{id}/enable`、`GET /admin/accounts/{id}/devices`、`POST /admin/accounts/{id}/devices/{device_id}/revoke`。

### 4.4 存档运维

- 列表：按账号/槽位/时间筛选，显示 revision、hash、大小、更新时间。
- 详情：元数据、历史版本、分块信息。
- 操作：下载、回滚到指定版本。**边界（已定）**：后台只读 + 回滚，不在列表单点硬删；删除仅在账号合规注销时级联。
- 存储：占用统计、孤儿对象扫描与清理（需二次确认）。
- 数据：`GET /admin/saves`、`GET /admin/saves/{id}`、`GET /admin/saves/{id}/versions`、`POST /admin/saves/{id}/rollback`、`GET /admin/storage/usage`、`POST /admin/storage/gc`。

### 4.5 内容管理

- 内容包：列表展示 name/kind/version/hash/size/状态；上传、校验、签名。
- 发布（已定支持灰度）：创建发布批次，按账号名单或百分比分批放量，可暂停、继续、全量、回滚到历史版本。
- 校验报告：schema/引用完整性/哈希/依赖检查结果。
- 数据：`GET /admin/content/packs`、`POST /admin/content/packs`、`POST /admin/content/packs/{name}/validate`、`POST /admin/content/publish`、`GET /admin/content/releases`、`POST /admin/content/releases`、`POST /admin/content/releases/{id}/pause`、`POST /admin/content/releases/{id}/resume`、`POST /admin/content/releases/{id}/rollback`。

### 4.6 远程配置

- 编辑器：按点分键分组（`economy.*`、`balance.*`、`cheat.*` 等），支持 JSON 视图与表单视图。
- 版本：每次发布生成版本，支持查看差异、回滚；乐观锁 `revision` 防并发覆盖。
- 数据：`GET /admin/config`、`PUT /admin/config`、`GET /admin/config/versions`、`POST /admin/config/rollback`。

### 4.7 公告

- 列表与编辑：标题、正文（Markdown）、目标人群（全部/指定账号）、起止时间、状态（草稿/已排期/已发布/已下线）。
- 数据：`GET /admin/announcements`、`POST /admin/announcements`、`PUT /admin/announcements/{id}`、`DELETE /admin/announcements/{id}`。

### 4.8 遥测与统计

- 事件目录：列出已上报的 `event_type` 及计数。
- 明细查询：按 event_type/时间/playthrough 过滤，明细保留期默认 90 天。
- 日聚合看板：长期保留的按日聚合趋势（事件量、死亡分布、职业分布、平衡指标等）。
- 人生统计：总收入、总支出、职业轨迹、主要成就（对应 R39.3）。
- 导出与合规删除（记审计）：导出 CSV/JSON，受大小上限约束。
- 数据：`GET /admin/telemetry/events`、`GET /admin/telemetry/aggregates`、`GET /admin/telemetry/life-stats`、`POST /admin/telemetry/export`、`POST /admin/telemetry/purge`。

### 4.9 审计日志

- 列表：按 actor/action/target/时间过滤，展示前后差异。
- 只读；支持导出。
- 数据：`GET /admin/audit-logs`。

### 4.10 运营助手（预留，默认关闭）

- 定位：后台旁路，用于日志摘要、告警聚合、运营问答、内容草稿、异常检测；不参与实时玩法与叙事。
- UI：状态卡（模型是否就绪）、自然语言查询框、草稿生成区、开关。
- 降级：模型缺失/超时/过载时静默降级，主功能不受影响。
- 数据：`GET /admin/assistant/status`、`POST /admin/assistant/query`、`POST /admin/assistant/draft`。

### 4.11 系统运维

- 服务健康：Go/PostgreSQL/Redis/MinIO 状态与关键指标。
- 备份：最近备份记录、手动触发、下载、恢复演练入口。
- 迁移：当前数据库迁移版本，可回滚到上一后端版本（需二次确认）。
- 密钥：仅展示各关键密钥是否存在，缺失时高亮。
- 数据：`GET /admin/system/status`、`GET /admin/system/backups`、`POST /admin/system/backup`、`GET /admin/system/migrations`。

## 5. API 端点总表

前缀 `/api/v1`，Bearer Token，错误体见 `common.schema.json`。

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/admin/me` | 当前管理员信息与权限 |
| GET | `/admin/dashboard/summary` | 仪表盘汇总 |
| GET | `/admin/accounts` | 账号列表 |
| GET | `/admin/accounts/{id}` | 账号详情 |
| POST | `/admin/accounts/{id}/disable` | 封禁账号 |
| POST | `/admin/accounts/{id}/enable` | 解封账号 |
| GET | `/admin/accounts/{id}/devices` | 设备列表 |
| POST | `/admin/accounts/{id}/devices/{device_id}/revoke` | 吊销设备 refresh |
| GET | `/admin/saves` | 存档列表 |
| GET | `/admin/saves/{id}` | 存档详情 |
| GET | `/admin/saves/{id}/versions` | 存档历史版本 |
| POST | `/admin/saves/{id}/rollback` | 回滚存档 |
| GET | `/admin/storage/usage` | 存储占用 |
| POST | `/admin/storage/gc` | 孤儿对象清理 |
| GET | `/admin/content/packs` | 内容包列表 |
| POST | `/admin/content/packs` | 上传内容包 |
| POST | `/admin/content/packs/{name}/validate` | 校验内容包 |
| POST | `/admin/content/publish` | 发布内容包（兼容旧端点） |
| GET | `/admin/content/releases` | 发布批次列表 |
| POST | `/admin/content/releases` | 创建灰度发布批次 |
| POST | `/admin/content/releases/{id}/pause` | 暂停放量 |
| POST | `/admin/content/releases/{id}/resume` | 继续放量 |
| POST | `/admin/content/releases/{id}/rollback` | 回滚发布 |
| GET | `/admin/config` | 读取远程配置 |
| PUT | `/admin/config` | 编辑并发布远程配置 |
| GET | `/admin/config/versions` | 配置版本历史 |
| POST | `/admin/config/rollback` | 回滚配置 |
| GET | `/admin/announcements` | 公告列表 |
| POST | `/admin/announcements` | 新建公告 |
| PUT | `/admin/announcements/{id}` | 编辑公告 |
| DELETE | `/admin/announcements/{id}` | 删除公告 |
| GET | `/admin/telemetry/events` | 遥测明细 |
| GET | `/admin/telemetry/aggregates` | 日聚合 |
| GET | `/admin/telemetry/life-stats` | 人生统计 |
| POST | `/admin/telemetry/export` | 导出遥测 |
| POST | `/admin/telemetry/purge` | 合规删除 |
| GET | `/admin/audit-logs` | 审计日志 |
| GET | `/admin/assistant/status` | 运营助手状态 |
| POST | `/admin/assistant/query` | 运营助手查询 |
| POST | `/admin/assistant/draft` | 生成内容草稿 |
| GET | `/admin/system/status` | 系统状态 |
| GET | `/admin/system/backups` | 备份列表 |
| POST | `/admin/system/backup` | 手动触发备份 |
| GET | `/admin/system/migrations` | 迁移版本 |

> 端点将在 `shared/openapi/openapi.yaml` 落实（任务 24/25）。当前已有 3 个 admin 端点保留兼容。

## 6. 数据模型（后台新增）

### 6.1 admin_audit_logs

| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuidv7 | 主键 |
| actor_account_id | uuid | 操作者 |
| action | string | 动作键，如 `account.disable` |
| target_type | string | 目标类型 |
| target_id | string | 目标 ID |
| before | jsonb | 变更前快照（脱敏） |
| after | jsonb | 变更后快照（脱敏） |
| result | string | `ok` / `error` |
| ip | string | 来源 IP |
| user_agent | string | UA |
| created_at | timestamptz | 时间 |

### 6.2 content_releases

| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuidv7 | 主键 |
| pack_name | string | 内容包名 |
| pack_version | string | 版本 |
| strategy | string | `all` / `percent` / `accounts` |
| rollout_percent | int | 放量百分比 |
| account_list | jsonb | 指定账号名单 |
| status | string | `scheduled`/`rolling`/`paused`/`completed`/`rolled_back` |
| manifest_version | int | 目标清单版本 |
| created_at / updated_at | timestamptz | |

### 6.3 announcements

| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuidv7 | 主键 |
| title / body | text | 标题与 Markdown 正文 |
| audience | string | `all` / `accounts` |
| account_list | jsonb | 指定账号 |
| start_at / end_at | timestamptz | 起止 |
| status | string | `draft`/`scheduled`/`published`/`offline` |
| created_at / updated_at | timestamptz | |

### 6.4 config_versions

| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuidv7 | 主键 |
| version | int | 递增版本 |
| values | jsonb | 配置内容 |
| revision | int | 乐观锁 |
| created_by | uuid | 操作者 |
| created_at | timestamptz | |

## 7. 非功能

- 列表统一游标或页码分页，默认每页 20，可调。
- 导出上限：单次导出默认不超过 10 万行或 50MB，超出走异步任务（Redis 队列）并通知。
- 配置与内容发布使用乐观锁，冲突时提示刷新后重试。
- 审计日志保留期长于遥测明细，默认 365 天。
- 主题支持亮/暗，跟随系统。

## 8. 测试策略

- 权限：非 admin 访问任意 `/admin/*` 返回 403；未登录 401。
- 审计：每个写端点调用后产生一条审计记录，字段完整。
- 内容：发布批次灰度计算、暂停/继续、回滚的状态机正确；校验能拒绝坏包。
- 配置：版本递增、回滚、并发冲突返回 409。
- 遥测：聚合与导出数量正确，删除按保留期生效。
- 危险操作：缺少二次确认参数时拒绝。
- 前端：构建通过、路由守卫生效、请求层 401 自动刷新。

## 9. 对应关系

- 需求：R38（管理后台）、R39（遥测与数据）。
- 任务：`tasklist.md` 第 24 项（后端支撑）、第 25 项（React 后台）。
- 相关：`design.md`「后端运营」「后端本地模型（运营助手）」；`shared/openapi/openapi.yaml`。
