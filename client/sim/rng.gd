class_name SplitMix64
extends RefCounted
## 共享伪随机数：SplitMix64（客户端/后端一致性，见 shared/consistency/README.md）。
## GDScript 的 int 为 64 位有符号，所有运算按无符号位模式处理。

## GDScript 的 int 为 64 位有符号，且十六进制字面量超过 INT64_MAX 会解析失败，
## 故常量一律写成等价的补码有符号十进制。
const GAMMA: int = -7046029254386353131  # 0x9E3779B97F4A7C15
const MASK: int = -1                      # 0xFFFFFFFFFFFFFFFF
const MUL_1: int = -4658895280553007687   # 0xBF58476D1CE4E5B9
const MUL_2: int = -7723592293110705685   # 0x94D049BB133111EB
const TWO_POW_64: float = 18446744073709551616.0
const TWO_POW_32: float = 4294967296.0

var _state: int = 0

func _init(seed: int = 0) -> void:
	_state = seed

func state() -> int:
	return _state

func set_state(value: int) -> void:
	_state = value

## 无符号 64 位逻辑右移（GDScript 的 >> 为算术右移）。
static func _lshr(x: int, n: int) -> int:
	if n <= 0:
		return x
	if x >= 0:
		return x >> n
	var mask: int = (1 << (64 - n)) - 1
	return (x >> n) & mask

## 产出下一个无符号 64 位随机数（以有符号 int 位模式返回）。
func next_u64() -> int:
	_state = (_state + GAMMA) & MASK
	var z: int = _state
	z = ((z ^ _lshr(z, 30)) * MUL_1) & MASK
	z = ((z ^ _lshr(z, 27)) * MUL_2) & MASK
	z = z ^ _lshr(z, 31)
	return z & MASK

## 归一到 [0,1)，等价 uint64 * 2^-64。
func next_float() -> float:
	var u: int = next_u64()
	var hi: int = _lshr(u, 32)
	var lo: int = u & 0xFFFFFFFF
	return (float(hi) * TWO_POW_32 + float(lo)) / TWO_POW_64
