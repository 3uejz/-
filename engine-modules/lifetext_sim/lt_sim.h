#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// 无状态批量确定性内核。契约见 engine-modules/README.md。
// 所有函数不读写全局状态；输入输出均为 Packed 数组。
// SplitMix64 与 shared/consistency/vectors/rng.json 保持一致。
class LTSim : public RefCounted {
	GDCLASS(LTSim, RefCounted);

public:
	static constexpr int API_VERSION = 1;

	static int get_api_version();

	// 从 seed 起生成 count 个 SplitMix64 输出，按无符号 64 位位模式存入 int64。
	static PackedInt64Array next_u64(int64_t p_seed, int p_count);

	// 批量指数衰减：value * exp(-rate_per_hour * hours)，逐元素。
	static PackedFloat64Array decay_batch(const PackedFloat64Array &p_values, double p_rate_per_hour, double p_hours);

protected:
	static void _bind_methods();
};
