package sim_test

import (
	"encoding/json"
	"fmt"
	"math"
	"reflect"
	"testing"

	"lifetextsandbox/server/internal/sim"
)

// TestBaselineDomainsConsistency 校验按域生成的全部基线常量与共享向量
// baseline_domains.json 一致。数据驱动：新增迁移域只需扩向量。
func TestBaselineDomainsConsistency(t *testing.T) {
	var v struct {
		Domains map[string]map[string]any `json:"domains"`
	}
	readVectorFile(t, "baseline_domains.json", &v)
	if len(v.Domains) == 0 {
		t.Fatal("baseline_domains.json 无 domains")
	}

	for domain, expected := range v.Domains {
		gots, ok := sim.BaselineDomains[domain]
		if !ok {
			t.Errorf("代码缺少域 %s", domain)
			continue
		}
		for key, want := range expected {
			got, ok := gots[key]
			if !ok {
				t.Errorf("%s.%s 常量缺失", domain, key)
				continue
			}
			compareVectorValue(t, fmt.Sprintf("%s.%s", domain, key), got, want)
		}
	}
}

func compareVectorValue(t *testing.T, label string, got, want any) {
	t.Helper()
	got = normalizeValue(got)
	switch w := want.(type) {
	case []any:
		g, ok := got.([]any)
		if !ok {
			t.Errorf("%s: 类型应为数组，got %T", label, got)
			return
		}
		if len(g) != len(w) {
			t.Errorf("%s: 长度 got=%d want=%d", label, len(g), len(w))
			return
		}
		for i := range w {
			compareVectorValue(t, fmt.Sprintf("%s[%d]", label, i), g[i], w[i])
		}
	case map[string]any:
		g, ok := got.(map[string]any)
		if !ok {
			t.Errorf("%s: 类型应为字典，got %T", label, got)
			return
		}
		for k, wv := range w {
			gv, ok := g[k]
			if !ok {
				t.Errorf("%s.%s: 缺少键", label, k)
				continue
			}
			compareVectorValue(t, fmt.Sprintf("%s.%s", label, k), gv, wv)
		}
	case float64:
		gf, ok := toFloat(got)
		if !ok {
			t.Errorf("%s: 类型应为数值，got %T", label, got)
			return
		}
		if math.Abs(gf-w) > 1e-9 {
			t.Errorf("%s: got=%v want=%v", label, gf, w)
		}
	default:
		if fmt.Sprint(got) != fmt.Sprint(want) {
			t.Errorf("%s: got=%v want=%v", label, got, want)
		}
	}
}

// normalizeValue 将生成常量中的强类型 map/array（如 map[string][2]int）统一为
// map[string]any / []any，以便与 JSON 解码结果做逐值比较。
func normalizeValue(v any) any {
	if v == nil {
		return nil
	}
	rv := reflect.ValueOf(v)
	switch rv.Kind() {
	case reflect.Map:
		out := make(map[string]any, rv.Len())
		for _, k := range rv.MapKeys() {
			out[fmt.Sprint(k.Interface())] = normalizeValue(rv.MapIndex(k).Interface())
		}
		return out
	case reflect.Slice, reflect.Array:
		out := make([]any, rv.Len())
		for i := 0; i < rv.Len(); i++ {
			out[i] = normalizeValue(rv.Index(i).Interface())
		}
		return out
	default:
		return v
	}
}

func toFloat(v any) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case int:
		return float64(n), true
	case int64:
		return float64(n), true
	case json.Number:
		f, err := n.Float64()
		return f, err == nil
	default:
		return 0, false
	}
}
