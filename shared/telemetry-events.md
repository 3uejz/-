# 遥测事件目录（Telemetry Events）

> 对应需求 R39；数据结构见 `shared/schemas/telemetry.schema.json`；后端运营见 `design.md`「后端运营」。本文件是遥测事件类型、上报策略、保留与聚合的单一真源。

## 1. 定位与原则

- 遥测默认开启匿名上报，用户可一键关闭；关闭后事件本地不入队。
- 只采集与玩法、平衡、稳定性相关的事件；禁止采集可识别个人的信息（真实姓名、地址、账号凭据、精确 IP 之外的设备指纹）。
- 离线时事件本地缓存，恢复后按 `event_id` 去重补传。
- 客户端负责产生事件，后端负责去重、聚合与保留。

## 2. 事件信封

所有事件使用统一信封（`shared/schemas/telemetry.schema.json`）：

| 字段 | 必填 | 说明 |
|------|------|------|
| event_id | 是 | UUIDv7，去重键 |
| event_type | 是 | 点分小写，见第 4 节目录 |
| occurred_at | 是 | UTC RFC3339 |
| world_minutes | 否 | 世界绝对分钟 |
| account_id | 否 | 绑定账号时的匿名 ID |
| playthrough_id | 否 | 本世存档 ID |
| session_id | 否 | 本次会话 ID |
| client_version | 否 | 客户端版本 |
| schema_version | 是 | 遥测 schema 版本 |
| has_context | 否 | 是否含上下文快照（抽样调试用） |
| payload | 否 | 事件负载，字段随类型定义 |

## 3. 上报策略（已定）

- **关键事件必报**：死亡、结婚、离婚、生育、破产、重大疾病、犯罪定罪、事业里程碑、成就达成、游戏结束等，全部上报，不采样。
- **高频事件采样**：属性变化、移动、价格变动、关系微调等按事件类型设采样率（如 1%、5%、10%），采样在客户端完成并写入 `sampled=true` 语义（体现在 `payload.sample_rate`）。
- **聚合优先**：高频事件在客户端按时间窗预聚合（如每日属性均值/极值），减少事件量。
- 采样率与开关由远程配置下发，默认值见第 4 节。

## 4. 事件目录

| event_type | 分类 | 触发时机 | 上报 | payload 关键字段 |
|------------|------|----------|------|------------------|
| life.birth | life | 角色出生 | 必报 | seed、region_key、family_class |
| life.milestone | life | 成年/毕业/结婚/生育/离婚 | 必报 | milestone、age、partner |
| life.death | life | 角色死亡 | 必报 | cause、age、region_key |
| playthrough.end | life | 一世结束 | 必报 | years、income_total、expense_total、top_occupation |
| career.employ | career | 入职 | 必报 | occupation_key、salary |
| career.promotion | career | 晋升 | 必报 | from、to、performance |
| career.resign | career | 离职 | 必报 | occupation_key、reason |
| career.business | career | 创业/破产 | 必报 | stage、capital、result |
| economy.transaction | economy | 大额交易 | 采样 | kind、amount、currency |
| economy.bankrupt | economy | 破产 | 必报 | debt、assets |
| economy.property | economy | 房产买卖 | 必报 | action、price、region_key |
| economy.loan_default | economy | 贷款违约 | 必报 | principal、days_overdue |
| health.illness | health | 确诊疾病 | 必报 | disease_key、severity |
| health.hospitalize | health | 住院/手术 | 必报 | procedure、cost、result |
| health.addiction | health | 成瘾/戒断 | 必报 | substance、stage |
| social.relation | social | 关系显著变化 | 采样 | target_type、dimension、delta |
| education.enroll | education | 入学 | 必报 | institution、level |
| education.graduation | education | 毕业/证书 | 必报 | credential、level |
| education.skillup | education | 技能升级 | 采样 | skill_key、level |
| crime.arrest | crime | 被捕 | 必报 | charge、region_key |
| crime.conviction | crime | 定罪/判决 | 必报 | charge、sentence_minutes |
| world.event | world | 全球事件 | 必报 | event_key、scope、severity |
| world.disaster | world | 灾害 | 必报 | hazard_key、region_key、loss |
| world.era_change | world | 时代推进 | 必报 | from_era、to_era |
| balance.attribute | balance | 属性分布采样 | 采样 5% | attribute、value、age |
| balance.price | balance | 物价指数聚合 | 日聚合 | region_key、price_index |
| balance.population | balance | 人口聚合 | 日聚合 | region_key、cohorts |
| cheat.draw | cheat | 金手指抽取 | 必报（匿名） | rarity、pity、reroll |
| cheat.toggle | cheat | 金手指开关 | 必报（匿名） | enabled |
| system.session | system | 会话开始/结束 | 必报 | action、duration_seconds |
| system.performance | system | 性能采样 | 采样 1% | fps、tick_ms、memory_mb |
| system.error | system | 客户端错误 | 必报 | code、module、stack_hash |
| system.content | system | 内容包更新 | 必报 | pack、from、to |

> 目录随系统扩展；新增事件须同时更新本表与 `telemetry.schema.json` 的校验约束（如需要）。

## 5. 保留与聚合（已定）

- **明细**：默认保留 90 天，超期删除。
- **日聚合**：按日聚合长期保留，用于趋势与平衡分析。
- **聚合维度**：日期、地域（粗粒度）、职业类别、年龄段、时代。
- 合规删除：支持按账号/时间范围删除，操作记审计。

## 6. 人生统计聚合（R39.3）

由 `playthrough.end` 与事件流聚合得到：

| 指标 | 来源 |
|------|------|
| 总收入 / 总支出 | economy.* 聚合 |
| 职业轨迹 | career.* 时间序列 |
| 主要成就 | life.milestone、achievements |
| 婚姻/子女 | life.milestone |
| 死亡原因与年龄 | life.death |

结果由 `/api/v1/admin/telemetry/life-stats` 提供。

## 7. 隐私与合规

- 事件负载禁止包含可识别个人的信息；`payload` 由校验器过滤敏感键。
- 遥测开关状态随存档与设置保存；关闭即时停止入队。
- 提供数据导出与删除接口（R39）。
