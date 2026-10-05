package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

const (
	defaultCatalogDir = "content/catalog"
	defaultOutDir     = "build/content"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "validate":
		os.Exit(runValidate(os.Args[2:]))
	case "build":
		os.Exit(runBuild(os.Args[2:]))
	case "diff":
		os.Exit(runDiff(os.Args[2:]))
	case "patch":
		os.Exit(runPatch(os.Args[2:]))
	case "sample":
		os.Exit(runSample(os.Args[2:]))
	case "assets":
		os.Exit(runAssets(os.Args[2:]))
	case "-h", "--help", "help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "未知命令: %s\n", os.Args[1])
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `contentbuilder - 浮生录内容构建与校验工具

用法:
  contentbuilder validate [--catalog DIR]
  contentbuilder build    [--catalog DIR] [--out DIR] [--base-url URL] [--version N]
  contentbuilder diff     --prev MANIFEST --next MANIFEST [--prev-catalog DIR] [--next-catalog DIR]
  contentbuilder patch    --prev-catalog DIR --next-catalog DIR [--out DIR] [--base-url URL] [--version N]
  contentbuilder sample   [--catalog DIR]
  contentbuilder assets   --dir ART_DIR [--out LEDGER.json]
`)
}

func loadAndValidate(catalogDir string) (map[string]*rawCategory, []issue) {
	cat, issues := LoadCatalog(catalogDir)
	if len(issues) > 0 {
		return cat, issues
	}
	return cat, Validate(cat)
}

func runValidate(args []string) int {
	fs := flag.NewFlagSet("validate", flag.ContinueOnError)
	catalogDir := fs.String("catalog", defaultCatalogDir, "内容源目录")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	_, issues := loadAndValidate(*catalogDir)
	if len(issues) > 0 {
		for _, is := range issues {
			fmt.Fprintln(os.Stderr, "错误:", is.String())
		}
		fmt.Fprintf(os.Stderr, "校验失败：%d 个问题\n", len(issues))
		return 1
	}
	fmt.Println("校验通过")
	return 0
}

func runBuild(args []string) int {
	fs := flag.NewFlagSet("build", flag.ContinueOnError)
	catalogDir := fs.String("catalog", defaultCatalogDir, "内容源目录")
	outDir := fs.String("out", defaultOutDir, "内容包输出目录")
	baseURL := fs.String("base-url", "/content", "内容包下载地址前缀")
	version := fs.Int("version", 1, "清单版本号")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	cat, issues := loadAndValidate(*catalogDir)
	if len(issues) > 0 {
		for _, is := range issues {
			fmt.Fprintln(os.Stderr, "错误:", is.String())
		}
		fmt.Fprintf(os.Stderr, "拒绝构建：%d 个校验问题\n", len(issues))
		return 1
	}
	var packs []builtPack
	for _, name := range categoryOrder() {
		c, ok := cat[name]
		if !ok || len(c.Entries) == 0 {
			continue
		}
		spec := categorySpecs[name]
		data, err := EncodePack(name, spec.kind, c.Entries)
		if err != nil {
			fmt.Fprintln(os.Stderr, "编码失败:", err)
			return 1
		}
		path := filepath.Join(*outDir, name+".ltpack")
		if _, err := writeFile(path, data); err != nil {
			fmt.Fprintln(os.Stderr, "写入失败:", err)
			return 1
		}
		pack := builtPack{
			Name: name, Kind: spec.kind, Version: contentVersion(name, spec.kind, c.Entries),
			Hash: sha256Hex(data), Size: len(data), Path: path, Category: name,
		}
		if decoded, _, entries, err := DecodePack(data); err != nil || decoded != name || len(entries) != len(c.Entries) {
			fmt.Fprintf(os.Stderr, "内容包自检失败 %s: %v\n", name, err)
			return 1
		}
		packs = append(packs, pack)
	}
	m := buildManifest(packs, nowUTC(), "", *baseURL, *version)
	manifestPath := filepath.Join(*outDir, "manifest.json")
	if err := writeManifest(manifestPath, m); err != nil {
		fmt.Fprintln(os.Stderr, "写入清单失败:", err)
		return 1
	}
	fmt.Printf("构建完成：%d 个内容包 -> %s\n", len(packs), manifestPath)
	return 0
}

