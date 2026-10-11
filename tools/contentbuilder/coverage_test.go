package main

import (
	"strings"
	"testing"
)

func TestCoverageReportsShortfall(t *testing.T) {
	cat := map[string]*rawCategory{
		"sites": {Name: "sites", Entries: []entry{
			{Key: "site.a", Fields: map[string]any{"name": "A"}},
		}},
	}
	issues := Coverage(cat)
	foundShort := false
	for _, is := range issues {
		if is.Category == "sites" && strings.Contains(is.Message, "未达 R56 下限") {
			foundShort = true
		}
	}
	if !foundShort {
		t.Fatalf("应报告 sites 未达下限, issues=%v", issues)
	}
}

func TestCoverageSubTarget(t *testing.T) {
	cat := map[string]*rawCategory{
		"diseases": {Name: "diseases", Entries: []entry{
			{Key: "disease.a", Fields: map[string]any{"name": "A", "category": "精神"}},
			{Key: "disease.b", Fields: map[string]any{"name": "B", "category": "常见"}},
		}},
	}
	issues := Coverage(cat)
	found := false
	for _, is := range issues {
		if strings.Contains(is.Message, "精神疾病") {
			found = true
		}
	}
	if !found {
		t.Fatalf("应报告精神疾病子指标不足, issues=%v", issues)
	}
}
