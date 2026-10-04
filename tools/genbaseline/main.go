// Command genbaseline 从 shared/consistency/baseline/ 的数值基线真源生成
// GDScript 与 Go 常量代码，以及一致性快照 shared/consistency/vectors/baseline.json。
//
// 用法（仓库根或本目录均可）：
//
//	go run ./tools/genbaseline          # 写入生成物
//	go run ./tools/genbaseline -check   # 只校验生成物与真源一致（CI 用）
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"go/format"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type constEntry struct {
	name  string
	value any
}

type manifest struct {
	Spec    string   `json:"spec"`
	Version int      `json:"version"`
	Note    string   `json:"note"`
	Core    string   `json:"core"`
	Domains []string `json:"domains"`
}

// 生成物相对仓库根的路径。
const (
	gdOutPath     = "client/sim/baseline_generated.gd"
	goOutPath     = "server/internal/sim/baseline_generated.go"
	vectorOutPath = "shared/consistency/vectors/baseline.json"
)

func main() {
	check := flag.Bool("check", false, "只校验生成物，不写文件；不一致时退出码非零")
	flag.Parse()

	root, err := findRepoRoot()
	if err != nil {
		fatal(err)
	}
	man, err := loadManifest(root)
	if err != nil {
		fatal(err)
	}

	outputs, err := generate(root, man)
	if err != nil {
		fatal(err)
	}

	if *check {
		if err := checkOutputs(root, outputs); err != nil {
			fatal(err)
		}
		fmt.Println("数值基线生成物与真源一致")
		return
	}
	for path, content := range outputs {
		abs := filepath.Join(root, path)
		if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
			fatal(err)
		}
		if err := os.WriteFile(abs, content, 0o644); err != nil {
			fatal(err)
		}
		fmt.Println("生成", path)
	}
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "genbaseline:", err)
	os.Exit(1)
}

func findRepoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		marker := filepath.Join(dir, "shared", "consistency", "baseline", "manifest.json")
		if _, err := os.Stat(marker); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", errors.New("未找到仓库根（缺少 shared/consistency/baseline/manifest.json）")
		}
		dir = parent
	}
}

func loadManifest(root string) (*manifest, error) {
	raw, err := os.ReadFile(filepath.Join(root, "shared", "consistency", "baseline", "manifest.json"))
	if err != nil {
		return nil, err
	}
	var m manifest
	if err := json.Unmarshal(raw, &m); err != nil {
		return nil, err
	}
	if m.Core == "" || len(m.Domains) == 0 {
		return nil, errors.New("manifest.json 缺少 core 或 domains")
	}
	return &m, nil
}

// generate 返回 path -> 内容。
func generate(root string, man *manifest) (map[string][]byte, error) {
	baseDir := filepath.Join(root, "shared", "consistency", "baseline")

	core, err := decodeFile(filepath.Join(baseDir, man.Core))
	if err != nil {
		return nil, err
	}
	coreMap, ok := core.(map[string]any)
	if !ok {
		return nil, errors.New("core.json 顶层必须是对象")
	}

	// 收集所有域常量（分域文件为 {常量名: 值}）。
	var entries []constEntry
	for _, file := range man.Domains {
		decoded, err := decodeFile(filepath.Join(baseDir, file))
		if err != nil {
			return nil, err
		}
		m, ok := decoded.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("%s 顶层必须是对象", file)
		}
		for name, value := range m {
			entries = append(entries, constEntry{name, value})
		}
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].name < entries[j].name })

	gd, err := renderGDScript(coreMap, entries)
	if err != nil {
		return nil, err
	}
	goSrc, err := renderGo(coreMap, entries)
	if err != nil {
		return nil, err
	}
	vector, err := renderVector(coreMap)
	if err != nil {
		return nil, err
	}

	return map[string][]byte{
		gdOutPath:     gd,
		goOutPath:     goSrc,
		vectorOutPath: vector,
	}, nil
}

