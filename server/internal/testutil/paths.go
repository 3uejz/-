// Package testutil 提供测试共用的仓库路径解析（仅测试使用）。
package testutil

import (
	"os"
	"path/filepath"
)

// RepoRoot 从当前工作目录向上查找，定位包含 shared/consistency/vectors 的仓库根。
func RepoRoot() (string, bool) {
	dir, err := os.Getwd()
	if err != nil {
		return "", false
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "shared", "consistency", "vectors")); err == nil {
			return dir, true
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", false
		}
		dir = parent
	}
}

// VectorsDir 返回 shared/consistency/vectors 目录，找不到时返回空串。
func VectorsDir() string {
	root, ok := RepoRoot()
	if !ok {
		return ""
	}
	return filepath.Join(root, "shared", "consistency", "vectors")
}
