# 跨语言一致性测试（client / server）

目的：防止客户端（GDScript）与后端（Go）在同一输入下算出不同结果，导致数值漂移。两端必须对 `vectors/` 中的每个用例产出与 `expected` 完全一致的结果。

## 文件

- `vectors/rng.json`：共享伪随机数（SplitMix64）整数与浮点序列
- `vectors/time.json`：绝对分钟 → 公历日期/星期/季节
- `vectors/economy.json`：几何布朗运动（GBM）单步价格
- `vectors/population.json`：人口队列线性推进
- `vectors/worldsim.json`：宏观季度序列（人口/通胀/失业/基准利率/物价指数/PMI/相位/绝对分钟）
- `vectors/baseline.json`：数值基线快照（由生成器写出，勿手改）
- `baseline/`：数值基线**单一真源**（手写 JSON）。`manifest.json` 列出 `core` 与各域文件，
  `core.json` 存区间/默认值/速度档/昼夜相位，其余按域拆分（survival/region/geo_transport/
  climate_weather/era/economy 等）。

## 数值基线真源与代码生成

数值默认的单一真源位于 `baseline/`；生成器 `tools/genbaseline`（Go）据此产出：

- `client/sim/baseline_generated.gd`（`class_name BaselineGenerated`）
- `server/internal/sim/baseline_generated.go`（`Baseline*` 前缀常量）
- `shared/consistency/vectors/baseline.json`（快照）

```bash
# 重新生成生成物与快照
cd tools/genbaseline && go run .

# 仅校验生成物与真源一致（CI / scripts/test.sh 使用，不一致时退出码非零）
cd tools/genbaseline && go run . -check
```

`client/sim/baseline.gd` 与 `server/internal/sim/baseline.go` 不再手写常量，只保留运行时
remote override 与派生访问器；改默认值一律改 `baseline/` 下的 JSON 后重新生成。

## 1. 随机数规格（SplitMix64）

两端统一使用 **SplitMix64**，按随机流隔离。用于世界生成、事件抽取、经济随机项等一切需要可复现的场合。

```text
MASK = 0xFFFFFFFFFFFFFFFF
GAMMA = 0x9E3779B97F4A7C15

state = seed
function next():
    state = (state + GAMMA) AND MASK
    z = state
    z = ((z XOR (z >> 30)) * 0xBF58476D1CE4E5B9) AND MASK
    z = ((z XOR (z >> 27)) * 0x94D049BB133111EB) AND MASK
    z = z XOR (z >> 31)
    return z                      # 无符号 64 位整数

# 归一到 [0,1)
function next_float():
    return next() * 2^-64
```

流种子：由 `world_seed` 与流名字（如 `weather`、`events`、`economy`）拼接后哈希派生，保证各流互不相关；具体哈希实现由两端共享（见后续补充），初期可用 SplitMix64 对字符串逐字节累积。

注意：Go 用 `uint64`，GDScript 的 `int` 为 64 位有符号；实现时按无符号位运算处理（`>>` 用逻辑右移）。向量中的整数以 `0x` 前缀 16 位十六进制字符串给出，两端解析时**不得经过 double**（Godot 用 `String.hex_to_int`，Go 用 `strconv.ParseUint(s, 0, 64)`），避免精度丢失。浮点用例按 `1e-6` 容差比较。

## 2. 时间规格

- `absolute_minutes` 以 `epoch_utc = 2000-01-01T00:00:00Z` 为 0。
- 采用真实公历：月份天数、闰年规则（能被 4 整除且不能被 100 整除，或能被 400 整除）。
- 星期：ISO-8601，`1=周一 .. 7=周日`。
- 季节按北半球月份划分：3–5 春、6–8 夏、9–11 秋、12–2 冬。
- 世界起始时点由远程配置给出（默认落在现代年份），但**映射算法与 epoch 固定**，不得随版本漂移。

## 3. 经济与人口

- GBM 与人口推进公式见各自 vector 文件的 `formula` 字段。
- 浮点比较使用容差 `1e-6`（相对误差）；整数与时间必须精确相等。
- `worldsim.json` 为宏观季度序列，向量仅覆盖不触发周期切换的季度区间（不依赖 RNG），
  两端浮点比较容差 `1e-9`；实现见 `server/internal/worldsim/macro.go` 与 `client/sim/macro.gd`。

## 4. 运行方式

- Go：`server` 中编写一致性测试，读取 `shared/consistency/vectors/*.json`，逐用例断言。
- GDScript：`client` 中编写 headless 测试（GUT/GdUnit4），读取同一份向量文件。
- CI：任一不一致即阻断构建。

## 5. 维护

- 修改算法或 epoch 必须同步更新向量与本文档，并升 `version`。
- 新增数值模型时，先加向量用例，再写两端实现（测试先行）。
