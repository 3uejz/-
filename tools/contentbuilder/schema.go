package main

import (
	"fmt"
	"regexp"
	"sort"
)

// 字段类型。
type fieldType int

const (
	tString fieldType = iota
	tInt
	tFloat
	tBool
	tStringList
)

type fieldSpec struct {
	name     string
	typ      fieldType
	required bool
}

type categorySpec struct {
	// 类别名，对应 content/catalog/<name>.json|csv 与 pack 名。
	name string
	// 打包类型：core / data / art。
	kind string
	// 字段定义。
	fields []fieldSpec
	// 字段名 -> 目标类别（跨引用校验），被引用类别以 content_key 为键。
	crossRefs map[string]string
}

var contentKeyPattern = regexp.MustCompile(`^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$`)

// categorySpecs 是内容类别的硬性 schema（必填、类型、跨引用）。
var categorySpecs = map[string]categorySpec{
	"jobs": {name: "jobs", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"industry", tString, true},
		{"level", tInt, true}, {"salary_base", tInt, true}, {"skills", tStringList, false}, {"entry", tString, false},
	}, crossRefs: map[string]string{"skills": "skills"}},
	"skills": {name: "skills", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"domain", tString, true},
		{"max_level", tInt, true}, {"prereq", tStringList, false},
	}, crossRefs: map[string]string{"prereq": "skills"}},
	"items": {name: "items", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"category", tString, true},
		{"quality", tString, true}, {"price", tInt, true}, {"weight", tFloat, false},
	}},
	"events": {name: "events", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"type", tString, true},
		{"weight", tInt, true}, {"priority", tInt, true},
	}},
	"achievements": {name: "achievements", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"category", tString, true},
		{"metric", tString, true}, {"threshold", tFloat, true},
	}},
	"codex": {name: "codex", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"category", tString, true}, {"description", tString, true},
	}},
	"certificates": {name: "certificates", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"issuer", tString, true},
	}},
	"diseases": {name: "diseases", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"category", tString, true}, {"severity", tInt, true},
	}},
	"finance": {name: "finance", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"kind", tString, true}, {"risk", tFloat, true},
	}},
	"anomalies": {name: "anomalies", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"containment", tString, true}, {"threat", tString, true}, {"class", tString, true},
	}},
	"entertainment": {name: "entertainment", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"category", tString, true},
		{"fee", tInt, true}, {"minutes", tInt, true},
	}},
	"transport": {name: "transport", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"kind", tString, true}, {"speed", tFloat, true},
	}},
	"awards": {name: "awards", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"field", tString, true},
	}},
	"organizations": {name: "organizations", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"kind", tString, true},
	}},
	"languages": {name: "languages", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"region", tString, true},
	}},
	"festivals": {name: "festivals", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"month", tInt, true}, {"day", tInt, true},
	}},
	"manufacturing": {name: "manufacturing", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"era", tInt, true}, {"inputs", tStringList, false},
	}, crossRefs: map[string]string{"inputs": "items"}},
	"activities": {name: "activities", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"kind", tString, true},
	}},
	"goldfingers": {name: "goldfingers", kind: "data", fields: []fieldSpec{
		{"content_key", tString, true}, {"name", tString, true}, {"rarity", tString, true},
		{"category", tString, true}, {"description", tString, true},
	}},
}

// categoryOrder 稳定输出顺序。
func categoryOrder() []string {
	names := make([]string, 0, len(categorySpecs))
	for name := range categorySpecs {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// issue 是一条可定位的校验错误。
type issue struct {
	File     string
	Category string
	Key      string
	Message  string
}

func (i issue) String() string {
	return fmt.Sprintf("%s [%s %s] %s", i.File, i.Category, i.Key, i.Message)
}

// entry 是一条内容，content_key 为稳定主键。
type entry struct {
	Key    string
	Fields map[string]any
}

func fieldTypeName(t fieldType) string {
	switch t {
	case tString:
		return "string"
	case tInt:
		return "int"
	case tFloat:
		return "number"
	case tBool:
		return "bool"
	case tStringList:
		return "[]string"
	}
	return "unknown"
}

func typeOK(t fieldType, v any) bool {
	switch t {
	case tString:
		_, ok := v.(string)
		return ok
	case tInt:
		_, ok := v.(int)
		return ok
	case tFloat:
		switch v.(type) {
		case float64, int:
			return true
		}
		return false
	case tBool:
		_, ok := v.(bool)
		return ok
	case tStringList:
		arr, ok := v.([]any)
		if !ok {
			return false
		}
		for _, x := range arr {
			if _, ok := x.(string); !ok {
				return false
			}
		}
		return true
	}
	return false
}
