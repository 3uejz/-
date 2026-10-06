package sim

import "math"

// GBMNext 按几何布朗运动推进价格，真源与测试向量见
// shared/consistency/vectors/economy.json（spec=gbm）。
//
//	S_next = S * exp((mu - 0.5*sigma^2)*dt + sigma*sqrt(dt)*Z)
func GBMNext(s, mu, sigma, dt, z float64) float64 {
	return s * math.Exp((mu-0.5*sigma*sigma)*dt+sigma*math.Sqrt(dt)*z)
}
