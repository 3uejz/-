# 待明确与跨任务接口清单

本文件记录在实施（M0–M1）过程中暴露出的规格缺口、跨语言不一致与需补齐的设定。
状态未明确前不要按某一方实现固化；讨论清楚后回填到 `design.md` / `requirements.md` / `tasklist.md`，
并勾选对应条目。

## 一、影响跨语言一致性（优先处理）

- [x] **OI-1 新增数值未进共享基线**（2026-10-04 解决）：定 `shared/consistency/vectors/baseline.json` 为单一真源，生成 `baseline_generated.gd` 与 `baseline_generated.go`，CI 校验生成物无 diff；所有跨端/跨内核常量入基线，运行时 remote override 叠加。落地任务 46。
- [x] **OI-2 宏观/微观权威边界不可执行**（2026-10-04 解决）：明确后端权威（全球人口聚合、宏观指标、全球事件、云存档/传承）与客户端权威（本地精细区域、玩家、本地 NPC 与派生价格）；离线用同一确定性模型近似推进并记 `server_tick` 锚点；上线宏观服务器胜、保留本地。落地任务 24.4。

## 二、跨任务依赖（需在规格中显式标注接口）

- [x] **OI-3 疾病钩子接口已定**（2026-10-04）：营养系统输出 `disease_risk[content_key]`，D17（任务 17）消费，数值随 D17。
- [x] **OI-4 遗产分配已归属**（2026-10-04）：Survival 死亡时产出 `will` 与遗产清单，R43.10 分配归任务 18/22。
- [x] **OI-5 运行态存档已定**（2026-10-04）：扩 `save.schema` 持久化临终/死亡标志、遗嘱、成瘾运行态与过量天数，随 `schema_version` 迁移。
- [x] **OI-6 时代区间已定**（2026-10-04）：闭区间 `[era_min, era_max]`，缺省一端无界。
- [x] **OI-7 气候趋势已归属**（2026-10-04）：加配置键 `climate_trend`，数值随 D1（任务 9 细化）。
- [x] **OI-8 天气跨系统已定接口**（2026-10-04）：Weather 输出 modifier 字典，健康/心情/客流/交通/农业/能源各自消费。
- [x] **OI-9 跨境与交通事件已归属**（2026-10-04）：归 D2/D50 建模，先预留接口。
- [x] **OI-10 时区基准已定**（2026-10-04）：UTC 绝对分钟存储，按区域时区展示本地时间，跨时区旅行重算展示。
- [x] **OI-11 全量地理已归属**（2026-10-04）：任务 8 细化 + 内容任务；真实数据来源后定。
- [x] **OI-12 内容管线已归属**（2026-10-04）：任务 23。
- [x] **OI-13 输入与无障碍已归属**（2026-10-04）：TTS/焦点导航/键位捕获随相关 UI 任务。

## 处理约定

- 编号 OI-* 稳定，不随讨论重新编号。
- 讨论明确后：更新对应规格文件，并在本清单勾选并补一行结论（日期 + 决议）。
- OI-1、OI-2 在继续 M1 之前应优先有结论，避免继续制造不一致。

## 决议记录

### 2026-10-04 引擎定制方向

- **形态**：`engine/` 以 Git submodule 指向自有 Godot fork，维护 `lifetext` 分支，基点锁定 4.7.x 官方 tag，保留 `upstream` 镜像常合并；核心 diff 趋近于零。
- **范围**：内容管线与资源格式、性能热点、资源保护与加密、中文与输入法、构建与导出，全部纳入项目专用引擎。
- **节奏**：先以 GDExtension + 编辑器插件做原型（内容格式/加密/文本），验证通过后冻结为 `modules/lifetext_{content,crypto,text,sim}`，再建自定义导出模板。
- **平台**：首发 Windows，CI 产出定制编辑器 + Windows 导出模板 + headless 构建；本机使用官方引擎。
- 已落入 `design.md`「引擎定制」「引擎运行时架构」与 `tasklist.md` 任务 45。
- **附带修正**：原设计「连续开放世界/区块流式加载」与「局部 3D、切换加载」冲突，已改为按当前场所局部加载、跨场所由 2D 地图与文字指令切换。

