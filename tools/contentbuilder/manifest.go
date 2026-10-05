package main

import (
	"bytes"
	"encoding/json"
	"os"
	"sort"
	"time"
)

// manifestPack 对齐 content-manifest.schema.json#/$defs/pack。
type manifestPack struct {
	Name      string   `json:"name"`
	Kind      string   `json:"kind"`
	Version   string   `json:"version"`
	Hash      string   `json:"hash"`
	Size      int      `json:"size"`
	URL       string   `json:"url"`
	PatchOf   *string  `json:"patch_of,omitempty"`
	RegionKey string   `json:"region_key,omitempty"`
	DependsOn []string `json:"depends_on,omitempty"`
}

// manifest 对齐 content-manifest.schema.json。
type manifest struct {
	ManifestVersion  int            `json:"manifest_version"`
	GeneratedAt      string         `json:"generated_at"`
	MinClientVersion string         `json:"min_client_version,omitempty"`
	Packs            []manifestPack `json:"packs"`
}

// builtPack 是一个已编码的内容包及其元数据。
type builtPack struct {
	Name      string
	Kind      string
	Version   string
	Hash      string
	Size      int
	Path      string
	DependsOn []string
	Category  string
	Entries   map[string]map[string]any
	// PatchOf 非空时表示这是基础包的差量包。
	PatchOf string
	// Removed 是差量包需要删除的 content_key（仅差量有意义）。
	Removed []string
}

// contentVersion 依据条目内容计算稳定版本（与顺序无关）。
func contentVersion(category, kind string, entries []entry) string {
	keys := make([]string, 0, len(entries))
	byKey := map[string]entry{}
	for _, e := range entries {
		keys = append(keys, e.Key)
		byKey[e.Key] = e
	}
	sort.Strings(keys)
	var buf bytes.Buffer
	buf.WriteString(category + "|" + kind + "\n")
	for _, k := range keys {
		payload, _ := json.Marshal(byKey[k].Fields)
		buf.WriteString(k + "=" + string(payload) + "\n")
	}
	sum := sha256Hex(buf.Bytes())
	return sum[len("sha256:") : len("sha256:")+16]
}

// buildManifest 汇总已构建内容包生成清单。
func buildManifest(packs []builtPack, generatedAt, minClientVersion, baseURL string, manifestVersion int) manifest {
	m := manifest{ManifestVersion: manifestVersion, GeneratedAt: generatedAt, MinClientVersion: minClientVersion}
	for _, p := range packs {
		url := baseURL + "/" + p.Name + ".ltpack"
		mp := manifestPack{
			Name: p.Name, Kind: p.Kind, Version: p.Version, Hash: p.Hash,
			Size: p.Size, URL: url, DependsOn: p.DependsOn,
		}
		if p.PatchOf != "" {
			patchOf := p.PatchOf
			mp.PatchOf = &patchOf
		}
		m.Packs = append(m.Packs, mp)
	}
	return m
}

func writeManifest(path string, m manifest) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	_, err = writeFile(path, data)
	return err
}

func readManifest(path string) (manifest, error) {
	var m manifest
	data, err := os.ReadFile(path)
	if err != nil {
		return m, err
	}
	err = json.Unmarshal(data, &m)
	return m, err
}

func nowUTC() string {
	return time.Now().UTC().Format(time.RFC3339)
}