// buildPatches 对比新旧内容源，为每个发生变化的类别生成差量包。
func buildPatches(prev, next map[string]*rawCategory) []builtPack {
	names := map[string]bool{}
	for n := range next {
		names[n] = true
	}
	for n := range prev {
		names[n] = true
	}
	ordered := make([]string, 0, len(names))
	for n := range names {
		if _, ok := categorySpecs[n]; ok {
			ordered = append(ordered, n)
		}
	}
	sort.Strings(ordered)

	var out []builtPack
	for _, name := range ordered {
		spec := categorySpecs[name]
		var prevEntries, nextEntries []entry
		if c, ok := prev[name]; ok {
			prevEntries = c.Entries
		}
		if c, ok := next[name]; ok {
			nextEntries = c.Entries
		}
		pe := entriesMap(prevEntries)
		ne := entriesMap(nextEntries)
		added, changed, removed := diffEntries(pe, ne)
		if len(added)+len(changed)+len(removed) == 0 {
			continue
		}
		delta := patchEntries(ne, changed, added)
		encoded := delta
		if len(removed) > 0 {
			keys := make([]any, len(removed))
			for i, r := range removed {
				keys[i] = r
			}
			encoded = append(append([]entry{}, delta...), entry{
				Key:    ReservedRemovedKey,
				Fields: map[string]any{"keys": keys},
			})
		}
		data, err := EncodePack(name, spec.kind, encoded)
		if err != nil {
			continue
		}
		out = append(out, builtPack{
			Name:     fmt.Sprintf("%s.patch-%s", name, contentVersion(name, spec.kind, nextEntries)),
			Kind:     spec.kind,
			Version:  contentVersion(name, spec.kind, delta),
			Hash:     sha256Hex(data),
			Size:     len(data),
			Category: name,
			PatchOf:  name,
			Removed:  removed,
			Entries:  entriesMap(delta),
			data:     data,
		})
	}
	return out
}

func runPatch(args []string) int {
	fs := flag.NewFlagSet("patch", flag.ContinueOnError)
	prevCatalog := fs.String("prev-catalog", "", "旧内容源目录")
	nextCatalog := fs.String("next-catalog", "", "新内容源目录")
	outDir := fs.String("out", defaultOutDir, "差量包输出目录")
	baseURL := fs.String("base-url", "/content", "内容包下载地址前缀")
	version := fs.Int("version", 1, "清单版本号")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *prevCatalog == "" || *nextCatalog == "" {
		fmt.Fprintln(os.Stderr, "patch 需要 --prev-catalog 与 --next-catalog")
		return 2
	}
	prev, prevIssues := LoadCatalog(*prevCatalog)
	if len(prevIssues) > 0 {
		for _, is := range prevIssues {
			fmt.Fprintln(os.Stderr, "错误:", is.String())
		}
		return 1
	}
	next, issues := loadAndValidate(*nextCatalog)
	if len(issues) > 0 {
		for _, is := range issues {
			fmt.Fprintln(os.Stderr, "错误:", is.String())
		}
		fmt.Fprintf(os.Stderr, "拒绝构建：%d 个校验问题\n", len(issues))
		return 1
	}
	patches := buildPatches(prev, next)
	if len(patches) == 0 {
		fmt.Println("无内容变化，无需差量包")
		return 0
	}
	var manifestPacks []builtPack
	for _, p := range patches {
		path := filepath.Join(*outDir, p.Name+".ltpack")
		if _, err := writeFile(path, p.data); err != nil {
			fmt.Fprintln(os.Stderr, "写入差量失败:", err)
			return 1
		}
		meta, _ := json.MarshalIndent(map[string]any{"patch_of": p.PatchOf, "removed": p.Removed}, "", "  ")
		meta = append(meta, '\n')
		if _, err := writeFile(filepath.Join(*outDir, p.Name+".removals.json"), meta); err != nil {
			fmt.Fprintln(os.Stderr, "写入移除清单失败:", err)
			return 1
		}
		manifestPacks = append(manifestPacks, p)
	}
	m := buildManifest(manifestPacks, nowUTC(), "", *baseURL, *version)
	manifestPath := filepath.Join(*outDir, "patch-manifest.json")
	if err := writeManifest(manifestPath, m); err != nil {
		fmt.Fprintln(os.Stderr, "写入差量清单失败:", err)
		return 1
	}
	fmt.Printf("生成差量包：%d 个 -> %s\n", len(manifestPacks), manifestPath)
	return 0
}