### 2026-10-04 引擎细节决策

- **仓库布局**：overlay 模式。项目模块放游戏仓库 `engine-modules/lifetext_*`，核心 patch 放 `engine-patches/*.patch`，构建前覆盖进 Godot 源码树并 apply；`engine/` submodule 保持接近纯净。
- **内容容器**：列式数据块 + 字符串池 + zstd，带版本头与哈希；`.res` 仅用于核心内容。
- **加密范围**：存档用 AES-256-GCM + KDF（Argon2/PBKDF2），密文外附 sha256；PCK 用 Godot 内建加密；首发不做重型反篡改。
- 已落入 `design.md`「引擎定制」「引擎运行时架构」「存档 Schema 与体积」。
- **新增待办**：现有 `client/sim/save_codec.gd` 仅哈希校验，需按新决策补存档加密（含 KDF 与设置开关），并同步 `shared/schemas/save.schema.json` 的加密相关字段。

### 2026-10-04 引擎细节决策（二）

- **CI**：GitHub Actions 托管 runner；windows-latest 出 Windows 导出模板，ubuntu-latest 出 editor 与 headless；开 ccache 与 scons cache。
- **KDF**：Argon2id（在 `lifetext_crypto` 模块内实现）。
- **字体**：思源黑体（正文）+ 思源宋体（标题），OFL，做字形子集化。
- 已落入 `design.md`「引擎定制」「引擎运行时架构」「存档 Schema 与体积」「合规与许可」。
- **GDExtension 与 module 边界（原型期约定）**：内容加载器与加密放 module（需紧耦合引擎资源系统），文本增强允许少量核心 patch，确定性数值热点先以 GDExtension 验证再进 `lifetext_sim`。

### 2026-10-04 模块 API 与确定性决策

- **C++ 内核形态**：无状态批处理内核，输入输出均为 Packed 数组，无全局可变状态；模拟状态以 GDScript 为源，便于存档与单测。
- **确定性数值**：跨实现一致的部分用整数/定点，浮点仅用于表现与纯本地瞬时量。
- **一致性校验**：Go + GDScript + C++ 三端同时接入 `shared/consistency` 向量。
- **模块 API 契约**：`LT` 前缀 + API 版本常量、`RefCounted` 实例、批量 Packed 数组、结构化结果 `{ok, code, message, data}`；契约写入 `engine-modules/README.md`。
- 已落入 `design.md`「引擎定制」「引擎运行时架构」「混合权威」。
- **约束提醒**：后续 `lifetext_sim` 内核不得用浮点承载需跨端一致的逻辑；Go 侧避免 map 迭代参与确定性计算。

### 2026-10-04 OI-1 / OI-2 决议

- **OI-1**：`baseline.json` 单一真源 + 代码生成 `baseline_generated.gd/.go` + CI diff 校验；全部跨端/跨内核常量入基线，remote override 叠加。落地任务 46。
- **OI-2**：后端权威全球人口聚合与宏观指标、全球事件、云存档/传承；客户端权威本地精细区域、玩家、本地 NPC 与派生价格；离线用同一确定性模型近似推进并记 `server_tick` 锚点；上线宏观服务器胜、保留本地变更。落地任务 24.4。
- 已落入 `design.md`「混合权威」「全局数值基线」，`tasklist.md` 新增任务 46 与 24.4。

### 2026-10-04 OI-3～OI-13 决议

