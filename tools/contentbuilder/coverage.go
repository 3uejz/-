package main

import (
	"fmt"
	"sort"
	"strings"
)

// r56Targets 是 R56 内容硬指标中可由内容目录直接度量的类别下限。
// 数值型枚举（气候带/天气/灾害/时代/异常能力线）由数值基线保证，不在此列。
var r56Targets = map[string]int{
	"sites":              1000, // 地点
	"place_types":        100,  // 场所类型
	"jobs":               200,  // 职业岗位
	"skills":             140,  // 技能
	"items":              1000, // 物品种类
	"diseases":           80,   // 疾病
	"certificates":       30,   // 证书
	"entertainment":      100,  // 娱乐活动
	"events":             300,  // 随机事件
	"achievements":       300,  // 成就
	"codex":              500,  // 图鉴条目
	"transport":          12,   // 交通方式
	"finance":            40,   // 金融标的
	"manufacturing":      50,   // 制造与贸易品类
	"awards":             40,   // 奖项与荣誉
	"organizations":      30,   // 组织与阵营
	"anomalies":          2000, // 异常实体
	"activities":         20,   // 大型活动类型
	"primary_industry":   30,   // 第一产业品类
	"professional_firms": 12,   // 专业服务机构（D48）
	"life_services":      16,   // 生活服务品类（D49）
	"infra_projects":     12,   // 交通基建类型（D50）
}

// r56SubTargets 是需按字段值细分的子指标。
type subTarget struct {
	Category string
	Field    string
	Values   []string // 任一匹配即计入
	Min      int
	Label    string
}

var r56SubTargets = []subTarget{
	{Category: "diseases", Field: "category", Values: []string{"精神", "心理", "mental"}, Min: 20, Label: "精神疾病"},
	{Category: "diseases", Field: "category", Values: []string{"成瘾", "addiction"}, Min: 5, Label: "成瘾类型"},
}

// Coverage 对照 R56 下限，返回未达标的类别与子指标。
func Coverage(catalog map[string]*rawCategory) []issue {
	var issues []issue
	names := make([]string, 0, len(r56Targets))
	for n := range r56Targets {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, name := range names {
		want := r56Targets[name]
		got := 0
		if c, ok := catalog[name]; ok {
			got = len(c.Entries)
		}
		if got < want {
			issues = append(issues, issue{
				File:     name + ".json",
				Category: name,
				Message:  fmt.Sprintf("未达 R56 下限：%d < %d", got, want),
			})
		}
	}
	for _, st := range r56SubTargets {
		c, ok := catalog[st.Category]
		if !ok {
			continue
		}
		count := 0
		for _, e := range c.Entries {
			v, _ := e.Fields[st.Field].(string)
			for _, want := range st.Values {
				if strings.EqualFold(v, want) || v == want {
					count++
					break
				}
			}
		}
		if count < st.Min {
			issues = append(issues, issue{
				File:     st.Category + ".json",
				Category: st.Category,
				Message:  fmt.Sprintf("子指标「%s」未达 R56 下限：%d < %d", st.Label, count, st.Min),
			})
		}
	}
	return issues
}
