---
name: life-sandbox
description: Use when working anywhere in the 浮生录 (Life Text Sandbox) repository — a Godot 4 desktop + Go backend open-world life text sandbox. Covers spec locations, the discuss-before-code workflow, and the Chinese-only reply rule.
---

# 浮生录（Life Text Sandbox）项目技能

## 何时使用

在本仓库任何位置工作、或用户提到「浮生录 / 人生沙盒 / life-text-sandbox」时使用。

## 铁律

1. **先讨论后实现**：任何系统与方案先逐项讨论清楚，用户明确说「开始做」后才写实现代码。
2. **全程中文回复**。
3. 需求没敲定前，不改 `client/`、`server/`、`admin/` 下的实现代码；规格以文档为准。

## 规格位置

`当前工作区/.monkeycode/specs/life-text-sandbox/`

- `requirements.md`：需求 R1–R99、50 域 D1–D50
- `design.md`：架构、数值基线、逐域细节、横切系统
- `tasklist.md`：43 任务与里程碑 M0–M5
- `content-catalog.md`：内容全表
- `verb-registry.md`：中文指令动词

## 架构一句话

客户端 Godot 4（GDScript + 引擎定制）权威本地玩法、可离线；Go 模块化单体权威全球人口与宏观经济的统计，另提供账号、云存档、内容分发、传承档案与遥测；React 管理后台。

## 常用命令

- 工具链自检：`bash scripts/doctor.sh`
- 本地服务：`bash scripts/services.sh start|stop|status`
- Godot headless：`/workspace/.toolchain/godot --headless --version`
