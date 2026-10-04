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
