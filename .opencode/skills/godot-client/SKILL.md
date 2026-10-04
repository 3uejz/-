---
name: godot-client
description: Use when editing or running the Godot 4 client under client/ — GDScript, scenes (.tscn), resources (.tres), project.godot, content packs, headless runs, exports. Trigger keywords: Godot, GDScript, .tscn, .tres, project.godot, client/.
---

# Godot 客户端技能

## 引擎

- 版本锁定 **4.7.2-stable**，二进制位于 `/workspace/.toolchain/godot`（本仓库 fork 后仍锁定此版本）。
- 渲染后端 Forward+（Vulkan）。
- headless 运行：`/workspace/.toolchain/godot --headless ...`。

## 约定

- 代码与资产分离；逻辑用 GDScript，热点的逐帧计算才下沉 C++（GDExtension）。
- 内容以 `Resource`（`.tres`）组织；海量同构条目用自定义二进制容器 + 轻量结构，不逐条建 Resource。
- 场景与脚本命名跟随设计文档，不自行发明系统名。
- 不要提交 `client/.godot/`、`*.import`、导出产物。

## 常用命令

```bash
# 版本
/workspace/.toolchain/godot --headless --version

# 运行主场景（无显示环境用 headless 或 xvfb）
/workspace/.toolchain/godot --path client

# 导入资源
/workspace/.toolchain/godot --headless --path client --import
```

## 注意

写实现前先确认对应设计章节已在 `design.md` 中定稿；未定稿的系统不要动手。
