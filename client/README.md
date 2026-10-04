# client/ — Godot 4 客户端

Godot 4.7.2-stable 桌面端工程。玩法由中文文字指令驱动，表现层全 3D。

- 引擎二进制：`/workspace/.toolchain/godot`
- headless：`/workspace/.toolchain/godot --headless --path client ...`
- 约定与命令见技能 `godot-client`。

## 骨架

```
autoload/  GameState / WorldClock / TickScheduler / SpeedController（Autoload 单例）
sim/       确定性模拟原语（rng.gd=SplitMix64，gregorian.gd=公历映射，baseline.gd=数值基线）
command/   中文指令解析（待任务 4）
ui/        主界面壳（main.tscn）
net/       REST 客户端（待任务 3/后端对接）
content/   内容包加载（待任务 23）
tests/     headless 测试（test_base.gd 基类 + 各 suite）
```

## 测试

```bash
# 运行全部客户端测试（含跨语言一致性）
/workspace/.toolchain/godot --headless --path client --script res://tests/consistency_test.gd
```

共享数值规格见 `shared/consistency/`；两端一致性由 `scripts/test.sh` 统一运行。
