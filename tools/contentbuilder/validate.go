package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// rawCategory 是一个类别的源数据文件。
type rawCategory struct {
	File    string
	Name    string
	Entries []entry
}

// LoadCatalog 读取 content/catalog 下的所有类别源文件（.json 优先，其次 .csv）。
func LoadCatalog(dir string) (map[string]*rawCategory, []issue) {
	out := map[string]*rawCategory{}
	var issues []issue
	for name := range categorySpecs {
		jsonPath := filepath.Join(dir, name+".json")
		csvPath := filepath.Join(dir, name+".csv")
		if _, err := os.Stat(jsonPath); err == nil {
			cat, errs := loadJSONCategory(jsonPath, name)
			if len(errs) > 0 {
				issues = append(issues, errs...)
				continue
			}
			out[name] = cat
		} else if _, err := os.Stat(csvPath); err == nil {
			cat, errs := loadCSVCategory(csvPath, name)
			if len(errs) > 0 {
				issues = append(issues, errs...)
				continue
			}
			out[name] = cat
		}
	}
	return out, issues
}

func loadJSONCategory(path, name string) (*rawCategory, []issue) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, []issue{{File: path, Category: name, Message: err.Error()}}
	}
	var doc struct {
		Category string           `json:"category"`
		Entries  []map[string]any `json:"entries"`
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, []issue{{File: path, Category: name, Message: "JSON 解析失败: " + err.Error()}}
	}
	cat := &rawCategory{File: path, Name: name}
	for i, raw := range doc.Entries {
		key, _ := raw["content_key"].(string)
		cat.Entries = append(cat.Entries, entry{Key: key, Fields: normalizeJSON(raw)})
		_ = i
	}
	return cat, nil
}

// normalizeJSON 把 json 数字统一为 int/float。
func normalizeJSON(raw map[string]any) map[string]any {
	out := map[string]any{}
	for k, v := range raw {
		if f, ok := v.(float64); ok {
			if f == float64(int(f)) {
				out[k] = int(f)
			} else {
				out[k] = f
			}
			continue
		}
		out[k] = v
	}
	return out
}

func loadCSVCategory(path, name string) (*rawCategory, []issue) {
	f, err := os.Open(path)
	if err != nil {
		return nil, []issue{{File: path, Category: name, Message: err.Error()}}
	}
	defer f.Close()
	reader := csv.NewReader(f)
	reader.FieldsPerRecord = -1
	records, err := reader.ReadAll()
	if err != nil {
		return nil, []issue{{File: path, Category: name, Message: "CSV 解析失败: " + err.Error()}}
	}
	if len(records) == 0 {
		return nil, []issue{{File: path, Category: name, Message: "CSV 为空"}}
	}
	spec := categorySpecs[name]
	header := records[0]
	cat := &rawCategory{File: path, Name: name}
	for rowIdx, rec := range records[1:] {
		fields := map[string]any{}
		for col, colName := range header {
			if col >= len(rec) {
				continue
			}
			fields[colName] = convertCSVField(spec, colName, rec[col])
		}
		key, _ := fields["content_key"].(string)
		cat.Entries = append(cat.Entries, entry{Key: key, Fields: fields})
		_ = rowIdx
	}
	return cat, nil
}

func convertCSVField(spec categorySpec, name, raw string) any {
	for _, fs := range spec.fields {
		if fs.name != name {
			continue
		}
		switch fs.typ {
		case tInt:
			if n, err := strconv.Atoi(strings.TrimSpace(raw)); err == nil {
				return n
			}
		case tFloat:
			if f, err := strconv.ParseFloat(strings.TrimSpace(raw), 64); err == nil {
				return f
			}
		case tBool:
			return strings.EqualFold(strings.TrimSpace(raw), "true") || raw == "1"
		case tStringList:
			if strings.TrimSpace(raw) == "" {
				return []any{}
			}
			parts := strings.Split(raw, ";")
			arr := make([]any, 0, len(parts))
			for _, p := range parts {
				p = strings.TrimSpace(p)
				if p != "" {
					arr = append(arr, p)
				}
			}
			return arr
		}
		break
	}
	return strings.TrimSpace(raw)
}

// Validate 执行硬阻断式校验，任一错误即整体失败并定位条目。
func Validate(catalog map[string]*rawCategory) []issue {
	var issues []issue
	globalKeys := map[string]string{} // content_key -> "category/file"
	keysByCategory := map[string]map[string]bool{}

	// 第一遍：字段、类型、主键格式与全局重复。
	for name, cat := range catalog {
		spec := categorySpecs[name]
		catKeys := map[string]bool{}
		for _, e := range cat.Entries {
			loc := locFor(cat.File, e.Key)
			if e.Key == "" {
				issues = append(issues, issue{cat.File, name, loc, "缺少 content_key"})
			} else if !contentKeyPattern.MatchString(e.Key) {
				issues = append(issues, issue{cat.File, name, loc, "content_key 格式不合法（应点分小写）"})
			}
			if catKeys[e.Key] {
				issues = append(issues, issue{cat.File, name, loc, "重复 content_key"})
			}
			catKeys[e.Key] = true
			if prev, ok := globalKeys[e.Key]; ok && e.Key != "" {
				issues = append(issues, issue{cat.File, name, loc, fmt.Sprintf("content_key 与 %s 重复", prev)})
			} else if e.Key != "" {
				globalKeys[e.Key] = fmt.Sprintf("%s(%s)", name, e.Key)
			}
			for _, fs := range spec.fields {
				v, ok := e.Fields[fs.name]
				if !ok || v == nil {
					if fs.required {
						issues = append(issues, issue{cat.File, name, loc, fmt.Sprintf("缺少必填字段 %s", fs.name)})
					}
					continue
				}
				if !typeOK(fs.typ, v) {
					issues = append(issues, issue{cat.File, name, loc, fmt.Sprintf("字段 %s 类型应为 %s", fs.name, fieldTypeName(fs.typ))})
				}
			}
			if nm, ok := e.Fields["name"].(string); ok && strings.TrimSpace(nm) == "" {
				issues = append(issues, issue{cat.File, name, loc, "name 为空（i18n 键缺失）"})
			}
		}
		keysByCategory[name] = catKeys
	}

	// 第二遍：跨引用完整性。
	for name, cat := range catalog {
		spec := categorySpecs[name]
		for _, e := range cat.Entries {
			loc := locFor(cat.File, e.Key)
			for field, target := range spec.crossRefs {
				refs := toStringList(e.Fields[field])
				for _, ref := range refs {
					if !keysByCategory[target][ref] {
						issues = append(issues, issue{cat.File, name, loc, fmt.Sprintf("字段 %s 引用不存在的内容键 %s", field, ref)})
					}
				}
			}
		}
	}
	return issues
}

func toStringList(v any) []string {
	arr, ok := v.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(arr))
	for _, x := range arr {
		if s, ok := x.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func locFor(file, key string) string {
	if key == "" {
		return file
	}
	return fmt.Sprintf("%s#%s", file, key)
}
