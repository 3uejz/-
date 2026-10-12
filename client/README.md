# client/ — Godot 4 客户端

Godot 4.7.2-stable 桌面端工程。玩法由中文文字指令驱动，表现层为局部 3D 场景（切换加载，当前以程序化占位为主）。

- 引擎二进制：`/workspace/.toolchain/godot`
- headless：`/workspace/.toolchain/godot --headless --path client ...`
- 约定与命令见技能 `godot-client`。

## 骨架

```
autoload/   GameState / WorldClock / TickScheduler / SpeedController / Net（Autoload 单例）
sim/        确定性模拟系统（110+ 领域系统；rng.gd=SplitMix64，gregorian.gd=公历映射，baseline.gd=数值基线）
sim/sim_host.gd     玩法接线层：绑定 GameState、惰性挂载系统、按分钟推进、回写经济镜像
command/    中文指令解析（parser/intent/verb_registry）与执行（intent_executor.gd：意图 → 系统 → 叙事/面板）
ui/         主界面壳（main.tscn）与面板（注册表 37 面板）、面板内容装配
net/        REST 客户端与网关
content/    内容包加载（清单/差量/校验）
tests/      headless 测试（test_base.gd 基类 + 各 suite）
```

## 玩法接线

`main.gd` 在 `_ready()` 中经 `_init_simulation()` 建立 `SimHost`（绑定 `/root/GameState`）
与 `IntentExecutor`，并把执行器注入指令通路（`set_command_handler(_on_intent)`）：

```
文字/按钮 → CommandParser → CommandIntent → IntentExecutor → SimHost（模拟系统）
          → 叙事回显 + 时钟推进（GameState.clock ↔ WorldClock）+ 面板打开 + 存读档
```

指令输入的解析目录（物品/技能）来自 `SimHost` 注册的起步目录；未链接到目录的名称由执行器按名称回退匹配。

## 测试

```bash
# 运行全部客户端测试（含跨语言一致性）
/workspace/.toolchain/godot --headless --path client --script res://tests/consistency_test.gd

# 单套件
/workspace/.toolchain/godot --headless --path client --script res://tests/intent_executor_test.gd
```

共享数值规格见 `shared/consistency/`；两端一致性由 `scripts/test.sh` 统一运行。
