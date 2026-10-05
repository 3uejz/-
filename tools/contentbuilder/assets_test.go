package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestScanAssets(t *testing.T) {
	dir := t.TempDir()
	// 伪造一个模型资产与许可旁注。
	model := filepath.Join(dir, "bench.glb")
	if err := os.WriteFile(model, []byte("fake-glb-bytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(model+".license.json", []byte(`{"license":"CC0","source_url":"https://example.com/bench"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	// 一张贴图（无旁注）。
	if err := os.WriteFile(filepath.Join(dir, "wood.png"), []byte("png"), 0o644); err != nil {
		t.Fatal(err)
	}
	// 忽略的元数据文件。
	if err := os.WriteFile(filepath.Join(dir, "meta.json"), []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}

	ledger, err := scanAssets(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(ledger.Assets) != 2 {
		t.Fatalf("期望 2 项资产，得到 %d: %+v", len(ledger.Assets), ledger.Assets)
	}
	// 排序后 bench.glb 在前。
	modelEntry := ledger.Assets[0]
	if modelEntry.Kind != "model" {
		t.Errorf("bench.glb kind=%q，期望 model", modelEntry.Kind)
	}
	if len(modelEntry.LODTiers) != 3 {
		t.Errorf("模型应有 3 层 LOD，得到 %v", modelEntry.LODTiers)
	}
	if modelEntry.License != "CC0" || modelEntry.SourceURL != "https://example.com/bench" {
		t.Errorf("许可旁注未解析: %+v", modelEntry)
	}
	if modelEntry.Hash != sha256Hex([]byte("fake-glb-bytes")) {
		t.Errorf("hash 不匹配: %s", modelEntry.Hash)
	}
	if ledger.Assets[1].Kind != "texture" {
		t.Errorf("wood.png kind=%q，期望 texture", ledger.Assets[1].Kind)
	}
	if len(ledger.Assets[1].LODTiers) != 0 {
		t.Errorf("贴图不应有 LOD 层: %v", ledger.Assets[1].LODTiers)
	}
}