func runDiff(args []string) int {
	fs := flag.NewFlagSet("diff", flag.ContinueOnError)
	prevPath := fs.String("prev", "", "旧清单文件")
	nextPath := fs.String("next", "", "新清单文件")
	prevCatalog := fs.String("prev-catalog", "", "旧内容源目录（用于条目级差异）")
	nextCatalog := fs.String("next-catalog", "", "新内容源目录（用于条目级差异）")
	out := fs.String("out", "", "差量报告输出路径（默认 stdout）")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *prevPath == "" || *nextPath == "" {
		fmt.Fprintln(os.Stderr, "diff 需要 --prev 与 --next")
		return 2
	}
	prev, err := readManifest(*prevPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "读取旧清单失败:", err)
		return 1
	}
	next, err := readManifest(*nextPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "读取新清单失败:", err)
		return 1
	}
	report := diffManifests(prev, next)

	if *prevCatalog != "" && *nextCatalog != "" {
		prevCat, _ := LoadCatalog(*prevCatalog)
		nextCat, _ := LoadCatalog(*nextCatalog)
		for i := range report.Packs {
			pd := &report.Packs[i]
			pc, ok1 := prevCat[pd.Name]
			nc, ok2 := nextCat[pd.Name]
			if !ok1 || !ok2 {
				continue
			}
			pe := entriesMap(pc.Entries)
			ne := entriesMap(nc.Entries)
			pd.Added, pd.Changed, pd.Removed = diffEntries(pe, ne)
		}
	}

	data, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		fmt.Fprintln(os.Stderr, "序列化报告失败:", err)
		return 1
	}
	data = append(data, '\n')
	if *out == "" {
		fmt.Print(string(data))
	} else if _, err := writeFile(*out, data); err != nil {
		fmt.Fprintln(os.Stderr, "写入报告失败:", err)
		return 1
	}
	return 0
}

func entriesMap(entries []entry) map[string]map[string]any {
	out := map[string]map[string]any{}
	for _, e := range entries {
		out[e.Key] = e.Fields
	}
	return out
}

func runSample(args []string) int {
	fs := flag.NewFlagSet("sample", flag.ContinueOnError)
	catalogDir := fs.String("catalog", defaultCatalogDir, "内容源目录")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	sample := map[string]any{
		"category": "jobs",
		"entries": []map[string]any{
			{"content_key": "occupation.engineer", "name": "工程师", "industry": "technology", "level": 3, "salary_base": 1500000, "skills": []string{"skill.coding"}},
			{"content_key": "occupation.teacher", "name": "教师", "industry": "education", "level": 2, "salary_base": 900000, "skills": []string{"skill.teaching"}},
		},
	}
	data, _ := json.MarshalIndent(sample, "", "  ")
	data = append(data, '\n')
	path := filepath.Join(*catalogDir, "jobs.json")
	if _, err := writeFile(path, data); err != nil {
		fmt.Fprintln(os.Stderr, "写入示例失败:", err)
		return 1
	}
	fmt.Println("已生成示例:", path)
	return 0
}

func runAssets(args []string) int {
	fs := flag.NewFlagSet("assets", flag.ContinueOnError)
	dir := fs.String("dir", "", "待扫描的资产目录")
	out := fs.String("out", "", "台账输出路径（默认写到 stdout）")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *dir == "" {
		fmt.Fprintln(os.Stderr, "缺少 --dir")
		return 2
	}
	ledger, err := scanAssets(*dir)
	if err != nil {
		fmt.Fprintln(os.Stderr, "扫描失败:", err)
		return 1
	}
	if *out != "" {
		if err := writeLedger(*out, ledger); err != nil {
			fmt.Fprintln(os.Stderr, "写入台账失败:", err)
			return 1
		}
		fmt.Printf("资产台账已写入 %s（%d 项）\n", *out, len(ledger.Assets))
		return 0
	}
	data, _ := json.MarshalIndent(ledger, "", "  ")
	fmt.Println(string(data))
	return 0
}
