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
sim/flavor.gd       文案变化层：为高频动作生成确定性、时段场景化的叙事变体
sim/time_driver.gd  实时驱动：现实秒 × 倍速 → 游戏分钟（余数累积、单帧封顶）
command/    中文指令解析（parser/intent/verb_registry）与执行（intent_executor.gd：意图 → 系统 → 叙事/面板）
ui/         主界面壳（main.tscn）与面板（注册表 37 面板）、面板内容装配（panel_content.gd）
presentation/ 局部 3D 表现层（place_bindings.gd 场所绑定、scenes/placeholder_place.tscn 差异化占位场景）
assets/     美术资产目录与契约（见 assets/README.md：命名/LOD/替换工作流）
art/        叙事插画（illustrations/）
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
执行器经 `sim/flavor.gd` 为等待/睡/吃/锻炼/工作/学习等动作生成时段场景化的措辞变体。

## 挂机实时世界

除指令推进外，`main.gd._process()` 每帧按「现实增量 × 倍速」自动推进游戏内时钟与生理，
构成挂机实时世界（R1 / M0）：

```
_process(delta) → TimeDriver.consume(SpeedController.get_speed(), delta)
               → SimHost.advance(分钟) + TickScheduler.tick(now) + 刷新状态栏
```

- `sim/time_driver.gd`（`TimeDriver`）：把现实秒按倍速换算为游戏分钟，余数累积防漂移、单帧封顶 1 天。
- 快进目标（`SpeedController.target_minutes`）到达即停并回落 1 倍速；玩家死亡时暂停推进。
- **headless（测试/CI）下自动关闭**（`_auto_time_supported()` 判 `DisplayServer.get_name()`），
  保证测试确定性；可用 `set_auto_time()`/`auto_time_enabled()` 显式开关。

## 面板与表现层

- **37 个面板**全部接入内容装配（`ui/panels/panel_content.gd`）：核心面板直接读玩家字典；
  领域面板经 `context` 读取 `world_delta`/`macro`/`epidemic`/`weather`，数据缺失时给引导性空态。
- **3D 表现层**：`place_bindings.gd` 把 13 个场所分组映射到场景；`presentation/scenes/placeholder_place.tscn`
  按分组程序化生成差异化灰盒（`PlaceholderAssets.GROUP_STYLES`）。真实资产放入
  `presentation/scenes/places/<group>.tscn` 即自动替换，零改代码（见 `assets/README.md`）。

## 测试

```bash
# 运行全部客户端测试（含跨语言一致性）
/workspace/.toolchain/godot --headless --path client --script res://tests/consistency_test.gd

# 单套件
/workspace/.toolchain/godot --headless --path client --script res://tests/intent_executor_test.gd
```

共享数值规格见 `shared/consistency/`；两端一致性由 `scripts/test.sh` 统一运行。
