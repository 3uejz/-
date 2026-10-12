# User Instruction Memory

This file records user instructions, preferences, and teachings for reference in future interactions.

## Format

### User Instruction Entry
User instruction entries should follow this format:

[User Instruction Summary]
- Date: [YYYY-MM-DD]
- Context: [Mentioned scenario or time]
- Instructions:
  - [Content of user teaching or instruction, described line by line]

### Project Knowledge Entry
Entries discovered by the Agent during task execution should follow this format:

[Project Knowledge Summary]
- Date: [YYYY-MM-DD]
- Context: Discovered by Agent while performing [specific task description]
- Category: [Operations & Deployment|Build Methods|Testing Methods|Troubleshooting & Debugging|Workflow & Collaboration|Environment Configuration]
- Instructions:
  - [Specific knowledge points, described line by line]

## Deduplication Strategy
- Before adding a new entry, check for similar or identical instructions.
- If a duplicate is found, skip the new entry or merge it with the existing one.
- When merging, update the context or date information.
- This helps avoid redundant entries and keeps the memory file tidy.

## Entries

[User Instruction Summary]
- Date: 2026-10-03
- Context: 《浮生录》需求与设计讨论阶段
- Instructions:
  - 需求与方案必须逐系统讨论清楚，只有在用户明确说「开始做」之后才能写代码，不得提前实施。
  - 所有讨论要按「与现实对齐」的标准进行：现实世界里存在的体系都要做进去，体量不是约束，不够还可以继续加。
  - 全程用中文回复。

[User Instruction Summary]
- Date: 2026-10-03
- Context: 讨论游戏内容规模与方向时
- Instructions:
  - 游戏资源体量目标为 30GB；表现层采用全 3D（主角使用 3D 模型、NPC 简化表现），插画用于关键事件与图鉴；如需要可继续增大。
  - 内容硬指标与系统域不设上限，可随内容包持续扩展。

[Project Knowledge Summary]
- Date: 2026-10-03
- Context: Discovered by Agent while defining desktop performance targets for 《浮生录》
- Category: Environment Configuration
- Instructions:
  - 目标/开发机配置：CPU Intel i5-13600KF，内存 DDR5 32GB，显卡 RTX 4070（iGame 火神），存储 4TB 机械硬盘 + 1TB NVMe SSD。
  - 按此可开高配：精细 NPC 上限与资源缓存可上调；游戏主程序与热内容建议装在 NVMe，冷内容包可置于 HDD。

[User Instruction Summary]
- Date: 2026-10-03
- Context: 规格讨论阶段，用户要求并行推进
- Instructions:
  - 环境、工具链、技能可在后台搭建，用户在前台继续讨论玩法方案；后台工作不得阻塞前台讨论。

[Project Knowledge Summary]
- Date: 2026-10-03
- Context: 讨论后端部署拓扑时，用户提供私有服务器（联想笔记本）详细配置
- Category: Operations & Deployment
- Instructions:
  - 私有服务器为联想笔记本：CPU Intel Core i5-6200U（2 核 4 线程 @2.3GHz，Skylake 15W）；内存 4GB DDR4 2133（板载）+ 1 空闲 SO-DIMM 插槽，计划加一条 8GB（总约 12GB）；系统盘 447GB SSD（sdb），数据盘 119GB SSD（sda，挂载 /data/media）。
  - 显卡：核显 Intel HD Graphics 520，独显 AMD Radeon R5 M330（2GB，未使用）；网卡 Realtek RTL810xE（有线，r8169）+ Intel Wireless-AC 3165（无线，iwlwifi）。
  - 用途：单机单实例 Docker Compose 部署后端（Go + PostgreSQL + Redis + 对象存储），个人使用。
  - 结论：CPU 实为 2 核 4 线程（非四核），作个人后端足够但余量小；内存扩到约 12GB 缓解主要瓶颈；两块 SSD 合计约 566GB，满足存档/内容/备份。核显与独显均为老旧低端，不适合为模型推理提速。

[Project Knowledge Summary]
- Date: 2026-10-03
- Context: Discovered by Agent while provisioning the Godot + Go toolchain
- Category: Environment Configuration
- Instructions:
  - Godot 4.7.2-stable 二进制位于 `/workspace/.toolchain/godot`（headless 用 `--headless`）；`.toolchain/` 已加入 .gitignore，不入库。
  - 工具链自检：`bash scripts/doctor.sh`；本地服务：`bash scripts/services.sh start|stop|status`（Redis 6379、PostgreSQL 15 主集群 5432，容器内无 systemd，用 pg_ctlcluster）。
  - 已装：cmake 3.25、protobuf-compiler（protoc 3.21）、jq、redis 7.0、postgresql 15、Godot 运行时依赖 libfontconfig1/libfreetype6/libasound2。
  - Docker 在本开发容器内不可用；`deploy/docker-compose.yml` 只写文件，在私有服务器执行。
  - 项目技能位于 `.opencode/skills/`（life-sandbox、godot-client、go-backend）；新增或修改技能后需重启 opencode 才生效。

