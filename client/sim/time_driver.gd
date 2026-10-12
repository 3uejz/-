class_name TimeDriver
extends RefCounted
## 实时时间驱动（挂机实时世界，R1 / M0）。
## 把现实帧间隔按倍速换算为游戏内整分钟：余数累积，避免逐帧取整造成的漂移；
## 单帧推进量设上限，避免快进档（86400x）单帧推进过多导致卡顿。
## 纯逻辑、不依赖节点树与 Autoload，headless 直接实例化即可测试。

## 单帧最多推进的游戏分钟（≈1 天），超出部分留待后续帧，保证单帧结算有界。
var max_batch: int = 1440

var _accum: float = 0.0

## 消费一帧：返回本帧应推进的整分钟数（≥0），不足一分钟的余数保留到下次。
## speed 为倍速档（0=暂停，1=1:1 实时，60=每现实秒 1 小时，86400=每现实秒 1 天）。
func consume(speed: int, delta_seconds: float) -> int:
	if speed <= 0 or delta_seconds <= 0.0:
		return 0
	_accum += delta_seconds * float(speed) / 60.0
	var whole := int(floor(_accum))
	if whole > max_batch:
		whole = max_batch
	_accum -= float(whole)
	return whole

## 尚不足一分钟的累积余数（分钟）。
func carry() -> float:
	return _accum

func reset() -> void:
	_accum = 0.0
