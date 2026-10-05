package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// assetEntry 是一条美术/音频资产台账记录（R36.11、design §597 素材台账）。
type assetEntry struct {
	Name      string   `json:"name"`
	Path      string   `json:"path"`
	Kind      string   `json:"kind"` // model | texture | audio | other
	Size      int      `json:"size"`
	Hash      string   `json:"hash"`
	LODTiers  []string `json:"lod_tiers,omitempty"`
	License   string   `json:"license,omitempty"`
	SourceURL string   `json:"source_url,omitempty"`
}

type assetLedger struct {
	GeneratedAt string       `json:"generated_at"`
	Assets      []assetEntry `json:"assets"`
}

// 默认 LOD 分层；Blender 导出时按此命名。
var defaultLODTiers = []string{"LOD0", "LOD1", "LOD2"}

func assetKind(ext string) string {
	switch strings.ToLower(ext) {
	case ".glb", ".gltf", ".fbx", ".obj":
		return "model"
	case ".png", ".jpg", ".jpeg", ".webp", ".tga", ".exr":
		return "texture"
	case ".ogg", ".wav", ".mp3":
		return "audio"
	}
	return "other"
}

func lodTiersFor(kind string) []string {
	if kind == "model" {
		return append([]string{}, defaultLODTiers...)
	}
	return nil
}

// scanAssets 递归扫描目录，生成资产台账（不含源 URL，除非有 .license.json 旁注）。
func scanAssets(dir string) (assetLedger, error) {
	ledger := assetLedger{GeneratedAt: nowUTC()}
	err := filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		ext := filepath.Ext(path)
		if ext == ".json" || ext == ".import" || ext == ".uid" {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(dir, path)
		kind := assetKind(ext)
		entry := assetEntry{
			Name:     strings.TrimSuffix(filepath.Base(path), ext),
			Path:     filepath.ToSlash(rel),
			Kind:     kind,
			Size:     len(data),
			Hash:     sha256Hex(data),
			LODTiers: lodTiersFor(kind),
		}
		if lic, ok := readLicenseSidecar(path); ok {
			entry.License = lic.License
			entry.SourceURL = lic.SourceURL
		}
		ledger.Assets = append(ledger.Assets, entry)
		return nil
	})
	sort.Slice(ledger.Assets, func(i, j int) bool { return ledger.Assets[i].Path < ledger.Assets[j].Path })
	return ledger, err
}

type licenseInfo struct {
	License   string `json:"license"`
	SourceURL string `json:"source_url"`
}

func readLicenseSidecar(assetPath string) (licenseInfo, bool) {
	side := assetPath + ".license.json"
	data, err := os.ReadFile(side)
	if err != nil {
		return licenseInfo{}, false
	}
	var info licenseInfo
	if err := json.Unmarshal(data, &info); err != nil {
		return licenseInfo{}, false
	}
	return info, true
}

func writeLedger(path string, ledger assetLedger) error {
	data, err := json.MarshalIndent(ledger, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	_, err = writeFile(path, data)
	return err
}