func checkOutputs(root string, outputs map[string][]byte) error {
	var bad []string
	for path, want := range outputs {
		abs := filepath.Join(root, path)
		got, err := os.ReadFile(abs)
		if err != nil {
			bad = append(bad, path+": 缺失或不可读")
			continue
		}
		if !bytes.Equal(got, want) {
			bad = append(bad, path+": 与真源不一致")
		}
	}
	if len(bad) > 0 {
		sort.Strings(bad)
		return errors.New("生成物过期，请运行 go run ./tools/genbaseline：\n  " + strings.Join(bad, "\n  "))
	}
	return nil
}

// --- 解码 ---

func decodeFile(path string) (any, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	dec := json.NewDecoder(f)
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return v, nil
}

func sortedKeys(m map[string]any) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// --- 数值字面量 ---

func isFloatNumber(n json.Number) bool {
	return strings.ContainsAny(n.String(), ".eE")
}

func gdNumber(n json.Number, indent string) (string, string) {
	if isFloatNumber(n) {
		f, _ := n.Float64()
		return "float", gdFloat(f)
	}
	return "int", n.String()
}

func gdFloat(f float64) string {
	s := strconv.FormatFloat(f, 'g', -1, 64)
	if !strings.ContainsAny(s, ".eE") {
		s += ".0"
	}
	return s
}

func goNumber(n json.Number) (string, bool) {
	if isFloatNumber(n) {
		f, _ := n.Float64()
		s := strconv.FormatFloat(f, 'g', -1, 64)
		if !strings.ContainsAny(s, ".eE") {
			s += ".0"
		}
		return s, true
	}
	return n.String(), false
}

// isRangeMap 判断是否为「名称 -> [min,max] 整数二元组」的表（用于生成 map[string][2]int）。
func isRangeMap(m map[string]any) bool {
	if len(m) == 0 {
		return false
	}
	for _, v := range m {
		arr, ok := v.([]any)
		if !ok || len(arr) != 2 {
			return false
		}
		for _, e := range arr {
			n, ok := e.(json.Number)
			if !ok || isFloatNumber(n) {
				return false
			}
		}
	}
	return true
}

// --- GDScript 生成 ---

func renderGDScript(core map[string]any, entries []constEntry) ([]byte, error) {
	var b strings.Builder
	b.WriteString("# 本文件由 tools/genbaseline 自动生成，请勿手改。\n")
	b.WriteString("# 真源：shared/consistency/baseline/（运行 `go run ./tools/genbaseline` 重新生成）。\n")
	b.WriteString("class_name BaselineGenerated\n")
	b.WriteString("extends RefCounted\n\n")

	coreConsts := []struct {
		name  string
		value any
	}{
		{"RANGES", core["ranges"]},
		{"RELATION_ANNUAL_DECAY_K", getPath(core, "defaults", "relation_annual_decay_k")},
		{"MINUTES_PER_DAY", getPath(core, "defaults", "minutes_per_day")},
		{"SPEED_LEVELS", core["speed_levels"]},
		{"DAY_PHASES", core["day_phases"]},
	}
	for _, c := range coreConsts {
		if c.value == nil {
			return nil, fmt.Errorf("core.json 缺少生成 %s 所需字段", c.name)
		}
		typ, lit := gdLiteral(c.value, "")
		fmt.Fprintf(&b, "const %s: %s = %s\n", c.name, typ, lit)
	}

	for _, e := range entries {
		typ, lit := gdLiteral(e.value, "")
		fmt.Fprintf(&b, "\nconst %s: %s = %s\n", e.name, typ, lit)
	}
	return []byte(b.String()), nil
}

func getPath(m map[string]any, keys ...string) any {
	var cur any = m
	for _, k := range keys {
		mm, ok := cur.(map[string]any)
		if !ok {
			return nil
		}
		cur = mm[k]
	}
	return cur
}

func isScalar(v any) bool {
	switch v.(type) {
	case json.Number, bool, string:
		return true
	default:
		return false
	}
}

