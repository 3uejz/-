# 引擎定制模块（overlay）

本目录是《浮生录》项目专用的 Godot 引擎模块，采用 **overlay 模式**：不直接改 `engine/` 源码树，而是通过 SCons 的 `custom_modules` 参数在构建时叠加进来。

```bash
scons -C engine platform=linuxbsd target=editor custom_modules=/abs/path/to/engine-modules
```

Windows 导出模板由 CI 构建：

```bash
scons -C engine platform=windows target=template_release custom_modules=%CD%\engine-modules
```

## 模块

| 模块 | 职责 | 状态 |
|------|------|------|
| `lifetext_content` | 列式二进制内容容器 + zstd、`ResourceFormatLoader` 解码 | 骨架 |
| `lifetext_crypto` | 存档 AES-256-GCM + Argon2id、PCK 加密辅助、完整性校验 | 骨架 |
| `lifetext_text` | CJK 排版辅助、IME 文本归一化 | 骨架 |
| `lifetext_sim` | 无状态批量确定性内核（SplitMix64、属性衰减、人口/经济热点） | 骨架 |

## 模块 API 契约

所有模块导出的类遵循统一约定，契约变更必须同步 `client/` 与 `server/` 的调用方，并纳入 `shared/consistency/`：

1. **`LT` 前缀**：导出的类名一律以 `LT` 开头（如 `LTSim`）。
2. **API 版本**：每个类提供 `static int get_api_version()`，返回值与该类的 `API_VERSION` 常量一致。加载时版本不匹配即拒绝。
3. **实例形态**：导出对象为 `RefCounted` 实例，由 GDScript 持有引用，不暴露全局可变状态。
4. **批量进出**：热点路径使用 `Packed*Array` 批量传入与返回，禁止逐实体跨语言调用。
5. **结构化结果**：可能失败的方法统一返回 `Dictionary`：`{ "ok": bool, "code": String, "message": String, "data": Variant }`。
6. **无状态内核**：`lifetext_sim` 的批处理函数不得读写全局状态，全部输入通过参数、输出通过返回值；模拟状态以 GDScript 为源。

## 一致性

`lifetext_sim` 的确定性算法与 `shared/consistency/vectors/`（Go/GDScript 两端）保持一致；新增批量内核时必须先加向量用例，再写实现。

## 相关文档

- `engine-patches/`：少量核心 patch（模块无法实现时才用），每个 patch 独立、可追溯到上游。
- `scripts/setup-engine.sh`：拉取引擎源码（默认官方 Godot 4.7.2；可通过 `GODOT_REPO` 指向自有 fork）。
- `scripts/build-engine.sh`：应用 patch 并调用 SCons 构建。
- `.github/workflows/engine.yml`：CI 构建编辑器、headless 与 Windows 导出模板。
