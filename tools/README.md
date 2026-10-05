# tools/ — 内容生产工具链

内容的导入、校验、打包，以及 Godot 资源/二进制容器的生成。

- 输入：`content/catalog/` 下的源数据（JSON/CSV）
- 输出：`build/content/` 下的轻量二进制内容包（`.ltpack`）与 `manifest.json` 差量清单
- 语言：Go，保持可 CI 化；纳入 `scripts/test.sh` 与 `.github/workflows/ci.yml`

## genbaseline/

数值基线生成器：由 `shared/consistency/baseline/*.json` 真源生成客户端 `baseline_generated.gd`，`-check` 校验生成物与真源一致（CI 硬阻断）。

## contentbuilder/

内容构建与校验工具，模块 `lifetextsandbox/tools/contentbuilder`。

```bash
cd tools/contentbuilder
go test ./...
go run . validate --catalog ../../content/catalog
go run . build --catalog ../../content/catalog --out ../../build/content
go run . diff --prev old/manifest.json --next new/manifest.json --prev-catalog ... --next-catalog ...
go run . patch --prev-catalog ... --next-catalog ... --out ../../build/patch
go run . sample --catalog ../../content/catalog
go run . assets --dir ../../content/art --out ../../build/asset-ledger.json
```

- 硬阻断式校验器：必填、类型、`content_key` 格式与全局重复、跨类别引用、`name`（i18n 键）非空，问题定位到 `文件#content_key`。
- `.ltpack` 容器格式：`magic "LTPK" | version u16 | kind | category | entryCount | (key, payloadJSON)*`，客户端 `client/sim/content_pack.gd` 解码并校验 sha256。
- `manifest.json` 对齐 `shared/schemas/content-manifest.schema.json`，含每包 `name/kind/version/hash/size/url`。
- `diff` 输出包级（added/changed/removed/unchanged）与条目级差异，供差量发布。
- `patch` 为每个变化类别生成 `<category>.patch-<version>.ltpack`（新增+变更条目）与 `.removals.json`（删除条目），并输出带 `patch_of` 的差量清单；差量应用后与全量发布等价（`applyPackPatch` 有单测）。
- 回滚：包按内容哈希与版本命名并保留 `<name>-<version>` 历史文件与既往 `manifest.json`，回滚即切回旧清单并按旧哈希重新校验挂载。
- `assets` 递归扫描美术/音频目录，生成资产台账（路径/类型/大小/sha256/模型 LOD 分层/许可），许可与来源来自同名 `<file>.license.json` 旁注，用于 `design §597` 素材合规审计。
