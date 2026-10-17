#!/usr/bin/env python3
"""程序化 3D 资产生成器（纯 CPU，产出 glTF `.glb`）。

无 GPU、无外部建模软件环境下，用确定性参数几何把内容键编译为真实网格，
落到客户端资产约定路径 `client/assets/models/`，供 Godot 直接导入使用。

运行（隔离环境）：
    .toolchain/meshgen-venv/bin/python tools/meshgen/meshgen.py --all
    .toolchain/meshgen-venv/bin/python tools/meshgen/meshgen.py --groups residence,nature

设计要点：
- 确定性：形状固定，颜色由分组名稳定哈希决定，重复运行产物字节一致（可入库、可 diff）。
- 零依赖运行时：仅依赖 trimesh / numpy / manifold3d，均为纯 CPU 轮子。
- Godot 约定：1 单位 = 1 米；Y 轴向上；地面瓦片 20x20。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import trimesh

# 仓库根：本文件位于 <root>/tools/meshgen/meshgen.py
ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "client" / "assets" / "models" / "place_groups"

RGBA = tuple[int, int, int, int]


# --------------------------------------------------------------------------
# 颜色与几何工具
# --------------------------------------------------------------------------
def _rgb(r: float, g: float, b: float) -> RGBA:
    """0..1 浮点色 → 0..255 RGBA。"""
    return (int(r * 255), int(g * 255), int(b * 255), 255)


def _stable_color(name: str, lo: float = 0.35, hi: float = 0.85) -> RGBA:
    """由名称稳定哈希得到可复现的暖色系颜色。"""
    h = hashlib.sha256(name.encode("utf-8")).digest()
    r = lo + (hi - lo) * (h[0] / 255.0)
    g = lo + (hi - lo) * (h[1] / 255.0)
    b = lo + (hi - lo) * (h[2] / 255.0)
    return _rgb(r, g, b)


def _paint(mesh: trimesh.Trimesh, color: RGBA) -> trimesh.Trimesh:
    """给网格刷顶点色（导出 GLB 时写成 baseColorFactor）。"""
    colors = np.tile(np.array(color, dtype=np.uint8), (len(mesh.vertices), 1))
    mesh.visual = trimesh.visual.ColorVisuals(mesh=mesh, vertex_colors=colors)
    return mesh


def _box(extents, translate=(0, 0, 0), color: RGBA = (200, 200, 200, 255)):
    m = trimesh.creation.box(extents=list(extents))
    m.apply_translation(list(translate))
    return _paint(m, color)


def _cyl(radius, height, translate=(0, 0, 0), color: RGBA = (200, 200, 200, 255), sections: int = 24):
    m = trimesh.creation.cylinder(radius=radius, height=height, sections=sections)
    m.apply_translation(list(translate))
    return _paint(m, color)


def _cone(radius, height, translate=(0, 0, 0), color: RGBA = (200, 200, 200, 255), sections: int = 24):
    m = trimesh.creation.cone(radius=radius, height=height, sections=sections)
    m.apply_translation(list(translate))
    return _paint(m, color)


def _sphere(radius, translate=(0, 0, 0), color: RGBA = (200, 200, 200, 255), subdiv: int = 2):
    m = trimesh.creation.icosphere(subdivisions=subdiv, radius=radius)
    m.apply_translation(list(translate))
    return _paint(m, color)


def _prism(extents, translate=(0, 0, 0), color: RGBA = (200, 200, 200, 255)):
    """三角屋顶楔形：先建 box 再把顶面收拢成脊线。"""
    w, d, h = extents
    verts = np.array(
        [
            [-w / 2, 0, -d / 2], [w / 2, 0, -d / 2], [w / 2, 0, d / 2], [-w / 2, 0, d / 2],
            [0, h, -d / 2], [0, h, d / 2],
        ],
        dtype=float,
    )
    faces = np.array(
        [
            [0, 2, 1], [0, 3, 2],   # 底面
            [0, 1, 4],              # 前山墙
            [3, 5, 2],              # 后山墙
            [0, 4, 5], [0, 5, 3],   # 左坡
            [1, 2, 5], [1, 5, 4],   # 右坡
        ],
        dtype=int,
    )
    m = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
    m.apply_translation(list(translate))
    return _paint(m, color)


def _ground(group: str, size: float = 20.0, color: RGBA | None = None):
    c = color or _stable_color(f"ground:{group}", 0.20, 0.45)
    return _box((size, 0.2, size), (0, -0.1, 0), c)


# --------------------------------------------------------------------------
# 13 个场所分组的分组原型
# --------------------------------------------------------------------------
def _scene(*meshes) -> trimesh.Scene:
    scene = trimesh.Scene()
    for i, m in enumerate(meshes):
        scene.add_geometry(m, node_name=f"part_{i}", geom_name=f"part_{i}")
    return scene


def _residence(_seed: str):
    wall = _rgb(0.62, 0.45, 0.32)
    roof = _rgb(0.52, 0.22, 0.20)
    parts = [_ground("residence")]
    for dx, dz in ((-4, -2), (3, 3)):
        parts.append(_box((4, 3, 4), (dx, 1.5, dz), wall))
        parts.append(_prism((4.6, 4.6, 1.8), (dx, 3.0, dz), roof))
        parts.append(_box((0.8, 1.6, 0.2), (dx, 0.8, dz + 2.0), _rgb(0.30, 0.20, 0.14)))
    return _scene(*parts)


def _dining(_seed: str):
    parts = [_ground("dining")]
    parts.append(_box((6, 3, 5), (0, 1.5, 0), _rgb(0.80, 0.62, 0.40)))
    parts.append(_box((6.6, 0.4, 5.6), (0, 3.2, 0), _rgb(0.70, 0.28, 0.24)))
    for i in range(3):
        parts.append(_cyl(0.9, 0.2, (-2 + i * 2, 1.1, 3.2), _rgb(0.86, 0.80, 0.66)))  # 遮阳伞
        parts.append(_cyl(0.06, 1.2, (-2 + i * 2, 0.6, 3.2), _rgb(0.5, 0.5, 0.5), sections=8))
    return _scene(*parts)


def _retail(_seed: str):
    parts = [_ground("retail")]
    parts.append(_box((8, 4, 5), (0, 2.0, -1), _rgb(0.86, 0.78, 0.62)))
    parts.append(_box((8.4, 0.6, 1.4), (0, 3.4, 2.0), _rgb(0.30, 0.42, 0.60)))  # 招牌
    for i in range(4):
        parts.append(_box((1.2, 1.2, 1.0), (-3 + i * 2, 0.6, 3.0), _stable_color(f"stall{i}")))
    return _scene(*parts)


def _medical(_seed: str):
    parts = [_ground("medical")]
    parts.append(_box((7, 5, 6), (0, 2.5, 0), _rgb(0.90, 0.92, 0.94)))
    # 红十字（两块薄板）
    parts.append(_box((0.6, 2.0, 0.2), (0, 3.2, 3.05), _rgb(0.82, 0.16, 0.16)))
    parts.append(_box((2.0, 0.6, 0.2), (0, 3.2, 3.05), _rgb(0.82, 0.16, 0.16)))
    return _scene(*parts)


def _education(_seed: str):
    parts = [_ground("education")]
    parts.append(_box((9, 4, 5), (0, 2.0, 0), _rgb(0.74, 0.72, 0.62)))
    parts.append(_prism((9.4, 5.4, 1.2), (0, 4.0, 0), _rgb(0.46, 0.32, 0.26)))
    parts.append(_sphere(0.6, (0, 4.6, 2.6), _rgb(0.95, 0.95, 0.90), subdiv=2))  # 钟面
    for i in range(4):  # 门前立柱
        parts.append(_cyl(0.25, 3.4, (-3 + i * 2, 1.7, 2.6), _rgb(0.88, 0.86, 0.78), sections=12))
    return _scene(*parts)


def _government(_seed: str):
    parts = [_ground("government")]
    parts.append(_box((10, 0.4, 7), (0, 0.2, 0), _rgb(0.80, 0.80, 0.84)))  # 台基
    parts.append(_box((8, 4, 5), (0, 2.4, 0), _rgb(0.70, 0.70, 0.74)))
    for i in range(6):
        parts.append(_cyl(0.35, 4, (-3.5 + i * 1.4, 4.4, 3.0), _rgb(0.92, 0.92, 0.90), sections=12))
    parts.append(_box((9, 0.6, 6.4), (0, 6.7, 0), _rgb(0.62, 0.22, 0.26)))  # 檐口
    parts.append(_prism((9, 6.4, 2.0), (0, 7.0, 0), _rgb(0.58, 0.20, 0.24)))
    return _scene(*parts)


def _transport(_seed: str):
    parts = [_ground("transport")]
    parts.append(_box((14, 0.4, 3), (0, 0.8, 0), _rgb(0.42, 0.42, 0.46)))  # 站台
    for i in range(3):
        parts.append(_cyl(0.2, 4, (-4 + i * 4, 2.6, 0), _rgb(0.60, 0.60, 0.64), sections=12))
    parts.append(_box((14, 0.3, 4), (0, 4.7, 0), _rgb(0.30, 0.55, 0.72)))  # 雨棚
    parts.append(_box((3, 1.4, 7), (-5, 0.9, 0), _rgb(0.90, 0.76, 0.20)))  # 车体
    return _scene(*parts)


def _culture(_seed: str):
    parts = [_ground("culture")]
    parts.append(_cyl(3.5, 3.0, (0, 1.5, 0), _rgb(0.60, 0.54, 0.66), sections=32))
    dome = trimesh.creation.icosphere(subdivisions=3, radius=3.5)
    dome.apply_translation([0, 3.0, 0])
    dome = _paint(dome, _rgb(0.66, 0.58, 0.74))
    parts.append(dome)
    parts.append(_cyl(0.3, 3.0, (0, 6.6, 0), _rgb(0.90, 0.86, 0.55), sections=12))
    return _scene(*parts)


def _religion(_seed: str):
    parts = [_ground("religion")]
    gold = _rgb(0.86, 0.78, 0.50)
    for i, (w, h) in enumerate(((6, 2.0), (5, 1.8), (4, 1.6))):
        parts.append(_box((w, h, w), (0, 1 + i * 2.0, 0), _rgb(0.70, 0.32, 0.28)))
        parts.append(_prism((w + 0.6, w + 0.6, 1.0), (0, 2 + i * 2.0, 0), gold))
    parts.append(_cyl(0.2, 3.0, (0, 8.6, 0), gold, sections=10))  # 塔刹
    return _scene(*parts)


def _industry(_seed: str):
    parts = [_ground("industry")]
    parts.append(_box((10, 4, 6), (0, 2.0, 0), _rgb(0.66, 0.46, 0.28)))
    parts.append(_prism((10.4, 6.4, 1.2), (0, 4.0, 0), _rgb(0.48, 0.34, 0.24)))
    for dx in (-3, 0, 3):  # 烟囱
        parts.append(_cyl(0.7, 7, (dx, 5.5, -2), _rgb(0.72, 0.72, 0.70), sections=16))
    return _scene(*parts)


def _finance(_seed: str):
    parts = [_ground("finance")]
    parts.append(_box((6, 14, 6), (0, 7.0, 0), _rgb(0.62, 0.68, 0.74)))
    parts.append(_box((6.4, 0.6, 6.4), (0, 14.2, 0), _rgb(0.82, 0.68, 0.30)))
    for i in range(3):  # 退台
        s = 4 - i
        parts.append(_box((s, 1.0, s), (0, 14.8 + i * 1.0, 0), _rgb(0.70, 0.76, 0.80)))
    return _scene(*parts)


def _nature(_seed: str):
    parts = [_ground("nature", color=_rgb(0.30, 0.46, 0.28))]
    for i, (dx, dz, s) in enumerate(((-4, 2, 1.0), (3, -3, 1.3), (5, 3, 0.8), (-2, -4, 1.1))):
        parts.append(_cyl(0.4 * s, 2.0 * s, (dx, 1.0 * s, dz), _rgb(0.42, 0.30, 0.20), sections=8))
        parts.append(_sphere(1.6 * s, (dx, 3.0 * s, dz), _rgb(0.26, 0.52, 0.28), subdiv=2))
    parts.append(_sphere(0.8, (0, 0.5, 0), _rgb(0.55, 0.55, 0.52), subdiv=1))  # 石
    return _scene(*parts)


def _special(_seed: str):
    parts = [_ground("special")]
    parts.append(_box((2, 8, 2), (0, 4.0, -2), _rgb(0.42, 0.36, 0.58)))  # 方尖碑
    parts.append(_cone(1.0, 2.0, (0, 9.0, -2), _rgb(0.60, 0.35, 0.82), sections=4))
    parts.append(_cyl(2.5, 0.4, (2, 0.2, 2), _rgb(0.34, 0.30, 0.42), sections=24))  # 圆台
    parts.append(_sphere(1.2, (2, 2.0, 2), _rgb(0.60, 0.35, 0.82), subdiv=3))  # 悬浮球
    return _scene(*parts)


GROUPS = {
    "residence": _residence,
    "dining": _dining,
    "retail": _retail,
    "medical": _medical,
    "education": _education,
    "government": _government,
    "transport": _transport,
    "culture": _culture,
    "religion": _religion,
    "industry": _industry,
    "finance": _finance,
    "nature": _nature,
    "special": _special,
}


# --------------------------------------------------------------------------
# 导出
# --------------------------------------------------------------------------
def build_group(group: str) -> trimesh.Scene:
    if group not in GROUPS:
        raise KeyError(f"未知场所分组：{group}（可选：{', '.join(GROUPS)}）")
    return GROUPS[group](group)


def _display_path(path: Path) -> str:
    """仓库内用相对路径展示，仓库外（如 /tmp 输出）保留绝对路径。"""
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def export_group(group: str, out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    scene = build_group(group)
    path = out_dir / f"{group}.glb"
    data = scene.export(file_type="glb")
    path.write_bytes(data)
    bounds = scene.bounds  # (2,3)
    size = (bounds[1] - bounds[0]).tolist()
    return {
        "group": group,
        "path": _display_path(path),
        "bytes": len(data),
        "parts": len(scene.geometry),
        "size": [round(v, 3) for v in size],
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="程序化 3D 资产生成器（glb）")
    ap.add_argument("--all", action="store_true", help="生成全部 13 个场所分组")
    ap.add_argument("--groups", default="", help="逗号分隔的分组名，如 residence,nature")
    ap.add_argument("--out", default=str(DEFAULT_OUT), help="输出目录")
    ap.add_argument("--manifest", action="store_true", help="同时写出 manifest.json")
    args = ap.parse_args(argv)

    if args.all:
        groups = list(GROUPS)
    elif args.groups:
        groups = [g.strip() for g in args.groups.split(",") if g.strip()]
    else:
        ap.error("需指定 --all 或 --groups")
        return 2

    out_dir = Path(args.out).resolve()
    results = []
    for g in groups:
        info = export_group(g, out_dir)
        results.append(info)
        print(f"[meshgen] {g:10s} {info['bytes']:>7d} B  parts={info['parts']:>2d}  size={info['size']}  -> {info['path']}")

    if args.manifest:
        man = out_dir / "manifest.json"
        man.write_text(json.dumps({"generator": "meshgen", "groups": results}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"[meshgen] manifest -> {_display_path(man)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