func allScalar(vs []any) bool {
	for _, v := range vs {
		if !isScalar(v) {
			return false
		}
	}
	return true
}

func allScalarMap(m map[string]any) bool {
	for _, v := range m {
		if !isScalar(v) {
			return false
		}
	}
	return true
}

// gdLiteral 返回 GDScript 类型名与字面量（indent 为当前缩进前缀）。
func gdLiteral(v any, indent string) (string, string) {
	switch t := v.(type) {
	case json.Number:
		return gdNumber(t, indent)
	case bool:
		return "bool", strconv.FormatBool(t)
	case string:
		return "String", strconv.Quote(t)
	case []any:
		if len(t) == 0 {
			return "Array", "[]"
		}
		if allScalar(t) {
			parts := make([]string, len(t))
			for i, e := range t {
				_, lit := gdLiteral(e, indent)
				parts[i] = lit
			}
			return "Array", "[" + strings.Join(parts, ", ") + "]"
		}
		inner := indent + "\t"
		var b strings.Builder
		b.WriteString("[\n")
		for _, e := range t {
			_, lit := gdLiteral(e, inner)
			b.WriteString(inner + lit + ",\n")
		}
		b.WriteString(indent + "]")
		return "Array", b.String()
	case map[string]any:
		if len(t) == 0 {
			return "Dictionary", "{}"
		}
		if allScalarMap(t) {
			parts := make([]string, 0, len(t))
			for _, k := range sortedKeys(t) {
				_, lit := gdLiteral(t[k], indent)
				parts = append(parts, strconv.Quote(k)+": "+lit)
			}
			return "Dictionary", "{" + strings.Join(parts, ", ") + "}"
		}
		inner := indent + "\t"
		var b strings.Builder
		b.WriteString("{\n")
		for _, k := range sortedKeys(t) {
			_, lit := gdLiteral(t[k], inner)
			b.WriteString(inner + strconv.Quote(k) + ": " + lit + ",\n")
		}
		b.WriteString(indent + "}")
		return "Dictionary", b.String()
	default:
		panic(fmt.Sprintf("不支持的字面量类型 %T", v))
	}
}

// --- Go 生成 ---

func renderGo(core map[string]any, entries []constEntry) ([]byte, error) {
	var consts, vars strings.Builder

	addScalar := func(name string, value any) error {
		switch value.(type) {
		case json.Number, bool, string:
			lit, _ := goLiteral(value, "")
			fmt.Fprintf(&consts, "\t%s = %s\n", goName(name), lit)
		default:
			// map/array 用 var 表达。
			typ, lit := goVarLiteral(value, "")
			fmt.Fprintf(&vars, "\t%s %s = %s\n", goName(name), typ, lit)
		}
		return nil
	}

	for _, c := range []struct {
		name  string
		value any
	}{
		{"RANGES", core["ranges"]},
		{"RELATION_ANNUAL_DECAY_K", getPath(core, "defaults", "relation_annual_decay_k")},
		{"MINUTES_PER_DAY", getPath(core, "defaults", "minutes_per_day")},
		{"SPEED_LEVELS", core["speed_levels"]},
		{"DAY_PHASES", core["day_phases"]},
	} {
		if c.value == nil {
			return nil, fmt.Errorf("core.json 缺少生成 %s 所需字段", c.name)
		}
		if err := addScalar(c.name, c.value); err != nil {
			return nil, err
		}
	}
	seen := map[string]string{}
	for _, e := range entries {
		if prev, ok := seen[e.name]; ok {
			return nil, fmt.Errorf("常量名冲突 %s（与 %s）", e.name, prev)
		}
		seen[e.name] = "entry"
		if err := addScalar(e.name, e.value); err != nil {
			return nil, err
		}
	}

	var b strings.Builder
	b.WriteString("// Code generated by tools/genbaseline; DO NOT EDIT.\n")
	b.WriteString("// Source: shared/consistency/baseline/ (run `go run ./tools/genbaseline` to regenerate).\n\n")
	b.WriteString("package sim\n\n")
	if consts.Len() > 0 {
		b.WriteString("const (\n")
		b.WriteString(consts.String())
		b.WriteString(")\n\n")
	}
	if vars.Len() > 0 {
		b.WriteString("var (\n")
		b.WriteString(vars.String())
		b.WriteString(")\n")
	}
	formatted, err := format.Source([]byte(b.String()))
	if err != nil {
		return nil, fmt.Errorf("生成 Go 代码格式化失败: %w", err)
	}
	return formatted, nil
}

