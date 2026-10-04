package sim

// 全局数值基线的运行时访问层。
//
// 数值真源位于 shared/consistency/baseline/*.json，常量由 tools/genbaseline 生成到
// baseline_generated.go（Baseline* 前缀），两端须保持一致；实际变量可由远程配置覆盖。

// Ranges 返回各属性区间（真源 core.json 的 ranges，生成于 baseline_generated.go）。
func Ranges() map[string][2]int {
	out := make(map[string][2]int, len(BaselineRanges))
	for k, v := range BaselineRanges {
		out[k] = v
	}
	return out
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

// ClampAttribute 将属性值夹到其定义区间。
func ClampAttribute(v int) int {
	r := BaselineRanges["attribute"]
	return clampInt(v, r[0], r[1])
}

// ClampSkill 将技能等级夹到其定义区间。
func ClampSkill(v int) int {
	r := BaselineRanges["skill"]
	return clampInt(v, r[0], r[1])
}

// ClampFavor 将好感夹到其定义区间。
func ClampFavor(v int) int {
	r := BaselineRanges["favor"]
	return clampInt(v, r[0], r[1])
}

// ClampGrudge 将恩怨夹到其定义区间。
func ClampGrudge(v int) int {
	r := BaselineRanges["grudge"]
	return clampInt(v, r[0], r[1])
}
