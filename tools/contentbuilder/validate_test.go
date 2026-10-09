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

func TestLoadCSVCategory(t *testing.T) {
	dir := t.TempDir()
	csvBody := "content_key,name,domain,max_level,prereq\n" +
		"skill.coding,编程,technology,5,\n" +
		"skill.debug,调试,technology,3,skill.coding\n"
	if err := os.WriteFile(filepath.Join(dir, "skills.csv"), []byte(csvBody), 0o644); err != nil {
		t.Fatal(err)
	}
	cat, loadIssues := LoadCatalog(dir)
	if len(loadIssues) > 0 {
		t.Fatalf("CSV 加载不应报错: %v", loadIssues)
	}
	skills := cat["skills"]
	if skills == nil || len(skills.Entries) != 2 {
		t.Fatalf("应加载 2 条技能, got %+v", skills)
	}
	if skills.File != filepath.Join(dir, "skills.csv") {
		t.Fatalf("来源文件应为 csv, got %s", skills.File)
	}
	if issues := Validate(cat); len(issues) > 0 {
		t.Fatalf("CSV 目录不应报错: %v", issues)
	}
}

func TestValidateNewDomainCategories(t *testing.T) {
	dir := t.TempDir()
	// 任务 50 新增类别：债务产品、医疗分科、交通基建。
	writeJSON(t, dir, "debt_products.json", map[string]any{
		"category": "debt_products",
		"entries": []map[string]any{
			{"content_key": "debt.pawn", "name": "典当", "kind": "pawn", "annual_rate": 0.24},
		},
	})
	writeJSON(t, dir, "medical_services.json", map[string]any{
		"category": "medical_services",
		"entries": []map[string]any{
			{"content_key": "medical.ivf", "name": "辅助生殖", "department": "fertility", "base_success": 0.45},
		},
	})
	writeJSON(t, dir, "infra_projects.json", map[string]any{
		"category": "infra_projects",
		"entries": []map[string]any{
			{"content_key": "infra.railway", "name": "铁路", "mode": "rail", "capacity": 1.0},
		},
	})
	cat, loadIssues := LoadCatalog(dir)
	if len(loadIssues) > 0 {
		t.Fatalf("加载不应报错: %v", loadIssues)
	}
	if cat["debt_products"] == nil || cat["medical_services"] == nil || cat["infra_projects"] == nil {
		t.Fatalf("应加载三个新类别")
	}
	if issues := Validate(cat); len(issues) > 0 {
		t.Fatalf("新类别合法目录不应报错: %v", issues)
	}
	// 缺必填字段应被硬阻断。
	writeJSON(t, dir, "funeral_services.json", map[string]any{
		"category": "funeral_services",
		"entries": []map[string]any{
			{"content_key": "funeral.cremation", "name": "火化", "kind": "cremation"},
		},
	})
	cat2, _ := LoadCatalog(dir)
	if issues := Validate(cat2); !hasIssue(issues, "缺少必填字段 cost") {
		t.Fatalf("新类别缺字段应报错, issues=%v", issues)
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
