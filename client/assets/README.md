# 美术资产目录与契约

本目录承载客户端的美术资产。当前所有表现为「程序化占位」，本文件定义**资产契约**：
真实资产按此处约定命名与放置后，**无需修改任何代码**即可替换占位。

## 目录结构

```
assets/
├─ models/      3D 模型（glTF .glb 优先，.gltf 次之）
├─ textures/    贴图（.png / .webp；UI 图标可用 .svg）
├─ materials/   独立材质（.tres）
├─ audio/       音频（.ogg 音乐 / .wav 音效）
└─ placeholder/ 程序化占位（构建期可清理，不入库真实资产）
art/
└─ illustrations/  叙事内联插画（.tres / .png / .svg / .webp）
presentation/
└─ scenes/
   ├─ placeholder_place.tscn   差异化占位场景（默认）
   └─ places/<group>.tscn      场所分组真实场景（放入即替换）
```

## 命名规范

- 全小写，单词以 `_` 分隔；禁止空格与非 ASCII 字符。
- 内容键对应资产：把 `item.apple` 映射到 `models/item/apple.glb`（点号 → 目录/文件名）。
- 场所场景：`presentation/scenes/places/<group>.tscn`，`<group>` 取 13 个场所分组之一：
  `residence` / `dining` / `retail` / `medical` / `education` / `government` /
  `transport` / `culture` / `religion` / `industry` / `finance` / `nature` / `special`。
- 插画键：`illus.<name>` → `art/illustrations/<name>.(tres|png|svg|webp)`。

## LOD 约定

- 场所场景按距离分三级：`near` / `mid` / `far`。
- 三级可用同一场景（占位阶段）；真实资产到位后，在绑定中登记：
  `{ "near": near 路径, "mid": mid 路径, "far": far 路径 }`，
  未配置的层级回退到主路径。缺失层级不报错。
- 命名建议：`<name>_near.glb` / `<name>_mid.glb` / `<name>_far.glb`。

## 替换占位的工作流

1. 场所分组：将 `<group>.tscn` 放入 `presentation/scenes/places/`。
   `place_bindings.scene_for()` 会优先命中该约定路径，自动替换差异化占位场景。
2. 具体模型 / 贴图：按内容键命名放入 `assets/models|textures/`；
   表现层经 `PlaceholderAssets.placeholder_path()` 与内容键解析。
3. 插画：将文件放入 `art/illustrations/`，命名对应插画键即可，缺失时回退水墨留白。

以上流程均不涉及代码改动；`PlaceholderAssets.is_placeholder_path()` 可校验某路径是否仍为占位。
