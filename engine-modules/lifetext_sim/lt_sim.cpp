#include "lt_sim.h"

#include "core/object/class_db.h"

#include <cmath>

static uint64_t _splitmix64_next(uint64_t &r_state) {
	r_state += 0x9E3779B97F4A7C15ULL;
	uint64_t z = r_state;
	z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
	z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
	return z ^ (z >> 31);
}

int LTSim::get_api_version() {
	return API_VERSION;
}

PackedInt64Array LTSim::next_u64(int64_t p_seed, int p_count) {
	PackedInt64Array out;
	if (p_count <= 0) {
		return out;
	}
	out.resize(p_count);
	uint64_t state = uint64_t(p_seed);
	for (int i = 0; i < p_count; i++) {
		out.set(i, int64_t(_splitmix64_next(state)));
	}
	return out;
}

PackedFloat64Array LTSim::decay_batch(const PackedFloat64Array &p_values, double p_rate_per_hour, double p_hours) {
	PackedFloat64Array out;
	out.resize(p_values.size());
	const double factor = std::exp(-p_rate_per_hour * p_hours);
	for (int i = 0; i < p_values.size(); i++) {
		out.set(i, p_values[i] * factor);
	}
	return out;
}

void LTSim::_bind_methods() {
	ClassDB::bind_static_method("LTSim", D_METHOD("get_api_version"), &LTSim::get_api_version);
	ClassDB::bind_static_method("LTSim", D_METHOD("next_u64", "seed", "count"), &LTSim::next_u64);
	ClassDB::bind_static_method("LTSim", D_METHOD("decay_batch", "values", "rate_per_hour", "hours"), &LTSim::decay_batch);
}
