package main

import (
	"reflect"
	"testing"
)

func TestPackRoundTrip(t *testing.T) {
	entries := []entry{
		{Key: "occupation.engineer", Fields: map[string]any{"name": "工程师", "level": 3, "skills": []any{"skill.coding"}}},
		{Key: "occupation.teacher", Fields: map[string]any{"name": "教师", "level": 2}},
	}
	data, err := EncodePack("jobs", "data", entries)
	if err != nil {
		t.Fatal(err)
	}
	category, kind, got, err := DecodePack(data)
	if err != nil {
		t.Fatal(err)
	}
	if category != "jobs" || kind != "data" {
		t.Fatalf("元数据不匹配: %s/%s", category, kind)
	}
	if len(got) != 2 {
		t.Fatalf("条目数不匹配: %d", len(got))
	}
	if got["occupation.engineer"]["name"] != "工程师" {
		t.Fatalf("条目内容不匹配: %v", got["occupation.engineer"])
	}
}

func TestContentVersionStable(t *testing.T) {
	a := []entry{
		{Key: "a", Fields: map[string]any{"n": 1}},
		{Key: "b", Fields: map[string]any{"n": 2}},
	}
	b := []entry{
		{Key: "b", Fields: map[string]any{"n": 2}},
		{Key: "a", Fields: map[string]any{"n": 1}},
	}
	if contentVersion("x", "data", a) != contentVersion("x", "data", b) {
		t.Fatal("版本应与条目顺序无关")
	}
	c := []entry{
		{Key: "a", Fields: map[string]any{"n": 9}},
		{Key: "b", Fields: map[string]any{"n": 2}},
	}
	if contentVersion("x", "data", a) == contentVersion("x", "data", c) {
		t.Fatal("内容变化应导致版本变化")
	}
}

func TestDiffEntries(t *testing.T) {
	prev := map[string]map[string]any{
		"k1": {"n": 1},
		"k2": {"n": 2},
	}
	next := map[string]map[string]any{
		"k2": {"n": 2},
		"k3": {"n": 3},
	}
	added, changed, removed := diffEntries(prev, next)
	if !reflect.DeepEqual(added, []string{"k3"}) {
		t.Fatalf("added=%v", added)
	}
	if len(changed) != 0 {
		t.Fatalf("changed=%v", changed)
	}
	if !reflect.DeepEqual(removed, []string{"k1"}) {
		t.Fatalf("removed=%v", removed)
	}
}

func TestDiffManifests(t *testing.T) {
	prev := manifest{ManifestVersion: 1, Packs: []manifestPack{
		{Name: "jobs", Kind: "data", Hash: "sha256:aaa"},
		{Name: "items", Kind: "data", Hash: "sha256:bbb"},
	}}
	next := manifest{ManifestVersion: 2, Packs: []manifestPack{
		{Name: "jobs", Kind: "data", Hash: "sha256:ccc"},
		{Name: "skills", Kind: "data", Hash: "sha256:ddd"},
	}}
	d := diffManifests(prev, next)
	status := map[string]string{}
	for _, p := range d.Packs {
		status[p.Name] = p.Status
	}
	if status["jobs"] != "changed" || status["skills"] != "added" || status["items"] != "removed" {
		t.Fatalf("状态不匹配: %v", status)
	}
}

// TestPatchEquivalence 验证「差量更新后」与「全量发布」结果等价（任务 23.3）。
func TestPatchEquivalence(t *testing.T) {
	prevEntries := []entry{
		{Key: "item.apple", Fields: map[string]any{"name": "苹果", "price": 100}},
		{Key: "item.pear", Fields: map[string]any{"name": "梨", "price": 120}},
		{Key: "item.gone", Fields: map[string]any{"name": "停产", "price": 1}},
	}
	nextEntries := []entry{
		{Key: "item.apple", Fields: map[string]any{"name": "苹果", "price": 150}}, // changed
		{Key: "item.pear", Fields: map[string]any{"name": "梨", "price": 120}},   // unchanged
		{Key: "item.banana", Fields: map[string]any{"name": "香蕉", "price": 80}}, // added
	}
	prev := entriesMap(prevEntries)
	next := entriesMap(nextEntries)
	added, changed, removed := diffEntries(prev, next)
	patch := patchEntries(next, changed, added)
	got := applyPackPatch(prev, patch, removed)
	if !reflect.DeepEqual(got, next) {
		t.Fatalf("差量结果与全量不等价:\n got=%v\nwant=%v", got, next)
	}
}

// TestBuildPatches 验证 buildPatches 生成的差量包可还原为全量发布。
func TestBuildPatches(t *testing.T) {
	prev := map[string]*rawCategory{
		"items": {Name: "items", Entries: []entry{
			{Key: "item.apple", Fields: map[string]any{"name": "苹果", "price": 100}},
			{Key: "item.gone", Fields: map[string]any{"name": "停产", "price": 1}},
		}},
	}
	next := map[string]*rawCategory{
		"items": {Name: "items", Entries: []entry{
			{Key: "item.apple", Fields: map[string]any{"name": "苹果", "price": 150}},
			{Key: "item.banana", Fields: map[string]any{"name": "香蕉", "price": 80}},
		}},
	}
	patches := buildPatches(prev, next)
	if len(patches) != 1 {
		t.Fatalf("应生成 1 个差量包, got=%d", len(patches))
	}
	p := patches[0]
	if p.PatchOf != "items" {
		t.Fatalf("patch_of 应为 items, got=%s", p.PatchOf)
	}
	base := entriesMap(prev["items"].Entries)
	patchList := make([]entry, 0, len(p.Entries))
	for k, v := range p.Entries {
		patchList = append(patchList, entry{Key: k, Fields: v})
	}
	got := applyPackPatch(base, patchList, p.Removed)
	want := entriesMap(next["items"].Entries)
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("差量更新后与全量发布不等价:\n got=%v\nwant=%v", got, want)
	}
	// 删除列表应自包含于差量包，便于客户端无需额外 sidecar 即可应用。
	_, _, decoded, err := DecodePack(p.data)
	if err != nil {
		t.Fatalf("差量包应可解码: %v", err)
	}
	if _, ok := decoded[ReservedRemovedKey]; !ok {
		t.Fatalf("差量包应内嵌 %s 删除列表", ReservedRemovedKey)
	}
}
