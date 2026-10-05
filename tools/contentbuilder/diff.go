package main

import (
	"encoding/json"
	"sort"
)

// packDiff 描述单个内容包在两个版本间的差异。
type packDiff struct {
	Name     string   `json:"name"`
	Kind     string   `json:"kind"`
	Status   string   `json:"status"` // added|changed|removed|unchanged
	FromHash string   `json:"from_hash,omitempty"`
	ToHash   string   `json:"to_hash,omitempty"`
	Added    []string `json:"added,omitempty"`
	Changed  []string `json:"changed,omitempty"`
	Removed  []string `json:"removed,omitempty"`
}

// manifestDiff 是两个清单之间的完整差量报告。
type manifestDiff struct {
	From        int        `json:"from_manifest_version"`
	To          int        `json:"to_manifest_version"`
	GeneratedAt string     `json:"generated_at"`
	Packs       []packDiff `json:"packs"`
}

// diffManifests 比较两个清单，按包名给出状态；条目级差异由 diffEntries 单独计算后填充。
func diffManifests(prev, next manifest) manifestDiff {
	d := manifestDiff{From: prev.ManifestVersion, To: next.ManifestVersion, GeneratedAt: nowUTC()}
	prevByName := map[string]manifestPack{}
	for _, p := range prev.Packs {
		prevByName[p.Name] = p
	}
	nextNames := map[string]bool{}
	for _, p := range next.Packs {
		nextNames[p.Name] = true
		pd := packDiff{Name: p.Name, Kind: p.Kind}
		old, ok := prevByName[p.Name]
		switch {
		case !ok:
			pd.Status = "added"
		case old.Hash != p.Hash:
			pd.Status = "changed"
			pd.FromHash = old.Hash
			pd.ToHash = p.Hash
		default:
			pd.Status = "unchanged"
		}
		d.Packs = append(d.Packs, pd)
	}
	for _, p := range prev.Packs {
		if !nextNames[p.Name] {
			d.Packs = append(d.Packs, packDiff{Name: p.Name, Kind: p.Kind, Status: "removed", FromHash: p.Hash})
		}
	}
	sort.Slice(d.Packs, func(i, j int) bool { return d.Packs[i].Name < d.Packs[j].Name })
	return d
}

// diffEntries 计算同一类别两个版本间的条目差异（按 content_key）。
func diffEntries(prev, next map[string]map[string]any) (added, changed, removed []string) {
	for key, nv := range next {
		pv, ok := prev[key]
		if !ok {
			added = append(added, key)
			continue
		}
		if !jsonEqual(pv, nv) {
			changed = append(changed, key)
		}
	}
	for key := range prev {
		if _, ok := next[key]; !ok {
			removed = append(removed, key)
		}
	}
	sort.Strings(added)
	sort.Strings(changed)
	sort.Strings(removed)
	return
}

func jsonEqual(a, b map[string]any) bool {
	ab, _ := json.Marshal(a)
	bb, _ := json.Marshal(b)
	return string(ab) == string(bb)
}

// patchEntries 从新旧条目中提取增量包（新增+变更），用于生成差量包。
func patchEntries(next map[string]map[string]any, changed []string, added []string) []entry {
	out := make([]entry, 0, len(added)+len(changed))
	for _, key := range append(append([]string{}, added...), changed...) {
		out = append(out, entry{Key: key, Fields: next[key]})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Key < out[j].Key })
	return out
}

// applyPackPatch 在基础包上应用增量（新增/变更）与删除，得到与全量发布等价的条目集合。
func applyPackPatch(base map[string]map[string]any, patch []entry, removed []string) map[string]map[string]any {
	out := map[string]map[string]any{}
	for k, v := range base {
		out[k] = v
	}
	for _, e := range patch {
		out[e.Key] = e.Fields
	}
	for _, r := range removed {
		delete(out, r)
	}
	return out
}
