# 旧 H5 原型移植参考

## 背景

`prototype/legacy-h5/` 是《浮生录》早期的 Vite + Vue 3 + TypeScript H5 原型（单城「云州市」、7 项属性、约 120 物品 / 20 岗位 / 70 事件 / 100 成就 / 30 地点）。新的目标架构是 Godot 4 桌面客户端 + Go 后端，因此该原型**不作为运行代码复用**，而是作为算法思路、中文内容种子与界面结构的资料库。

- 原型目录：`prototype/legacy-h5/`
- 进入方式：`cd prototype/legacy-h5 && npm install && npm run dev`（`node_modules` 已随目录迁移；该目录被 `.gitignore` 排除，不入库）
- 规则：**任何新实现都必须落在 `client/`、`server/`、`shared/`、`content/`、`tools/` 等目标目录，禁止直接引用原型代码。**

## 文件映射与处置

| 原型文件 | 目标模块（design.md） | 移植建议 |
|----------|----------------------|----------|
| `src/engine/rng.ts`（mulberry32） | `client/` autoload RNG + `shared/` 规格 | 把 mulberry32 逐行移植到 GDScript 与 Go，保持 `state` 可序列化，服务「种子可复现 + 存档往返」 |
| `src/engine/parser/tokenizer.ts` | `client/command/` 分词器（R27） | 采用最长匹配 + 中文数字解析（十/百/千）+ Levenshtein 模糊建议；需补多义候选 ≤9 序号直选 |
| `src/engine/parser/resolver.ts` | `client/command/` 解析器（R27） | 词库索引构建、目标消歧、前缀补全、未识别建议；需改为内容驱动并从 Resource 词库构建索引 |
| `src/engine/verbs/registry.ts` | `client/command/` 动词注册（R27） | 动词 + 别名前缀匹配、分类帮助；基线以 `verb-registry.md` 为准 |
| `src/engine/time.ts`、`src/engine/state.ts` | `WorldClock`（R1） | 常量 1440 / 30 / 360 与设计一致，可直接沿用；**季节映射有偏差需按 D1 修正**；补 60x/3600x/86400x 快进与中断 |
| `src/engine/clock.ts` | `TickScheduler`（R1） | 「下一小时/日/年边界」步进避免逐分钟循环的思路可参考；需补季节级、年级、单帧结算上限 |
| `src/engine/events/engine.ts` | 事件调度（R98） | 加权触发 + 逐事件冷却 + 选项 + `EventEffect` 效果 DSL + 效果摘要文案，可作事件引擎原型；需补互斥组、全局限流、离线补算 |
| `src/engine/narrate.ts`、`src/content/texts.ts` | `Narrator`（R32） | 条件分组（昼夜/天气/季节/心情）随机模板 + `{var}` 渲染；中文文案可作种子 |
| `src/engine/save.ts` | `SaveManager`（R33/R58） | schema 版本号 + 迁移管线 + 序列化剔除瞬时字段的思路可参考；存储从 localStorage 改为 Godot 文件，需做分块与 <100MB 目标 |
| `src/engine/state-helpers.ts` | 统一数值入口 | `add_money`、属性 clamp、背包增删的集中式思路可参考 |
| `src/engine/systems/*` | 各领域系统 | 仅作最早期的简化参考，逻辑远浅于 D1–D50，需按设计重写 |
| `src/content/*` | `content/` 内容源（task 23） | 见下「内容种子转换」 |
| `src/App.vue`、`src/ui/*` | `client/ui/`（R57） | 仅作 UX 结构参考：开档设置、事件选项条、总览弹层、死亡结算页的信息组织 |
| 根 `package.json`/`vite.config.ts`/`tsconfig*.json`/`index.html` | 无 | 旧 H5 工程配置，仅原型自用，勿带入新工程 |

## 与新设计冲突项（禁止移植）

- `src/engine/legacy.ts`：用「传承点 + 天赋购买」表达元进度点数，与已定决策「无元进度点数」冲突，须丢弃；传承以世界延续、技能记忆、天赋血脉、资产人脉、世界记忆承载。
- `src/engine/state.ts`：属性模型过简（7 项属性、单一 `relationship`），需替换为属性分组与五维关系。
- 旧技能观感为 10 级，成就阈值写死 10，需统一到 **0..20 级**。
- `src/engine/systems/economy.ts`：股票用均匀随机游走，需改为 GBM。
- `src/engine/systems/social.ts`：`yearlyNpcLife` 使用 `Math.random` 而非种子 RNG，破坏可复现性，属反面教材。
- `src/engine/save.ts`：localStorage 存储不适用于 Godot 桌面端。
- 已发现小 bug（勿照抄）：`jobs.ts` 中 `driver` 的 `promotion` 指向更低的 `courier`；事件里程碑 `year` 写死为 0；`achievements.ts` 的 `ft_weather` 检查恒真。

## 内容种子转换（task 23）

原型数据类内容可转成 `content/` 的 CSV/JSON 种子，用于内容工具链导入：

- 可直接转换（纯数据）：`content/items.ts`（约 120 件）、`content/jobs.ts`（20 岗位 / 12 技能 / 5 学历 / 5 证书）、`content/events.ts`（约 70 条）、`content/locations.ts`（30 地点）、`content/npcs.ts`、`content/properties.ts`、`content/shops.ts`、`content/stocks.ts`。
- 需人工拆分（含函数逻辑）：`content/achievements.ts`（约 100 条，`check` 为函数，须把「展示数据」与「判定逻辑」分离后分别落库与编码）。
- 转换注意：原型 schema 比新设计浅（无品牌/品质/磨损、无营养向量、无保质期外字段），转换时应向新 schema 补齐字段，而非照搬。

转换工作安排在 task 23（内容管线与工具链）进行；在此之前保留原型源码即可，无需提前转换。

## prototype 目录约定

- `prototype/` 仅存放历史实现与实验，**不参与构建、不进 CI、不被 `client/`、`server/` 引用**。
- `prototype/legacy-h5/node_modules/`、`dist/`、`*.tsbuildinfo` 由现有 `.gitignore` 规则排除。
