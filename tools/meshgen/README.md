# meshgen/ — 程序化 3D 资产生成器

在无 GPU、无外部建模软件的开发环境里，用**确定性参数几何**把内容键编译为真实网格，
输出 glTF `.glb` 到客户端资产约定路径 `client/assets/models/`，Godot 直接导入使用。

## 依赖与隔离

纯 CPU，仅需 Python 轮子 `trimesh` / `numpy` / `manifold3d`。已装在隔离环境
`.toolchain/meshgen-venv`（`.toolchain/` 已在 `.gitignore` 中，不入库）。

重建环境：

```bash
# 前置：apt-get install -y python3.11-venv
python3 -m venv .toolchain/meshgen-venv
.toolchain/meshgen-venv/bin/pip install trimesh numpy manifold3d pillow
```

## 用法

```bash
# 生成全部 13 个场所分组（含 manifest）
.toolchain/meshgen-venv/bin/python tools/meshgen/meshgen.py --all --manifest

# 只生成指定分组
.toolchain/meshgen-venv/bin/python tools/meshgen/meshgen.py --groups residence,nature

# 自定义输出目录
.toolchain/meshgen-venv/bin/python tools/meshgen/meshgen.py --all --out /tmp/opencode/models
```

## 产物与约定

- 输出：`client/assets/models/place_groups/<group>.glb`（13 个 `residence`…`special`）与 `manifest.json`。
  13 个模型已入库，`placeholder_place.tscn` 优先加载，缺失时回退程序化灰盒。
- 该路径是**约定槽位**，留给真实/自建模型；生成器默认写入此处，真实模型按同名覆盖即替换。
- `--out` 支持相对仓库根的路径（内部会解析为绝对路径再写清单）。
- 参考样例另存 `tools/meshgen/samples/place_groups/`（供查看，不被 Godot 扫描，不参与运行时）。
- 单位：1 单位 = 1 米，Y 轴向上，地面瓦片 20×20，低面数（约 48–1500 三角面），实时友好。
- 确定性：形状固定、颜色由分组名稳定哈希决定，**重复运行产物字节一致**，可入库、可 diff。

## 形状目录

`GROUPS` 中每组一个原型函数（住宅/餐饮/零售/医疗/教育/政务/交通/文化/宗教/工业/金融/自然/特殊），
各自独立几何，肉眼可分。新增分组只需加一个构造函数并登记进 `GROUPS`。

## 硬约束

- 环境无 GPU（无 `/dev/nvidia*`）、2 核、约 750MB 可用内存、无 swap：
  扩散式文生 3D（TripoSR / Shap-E / SF3D / Hunyuan3D 等）**无法在此运行**。
  如需 AI 生成的真实模型，走云端 3D API（需自备密钥）或 GPU 机器，产物放入同目录约定路径即可。
- 不在 CI 中运行；属本地/离线资产生成。
