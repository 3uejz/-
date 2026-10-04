# 浮生录（Life Text Sandbox）

Godot 4 桌面端 + Go 后端的开放式人生文字沙盒。本文件面向在此仓库工作的编码 Agent。

## 工作方式（重要）

- 所有系统与方案必须先逐项讨论清楚；只有用户明确说「开始做」后才写实现代码。
- 全程使用中文回复。
- 规格文档位于 `当前工作区/.monkeycode/specs/life-text-sandbox/`：
  - `requirements.md`：R1–R99、50 个系统域（D1–D50）
  - `design.md`：Godot + Go 架构、数值基线、逐域细节、横切系统
  - `tasklist.md`：43 个实施任务与里程碑 M0–M5
  - `content-catalog.md`：内容全表
  - `verb-registry.md`：中文指令动词基线
- 用户级记忆见 `当前工作区/.monkeycode/MEMORY.md`。

## 环境与工具链

| 组件 | 位置 / 说明 |
|------|-------------|
| 操作系统 | Debian 12 (bookworm), x86_64, 2 核 |
| Go | 1.25.x（`/usr/local/go`） |
| Node | 22.x + npm / pnpm / yarn |
| Godot | 4.7.2-stable，`/workspace/.toolchain/godot`（headless 加 `--headless`） |
| Python | 3.11 |
| 编译 | gcc/g++ 12、make、cmake |
| protoc | 已装（protobuf-compiler） |
| PostgreSQL | 已装（apt，本地服务） |
| Redis | 已装（apt，本地服务） |
| Docker | 本容器内不可用；部署用 `deploy/` 下的 compose 文件在私有服务器执行 |

- 工具链自检：`bash scripts/doctor.sh`
- 本地服务管理：`bash scripts/services.sh start|stop|status`

## 目录结构

```
client/    Godot 4 客户端工程
server/    Go 模块化单体后端
admin/     React + Ant Design 管理后台
shared/    跨语言共享规格（JSON Schema、协议、一致性测试数据）
content/   内容源（职业、技能、物品、事件、地图等）
tools/     内容生产工具链（导入、校验、打包）
deploy/    私有服务器部署（docker-compose、Dockerfile）
scripts/   开发脚本（doctor、services）
prototype/ 历史 H5 原型，仅作移植参考，不参与构建、不进 CI、勿被目标工程引用
.monkeycode/  规格与记忆
```

## 代码与资产原则

- 代码与资产分离；内容以 Godot Resource 组织，海量同构条目用轻量二进制容器。
- 混合权威：客户端权威本地玩法（可离线），Go 后端权威全球人口与宏观经济。
- 共享规格 + 跨语言一致性测试，防止两端数值漂移。