// goName 把 UPPER_SNAKE 常量名转为 Baseline 前缀 + PascalCase。
func goName(name string) string {
	var b strings.Builder
	b.WriteString("Baseline")
	for _, part := range strings.Split(name, "_") {
		if part == "" {
			continue
		}
		b.WriteString(strings.ToUpper(part[:1]))
		b.WriteString(strings.ToLower(part[1:]))
	}
	return b.String()
}

func goLiteral(v any, indent string) (string, bool) {
	switch t := v.(type) {
	case json.Number:
		lit, isFloat := goNumber(t)
		return lit, isFloat
	case bool:
		return strconv.FormatBool(t), false
	case string:
		return strconv.Quote(t), false
	default:
		panic(fmt.Sprintf("goLiteral 不支持 %T", v))
	}
}

func goVarLiteral(v any, indent string) (string, string) {
	switch t := v.(type) {
	case []any:
		if len(t) == 0 {
			return "[]any", "[]any{}"
		}
		if allScalar(t) {
			parts := make([]string, len(t))
			for i, e := range t {
				lit, _ := goLiteral(e, indent)
				parts[i] = lit
			}
			return "[]any", "[]any{" + strings.Join(parts, ", ") + "}"
		}
		inner := indent + "\t"
		var b strings.Builder
		b.WriteString("[]any{\n")
		for _, e := range t {
			_, lit := goElement(e, inner)
			b.WriteString(inner + lit + ",\n")
		}
		b.WriteString(indent + "}")
		return "[]any", b.String()
	case map[string]any:
		if len(t) == 0 {
			return "map[string]any", "map[string]any{}"
		}
		if isRangeMap(t) {
			inner := indent + "\t"
			var b strings.Builder
			b.WriteString("map[string][2]int{\n")
			for _, k := range sortedKeys(t) {
				arr := t[k].([]any)
				a, _ := goNumber(arr[0].(json.Number))
				c, _ := goNumber(arr[1].(json.Number))
				b.WriteString(inner + strconv.Quote(k) + ": {" + a + ", " + c + "},\n")
			}
			b.WriteString(indent + "}")
			return "map[string][2]int", b.String()
		}
		if allScalarMap(t) {
			parts := make([]string, 0, len(t))
			for _, k := range sortedKeys(t) {
				lit, _ := goLiteral(t[k], indent)
				parts = append(parts, strconv.Quote(k)+": "+lit)
			}
			return "map[string]any", "map[string]any{" + strings.Join(parts, ", ") + "}"
		}
		inner := indent + "\t"
		var b strings.Builder
		b.WriteString("map[string]any{\n")
		for _, k := range sortedKeys(t) {
			_, lit := goElement(t[k], inner)
			b.WriteString(inner + strconv.Quote(k) + ": " + lit + ",\n")
		}
		b.WriteString(indent + "}")
		return "map[string]any", b.String()
	default:
		panic(fmt.Sprintf("goVarLiteral 不支持 %T", v))
	}
}

// goElement 为容器元素生成字面量（容器元素统一用 any / []any / map[string]any）。
func goElement(v any, indent string) (string, string) {
	switch v.(type) {
	case []any, map[string]any:
		return goVarLiteral(v, indent)
	default:
		lit, _ := goLiteral(v, indent)
		return "", lit
	}
}

// --- 一致性快照 ---

func renderVector(core map[string]any) ([]byte, error) {
	raw, err := json.MarshalIndent(core, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(raw, '\n'), nil
}
