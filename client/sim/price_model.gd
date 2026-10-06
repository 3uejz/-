class_name PriceModel
extends RefCounted
## 几何布朗运动价格推进（客户端/后端一致性，见 shared/consistency/vectors/economy.json）。
## 真源 spec=gbm；Go 端实现见 server/internal/sim/price.go。

## S_next = S * exp((mu - 0.5*sigma^2)*dt + sigma*sqrt(dt)*Z)
static func gbm_next(s: float, mu: float, sigma: float, dt: float, z: float) -> float:
	return s * exp((mu - 0.5 * sigma * sigma) * dt + sigma * sqrt(dt) * z)
