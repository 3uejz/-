package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeJSON(t *testing.T, dir, name string, v any) {
	t.Helper()
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, name), data, 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestValidateDetectsMissingField(t *testing.T) {
	dir := t.TempDir()
	writeJSON(t, dir, "jobs.json", map[string]any{
		"category": "jobs",
		"entries": []map[string]any{
			{"content_key": "occupation.engineer", "name": "工程师", "industry": "technology", "level": 3},
		},
	})
	cat, _ := LoadCatalog(dir)
	issues := Validate(cat)
	if !hasIssue(issues, "缺少必填字段 salary_base") {
		t.Fatalf("应检测到缺失字段, issues=%v", issues)
	}
}

func TestValidateCrossReference(t *testing.T) {
	dir := t.TempDir()
	writeJSON(t, dir, "skills.json", map[string]any{
		"category": "skills",
		"entries": []map[string]any{
			{"content_key": "skill.coding", "name": "编程", "domain": "technology", "max_level": 5},
		},
	})
	writeJSON(t, dir, "jobs.json", map[string]any{
		"category": "jobs",
		"entries": []map[string]any{
			{"content_key": "occupation.engineer", "name": "工程师", "industry": "technology", "level": 3, "salary_base": 1500000, "skills": []string{"skill.coding", "skill.missing"}},
		},
	})
	cat, _ := LoadCatalog(dir)
	issues := Validate(cat)
	if !hasIssue(issues, "引用不存在的内容键 skill.missing") {
		t.Fatalf("应检测到断链引用, issues=%v", issues)
	}
	if hasIssue(issues, "skill.coding") {
		t.Fatalf("存在的引用不应报错: %v", issues)
	}
}

func TestValidateDetectsDuplicateKey(t *testing.T) {
	dir := t.TempDir()
	writeJSON(t, dir, "items.json", map[string]any{
		"category": "items",
		"entries": []map[string]any{
			{"content_key": "item.apple", "name": "苹果", "category": "food", "quality": "common", "price": 100},
			{"content_key": "item.apple", "name": "苹果2", "category": "food", "quality": "common", "price": 100},
		},
	})
	cat, _ := LoadCatalog(dir)
	issues := Validate(cat)
	if !hasIssue(issues, "重复 content_key") {
		t.Fatalf("应检测到重复键, issues=%v", issues)
	}
}

func TestValidateAcceptsValidCatalog(t *testing.T) {
	dir := t.TempDir()
	writeJSON(t, dir, "skills.json", map[string]any{
		"category": "skills",
		"entries": []map[string]any{
			{"content_key": "skill.coding", "name": "编程", "domain": "technology", "max_level": 5},
		},
	})
	writeJSON(t, dir, "jobs.json", map[string]any{
		"category": "jobs",
		"entries": []map[string]any{
			{"content_key": "occupation.engineer", "name": "工程师", "industry": "technology", "level": 3, "salary_base": 1500000, "skills": []string{"skill.coding"}},
		},
	})
	cat, loadIssues := LoadCatalog(dir)
	if len(loadIssues) > 0 {
		t.Fatalf("加载不应报错: %v", loadIssues)
	}
	if issues := Validate(cat); len(issues) > 0 {
		t.Fatalf("合法目录不应报错: %v", issues)
	}
}

func hasIssue(issues []issue, substr string) bool {
	for _, is := range issues {
		if strings.Contains(is.Message, substr) {
			return true
		}
	}
	return false
}