- **接口契约（数值/实现随归属任务）**：OI-3 疾病 `disease_risk`→D17；OI-4 遗产→任务 18/22；OI-7 `climate_trend`→D1；OI-8 Weather modifier 字典→各系统；OI-9 跨境与交通事件→D2/D50。
- **已定实现语义**：OI-5 扩 schema 持久化运行态（含版本迁移）；OI-6 时代闭区间；OI-10 UTC 存储 + 本地展示。
- **工程未落地（归属任务）**：OI-11 全量地理→任务 8 细化；OI-12 内容管线→任务 23；OI-13 输入与无障碍→相关 UI 任务。
- 已落入 `design.md`「D1 天气生态与时代」「时间」「存档 Schema 与体积」。
- **新增待办**：`save.schema.json` 需按 OI-5 扩展运行态字段并加版本迁移；`baseline` 相关改动随任务 46 落地。

### 2026-10-04 金手指与后端决议

- **金手指关闭语义**：中途关闭只停用持续型效果，已获得的一次性效果不回收；再次开启恢复持续型效果（已同步 R100.5）。
- **金手指积分**：随轮回清零，不跨代继承。
- **金手指权威**：客户端抽取，后端仅下发稀有度分布与保底配置；只作用本地玩家状态，不进入后端全球人口与宏观。
- **后端首发范围**：完整后端（账号/云存档/内容/宏观/遥测/Admin）。
- **部署规格**：2 核 4 线程 / 8–12GB / 约 566GB SSD。
- **运营助手**：首发不启用，仅保留架构与接口预留。
- 已落入 `design.md`「金手指系统」「后端运营」「后端本地模型」与 `requirements.md` R100。

### 2026-10-04 后端细节决议

- **worldsim 时钟**：宏观为 `f(world_seed, tick, 全局事件日志)`，后端从最近检查点按需批量迭代到请求 tick，客户端离线用同一函数近似；快进即请求更大 tick。
- **云存档同步**：按 player/world/history 分块增量上传，`base_revision` 冲突检测，latest-wins + 历史回滚；宏观块以服务端为准。
- **Redis 职责**：会话/令牌缓存、限流计数、宏观检查点缓存、异步任务队列；MinIO 承载存档对象、内容包、备份。
- **会话策略**：短时 access JWT + 可轮换 refresh token，按设备存 `devices`，登出吊销。
- 已落入 `design.md`「混合权威」「存档 Schema 与体积」「后端运营」，`tasklist.md` 任务 24。

### 2026-10-04 内容分发 / Admin / 遥测决议

- **内容包鉴权**：签名 URL；同 LAN 可经交换机直连高速传输，支持 rsync/SMB 预置大包 + manifest 哈希校验、只补差量。
- **差量粒度**：先 pack 级，大包块级后续。
- **Admin 认证**：复用账号体系，账号标 `is_admin`。
- **遥测**：默认开启匿名上报、可一键关闭；事件结构含 `schema_version`；明细短期保留（默认 90 天）+ 按日聚合长期保留。
- 已落入 `design.md`「后端运营」，`tasklist.md` 任务 24/25。

### 2026-10-04 横切系统决议（遥测/错误/测试）

- **遥测目录**：新建 `shared/telemetry-events.md`，定义事件信封、目录、上报策略、保留聚合与人生统计；扩展 `telemetry.schema.json`（新增 schema_version 必填、account_id/session_id/has_context）。
- **上报策略**：关键事件必报 + 高频事件采样 + 客户端预聚合。
- **错误呈现**：三级（叙事流内联 / Toast / 模态）+ 网络指数退避重试与幂等键。
- **测试门槛**：CI 必须全绿，核心域设覆盖率下限，其余关键路径必测；领域不变量接入属性测试。
- 已落入 `shared/telemetry-events.md`、`design.md`「Error Handling」「Test Strategy」、`shared/schemas/telemetry.schema.json`。

### 2026-10-04 逐域缺口审计决议

