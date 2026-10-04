package sim

// 全局数值基线默认值。共享规格见 shared/consistency/vectors/baseline.json，
// 两端须保持一致；实际变量可由远程配置覆盖。

const (
	AttributeMin   = 0
	AttributeMax   = 100
	PersonalityMin = 0
	PersonalityMax = 100
	ValuesAxisMin  = 0
	ValuesAxisMax  = 100
	SkillMin       = 0
	SkillMax       = 20
	FavorMin       = -100
	FavorMax       = 100
	GrudgeMin      = -100
	GrudgeMax      = 100
	TrustMin       = 0
	TrustMax       = 100
	AweMin         = 0
	AweMax         = 100
	IntimacyMin    = 0
	IntimacyMax    = 100

	// RelationAnnualDecayK 关系强度年均衰减系数。
	RelationAnnualDecayK = 0.05
)

// Ranges 返回各属性区间，键与 baseline.json 的 ranges 对应。
func Ranges() map[string][2]int {
	return map[string][2]int{
		"attribute":   {AttributeMin, AttributeMax},
		"personality": {PersonalityMin, PersonalityMax},
		"values_axis": {ValuesAxisMin, ValuesAxisMax},
		"skill":       {SkillMin, SkillMax},
		"favor":       {FavorMin, FavorMax},
		"grudge":      {GrudgeMin, GrudgeMax},
		"trust":       {TrustMin, TrustMax},
		"awe":         {AweMin, AweMax},
		"intimacy":    {IntimacyMin, IntimacyMax},
	}
}

func clampInt(v, min, max int) int {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

// ClampAttribute 将属性值夹到 [0,100]。
func ClampAttribute(v int) int { return clampInt(v, AttributeMin, AttributeMax) }

// ClampSkill 将技能等级夹到 [0,20]。
func ClampSkill(v int) int { return clampInt(v, SkillMin, SkillMax) }

// ClampFavor 将好感夹到 [-100,100]。
func ClampFavor(v int) int { return clampInt(v, FavorMin, FavorMax) }

// ClampGrudge 将恩怨夹到 [-100,100]。
func ClampGrudge(v int) int { return clampInt(v, GrudgeMin, GrudgeMax) }
