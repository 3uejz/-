package sim

// MinutesPerYear 是共享的“年”长度：1440 分钟/日 × 365.25 日（与客户端一致）。
const MinutesPerYear = 1440.0 * 365.25

// PopulationCohortNext 按线性队列模型推进人口，真源与测试向量见
// shared/consistency/vectors/population.json（spec=cohort_linear）。
//
//	next = population * (1 + (birth_rate - death_rate + migration_rate) * years)
//	years = minutes / (1440 * 365.25)
func PopulationCohortNext(population, birthRate, deathRate, migrationRate, minutes float64) float64 {
	years := minutes / MinutesPerYear
	return population * (1 + (birthRate-deathRate+migrationRate)*years)
}
