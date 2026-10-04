package sim

// SplitMix64 是客户端/后端共享的可复现伪随机数发生器。
// 规格见 shared/consistency/README.md。
type SplitMix64 struct {
	state uint64
}

const (
	splitMixGamma uint64 = 0x9E3779B97F4A7C15
	splitMixMul1  uint64 = 0xBF58476D1CE4E5B9
	splitMixMul2  uint64 = 0x94D049BB133111EB
)

// NewSplitMix64 以给定种子创建发生器。
func NewSplitMix64(seed uint64) *SplitMix64 {
	return &SplitMix64{state: seed}
}

// State 返回当前内部状态。
func (r *SplitMix64) State() uint64 { return r.state }

// SetState 覆盖内部状态（用于存档恢复）。
func (r *SplitMix64) SetState(state uint64) { r.state = state }

// Next 产出下一个无符号 64 位随机数。
func (r *SplitMix64) Next() uint64 {
	r.state += splitMixGamma
	z := r.state
	z = (z ^ (z >> 30)) * splitMixMul1
	z = (z ^ (z >> 27)) * splitMixMul2
	z ^= z >> 31
	return z
}

// NextFloat 归一到 [0,1)，等价 uint64 * 2^-64。
func (r *SplitMix64) NextFloat() float64 {
	return float64(r.Next()) / 18446744073709551616.0
}
