# shared/ — 跨语言共享规格

客户端（GDScript）与后端（Go）共用的规格与数据，防止两端漂移。所有内容以本目录为**单一事实来源**。

## 结构

```
shared/
├── conventions.md              # 通用约定：版本/ID/时间/命名/金额/错误码/分页/鉴权/幂等
├── telemetry-events.md         # 遥测事件目录、上报策略、保留与聚合
├── schemas/                    # JSON Schema 2020-12，数据结构定义
│   ├── common.schema.json      # uuid/时间/金额/错误/分页/内容引用
│   ├── player.schema.json      # 玩家模型（属性组、技能、关系、财务、健康…）
│   ├── npc.schema.json         # NPC 模型与 LOD
│   ├── save.schema.json        # 存档文档（meta/clock/player/world_delta/rng/legacy）
│   ├── content-manifest.schema.json
│   ├── remote-config.schema.json
│   ├── telemetry.schema.json
│   ├── legacy.schema.json
│   ├── worldsim.schema.json    # 后端权威全球人口/宏观摘要
│   ├── goldfinger.schema.json  # 可选元层金手指运行时状态（R100）
│   └── goldfinger-def.schema.json  # 金手指内容定义 GoldfingerDef
├── openapi/
│   └── openapi.yaml            # OpenAPI 3.1，/api/v1 全部端点
└── consistency/
    ├── README.md               # 随机数/时间/经济/人口规格与运行方式
    └── vectors/                # 跨语言一致性测试向量（rng/time/economy/population）
```

## 使用

- 客户端与后端的数据结构以 `schemas/` 为准，不得各自定义。
- REST 接口以 `openapi/openapi.yaml` 为准，前缀 `/api/v1`。
- 随机数、时间映射、经济与人口公式以 `consistency/vectors/` 为准，两端实现须通过一致性测试。
- 系统语义与数值基线仍见 `当前工作区/.monkeycode/specs/life-text-sandbox/design.md`。