[User Instruction Summary]
- Date: 2026-10-04
- Context: 逐域深挖《浮生录》D1–D50 时，用户要求改变提问方式
- Instructions:
  - 每次需要用户拍板决策时，必须使用 question 工具的选项形式提问，给出候选选项（可含推荐项）；不要用自由文本清单让用户手工回填。

[User Instruction Summary]
- Date: 2026-10-04
- Context: M0 实现阶段，用户要求控制消耗
- Instructions:
  - 执行任务时节省 token：能委派给 subagent 的工作就委派，不要事事亲自动手；自身只保留必要的关键判断与汇总。

[Project Knowledge Summary]
- Date: 2026-10-04
- Context: Discovered by Agent while validating shared/ 规格文件（JSON Schema 与 OpenAPI）
- Category: Engineering & Debugging
- Instructions:
  - 本环境系统级未安装 PyYAML / jsonschema；校验 YAML 用仓库自带的 Node 包：`NODE_PATH=.opencode/node_modules node -e "require('yaml')..."`；校验 JSON 直接 `python3 -c json.load` 即可。
  - `shared/` 是跨语言规格单一事实来源：约定见 `shared/conventions.md`，接口见 `shared/openapi/openapi.yaml`（前缀 `/api/v1`），数据结构见 `shared/schemas/`，一致性向量见 `shared/consistency/vectors/`。

[Project Knowledge Summary]
- Date: 2026-10-04
- Context: Discovered by Agent while adding items/property/orders test suites (task 11)
- Category: Testing Methods
- Instructions:
  - 客户端测试文件放入 `client/tests/*_test.gd` 即被 `scripts/test.sh` 按 glob 自动发现执行，无需注册；套件须 `extends "res://tests/test_base.gd"` 并实现 `_suite_name()` 与 `run_tests()`。
  - 注意坑：`test_base` 仅在断言失败时累加 failures；若套件中出现运行时 `SCRIPT ERROR`（如空数组下标、参数类型不符），当前函数会中断但 failures 不增加，仍打印 `PASS`。因此看到 PASS 后仍需确认输出里没有 `SCRIPT ERROR`。

[Project Knowledge Summary]
- Date: 2026-10-11
- Context: Discovered by Agent while verifying task 45.2（Windows 导出自定义模板）与客户端后端接线
- Category: Operations & Deployment
- Instructions:
  - 引擎构建 CI 为 `.github/workflows/engine.yml`（工作流名 engine-build），仅在 push `engine-*` 标签或 workflow_dispatch 时触发；默认 `master` push 只跑 `.github/workflows/ci.yml`。单次全量约 35 分钟。
  - windows-template 作业流程：SCons 构建自定义模板 → 安装官方 4.7.2 编辑器 → 注册模板为 `%APPDATA%\Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe` → 用该模板导出客户端 → headless 冒烟运行导出程序。
  - 坑：Windows 编辑器要用 `Godot_v4.7.2-stable_win64_console.exe`（GUI 版不挂控制台，PowerShell 既不等待也拿不到退出码/日志）；导出路径传绝对路径，导出程序是 GUI 子系统，需用 `Start-Process -Wait -PassThru` 才能拿到退出码。
  - 查询本仓库 CI 状态：GitHub API 未认证会被限流（60/h）；可用 `git credential fill`（host=github.com）取 token 后以 `Authorization: Bearer` 调 `/repos/3uejz/-/actions/...`，勿在任何输出中打印 token。

[Project Knowledge Summary]
- Date: 2026-10-11
- Context: Discovered by Agent while running 客户端↔后端本地端到端联调
- Category: Testing Methods
- Instructions:
  - 本地连真实存储跑后端：先 `bash scripts/services.sh start`；创建 PG 角色/库 `life`（密码 `change-me`，与 `deploy/docker-compose.yml` 默认一致）后，用 `JWT_SECRET`(≥32B)/`ADMIN_PASSWORD`/`DATABASE_URL=postgres://life:change-me@127.0.0.1:5432/life?sslmode=disable`/`REDIS_URL=redis://127.0.0.1:6379/0` 启动 `server`（不配 DATABASE_URL 则回退进程内内存存储）。缺 `JWT_SECRET` 会拒绝启动（R37.12）。
  - `client/tests/net_live_test.gd` 会用真实 `HttpTransport` 打到 `http://127.0.0.1:8080`；后端不可达时打印 SKIP 且退出 0，故离线 `scripts/test.sh` 仍然通过。该套件以 `--script` 运行，Autoload 不挂载，实例化 net 后须 `add_child` 到 root 并 `await process_frame` 后 HTTPRequest 才在树内。
  - `.github/workflows/ci.yml` 现含三个作业：一致性校验与后端测试、Godot 客户端测试、管理后台构建。
