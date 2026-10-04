# 引擎核心补丁

只有模块层无法实现时才在此放置核心 patch（对应 design「引擎定制」的 C 层）：ResourceLoader 缓存与按需卸载、渲染特性裁剪、headless 优化等。

## 约定

- 每个 patch 独立成文件，文件名带简短用途，例如 `0001-resource-loader-lru.patch`。
- 每个 patch 顶部注释写明：解决什么问题、为什么不放在模块、对应上游 commit（若来自上游）。
- 通过 `git -C engine format-patch` 生成，或直接 `git diff` 导出。
- 应用顺序按文件名排序；`scripts/build-engine.sh` 在构建前用 `git apply --3way` 依次应用。
- `engine/` 源码树保持接近纯净，升级上游时只需处理 patch。
- 新增 patch 必须说明移除条件，便于上游修复后删除。