- **审计**：D1–D50 只读审计完成，结果固化于 `gaps.md`；结论是领域语义完整、缺可实施细节。
- **修复组织**：横切优先，登记任务 48–53（基线、schema 迁移、内容目录、UI/动词、跨域契约、测试）。
- **存档 schema**：一次大扩展 + `schema_version` 迁移。
- **UI**：面板由 12 扩到全量。
- **D20 语言**：独立类型，0..100 分项，独立遗忘速率。
- 已落入 `gaps.md`、`tasklist.md` 任务 48–53。

### 2026-10-04 客户端 UI 规格决议

- **规格落位**：新建 `ui.md` 作为客户端 UI 单一真源；新增 `tasklist.md` 任务 47 承载实施。
- **主题**：全量设计 token 系统 + 亮/暗双主题 + 主题色定制 + 无障碍三套（默认/高对比/色盲）+ 全局缩放与正文字号双档，设置页实时预览。
- **美术**：内联插画走水墨国风；图标单色线性；动效克制并尊重「减少动态」。
- **布局**：三区主界面（状态栏/叙事流/指令区）+ 右侧快捷动作；面板以侧边抽屉滑出，**可多开**。
- **叙事**：默认即时整条显示，可选打字机（默认关）；内联插画；实体可点击。
- **范围**：12 面板、8 类弹窗、系统托盘 + 桌面通知、全套无障碍，均首发。
- **输入**：键鼠优先，手柄后置。
- 已落入 `ui.md`、`design.md`「UI Inventory」、`tasklist.md` 任务 47。

### 2026-10-04 管理后台规格决议

- **规格落位**：新建 `admin.md` 作为后台单一真源；`design.md`「后端运营」保留索引。
- **模块范围**：首发做满 11 模块（登录鉴权、仪表盘、账号与设备、存档运维、内容管理、远程配置、公告、遥测与统计、审计日志、运营助手、系统运维）。
- **权限模型**：单管理员，复用账号 + `is_admin`；写操作全部审计，危险操作二次确认。
- **内容发布**：支持灰度分批（按账号/百分比），可暂停/继续/全量/回滚。
- **存档边界**：后台只读 + 回滚，不单点硬删；删除仅在账号合规注销时级联。
- **前端栈**：Vite + React 18 + TS + AntD 5 + React Router + TanStack Query + Zustand。
- **部署形态**：构建产物由 Go 同源静态托管于 `/admin`。
- **API 扩展**：`/api/v1/admin/*` 由 3 个扩至约 40 个端点，待同步 `shared/openapi/openapi.yaml`。
- 已落入 `admin.md`、`design.md`、`tasklist.md` 任务 25。

### 2026-10-04 金手指细节决议

- **内容格式**：新增 `shared/schemas/goldfinger-def.schema.json` + `GoldfingerDef` Resource（运行时状态沿用既有 `goldfinger.schema.json`），字段见 design 金手指节。
- **强度约束**：稀有度 power budget，效果带 cost，持续型按周期计费，总 cost 不超预算。
- **模块组织**：`MetaSystem` 统一注册表，模块实现 `enable/disable/on_tick/on_event/render`。
- **重抽**：开档限量免费（默认 3 次），之后消耗积分。
- 已落入 `design.md`「金手指系统」、`content-catalog.md` 第 20 节、`tasklist.md` 任务 44。
- **已完成**：已创建 `shared/schemas/goldfinger-def.schema.json` 并同步 `shared/README.md`（schema 由 10 增至 11）；新增 `scripts/validate_schemas.py`（语法 + 顶层约定 + 本地/跨文件 `$ref` 解析）并接入 `scripts/test.sh`。





## 状态汇总

- 已解决：OI-1、OI-2、OI-3、OI-4、OI-5、OI-6、OI-7、OI-8、OI-9、OI-10、OI-11、OI-12、OI-13（全部有归属或语义）。
- 待实现缺口（非阻塞）：存档加密（任务 3 收尾）、运行态 schema 扩展（OI-5）、共享基线生成（任务 46）。




