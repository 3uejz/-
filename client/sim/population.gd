class_name Population
extends RefCounted
## 线性队列人口推进（客户端/后端一致性，见 shared/consistency/vectors/population.json）。
## 真源 spec=cohort_linear；Go 端实现见 server/internal/sim/population.go。

const MINUTES_PER_YEAR: float = 1440.0 * 365.25

## next = population * (1 + (birth_rate - death_rate + migration_rate) * years)
## years = minutes / (1440 * 365.25)
static func cohort_next(population: float, birth_rate: float, death_rate: float, migration_rate: float, minutes: float) -> float:
	var years: float = minutes / MINUTES_PER_YEAR
	return population * (1.0 + (birth_rate - death_rate + migration_rate) * years)
