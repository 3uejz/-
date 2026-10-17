"""Blender 程序化场所模型生成器（试点：finance / culture / special）。

由 Blender 4.5 LTS 以 headless 方式执行：

    .toolchain/blender-4.5.14-linux-x64/blender \
        --background --python tools/meshgen/blender_gen.py -- \
        build --out tools/meshgen/samples/blender_pilot \
        --render-dir tools/meshgen/samples/blender_pilot/renders

设计约束：
- 纯 CPU、无 GPU；单位 1 = 1 米，Blender Z 轴向上，导出 glTF 时转 Y 轴向上。
- 确定性：不使用随机数；同版本 Blender + 同脚本产出字节一致。
- 产物与 trimesh 版共用同一约定槽位 `<group>.glb`，可同名覆盖、零改代码。

另提供 `render` 模式，把任意 GLB 用固定灯光/自动取景渲染成 PNG，便于肉眼比对。
"""

from __future__ import annotations

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

# ---------------------------------------------------------------------------
# 调色与材质
# ---------------------------------------------------------------------------

PALETTES = {
    "finance": {
        "stone": (0.68, 0.64, 0.58),
        "concrete": (0.52, 0.53, 0.55),
        "glass": (0.28, 0.40, 0.50),
        "gold": (0.78, 0.62, 0.26),
        "dark": (0.16, 0.17, 0.19),
    },
    "culture": {
        "stone": (0.80, 0.72, 0.58),
        "sand": (0.72, 0.62, 0.46),
        "roof": (0.20, 0.34, 0.34),
        "glass": (0.30, 0.42, 0.46),
        "dark": (0.22, 0.20, 0.18),
    },
    "special": {
        "obsidian": (0.10, 0.09, 0.13),
        "violet": (0.42, 0.22, 0.62),
        "glow": (0.62, 0.38, 0.92),
        "metal": (0.42, 0.43, 0.48),
        "ground": (0.16, 0.14, 0.20),
    },
    "residence": {
        "lawn": (0.34, 0.45, 0.30),
        "wall": (0.78, 0.74, 0.66),
        "roof": (0.48, 0.28, 0.22),
        "glass": (0.30, 0.40, 0.48),
        "wood": (0.42, 0.31, 0.22),
    },
    "dining": {
        "paving": (0.55, 0.53, 0.50),
        "wall": (0.82, 0.72, 0.55),
        "awning": (0.68, 0.24, 0.22),
        "glass": (0.30, 0.40, 0.44),
        "wood": (0.40, 0.29, 0.20),
    },
    "retail": {
        "paving": (0.58, 0.57, 0.55),
        "wall": (0.80, 0.78, 0.70),
        "sign": (0.30, 0.42, 0.60),
        "glass": (0.32, 0.44, 0.50),
        "fabric": (0.72, 0.30, 0.26),
    },
    "medical": {
        "paving": (0.62, 0.64, 0.65),
        "wall": (0.88, 0.90, 0.92),
        "red": (0.78, 0.16, 0.16),
        "glass": (0.32, 0.46, 0.54),
        "metal": (0.55, 0.57, 0.60),
    },
    "education": {
        "lawn": (0.38, 0.48, 0.32),
        "wall": (0.82, 0.76, 0.62),
        "roof": (0.34, 0.30, 0.28),
        "glass": (0.32, 0.44, 0.50),
        "metal": (0.60, 0.60, 0.58),
    },
    "government": {
        "stone": (0.72, 0.71, 0.68),
        "wall": (0.84, 0.82, 0.76),
        "roof": (0.30, 0.32, 0.36),
        "red": (0.70, 0.18, 0.18),
        "metal": (0.62, 0.63, 0.66),
    },
    "transport": {
        "asphalt": (0.28, 0.28, 0.30),
        "platform": (0.66, 0.64, 0.60),
        "train": (0.34, 0.40, 0.50),
        "canopy": (0.75, 0.76, 0.78),
        "metal": (0.52, 0.54, 0.57),
    },
    "religion": {
        "stone": (0.80, 0.76, 0.66),
        "wall": (0.86, 0.80, 0.68),
        "roof": (0.34, 0.28, 0.24),
        "gold": (0.78, 0.62, 0.26),
        "green": (0.32, 0.44, 0.30),
    },
    "industry": {
        "concrete": (0.50, 0.50, 0.49),
        "wall": (0.66, 0.66, 0.63),
        "roof": (0.40, 0.42, 0.44),
        "brick": (0.56, 0.32, 0.26),
        "metal": (0.58, 0.60, 0.63),
    },
    "nature": {
        "grass": (0.34, 0.48, 0.30),
        "hill": (0.42, 0.52, 0.34),
        "water": (0.24, 0.42, 0.52),
        "trunk": (0.38, 0.28, 0.20),
        "leaf": (0.28, 0.46, 0.28),
        "rock": (0.48, 0.48, 0.46),
    },
}


def make_material(name, color, roughness=0.55, metallic=0.0, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


# ---------------------------------------------------------------------------
# 基础几何
# ---------------------------------------------------------------------------


def _link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def _activate(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)


def add_box(name, size, loc, mat, bevel=0.0, segments=2, rotation_z=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rotation_z:
        obj.rotation_euler[2] = rotation_z
    obj.data.materials.append(mat)
    if bevel > 0.0:
        _apply_bevel(obj, bevel, segments)
    return obj


def _apply_bevel(obj, width, segments):
    _activate(obj)
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(45.0)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def add_cylinder(name, radius, depth, loc, mat, vertices=24, rotation_z=0.0, rotation_x=0.0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=loc
    )
    obj = bpy.context.object
    obj.name = name
    if rotation_z:
        obj.rotation_euler[2] = rotation_z
    if rotation_x:
        obj.rotation_euler[0] = rotation_x
    obj.data.materials.append(mat)
    return obj


def add_sphere(name, radius, loc, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=24, ring_count=12, radius=radius, location=loc
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def add_torus(name, major, minor, loc, mat, rotation_x=0.0):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major,
        minor_radius=minor,
        major_segments=48,
        minor_segments=8,
        location=loc,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler[0] = rotation_x
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def add_prism(name, half_x, half_y, z0, apex_z, mat, bevel=0.0):
    """沿 Y 轴拉伸的三棱柱（山花/坡屋顶）。"""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    v = [
        bm.verts.new((-half_x, -half_y, z0)),
        bm.verts.new((half_x, -half_y, z0)),
        bm.verts.new((0.0, -half_y, apex_z)),
        bm.verts.new((-half_x, half_y, z0)),
        bm.verts.new((half_x, half_y, z0)),
        bm.verts.new((0.0, half_y, apex_z)),
    ]
    bm.faces.new([v[0], v[1], v[2]])
    bm.faces.new([v[5], v[4], v[3]])
    bm.faces.new([v[0], v[3], v[4], v[1]])
    bm.faces.new([v[1], v[4], v[5], v[2]])
    bm.faces.new([v[2], v[5], v[3], v[0]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    _link(obj)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        _apply_bevel(obj, bevel, 2)
    return obj


def add_cone(name, radius, depth, loc, mat, vertices=4, rotation_z=0.0):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=radius, radius2=0.0, depth=depth, location=loc
    )
    obj = bpy.context.object
    obj.name = name
    if rotation_z:
        obj.rotation_euler[2] = rotation_z
    obj.data.materials.append(mat)
    return obj


def add_rock(name, radius, loc, mat, squash=0.65):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=radius, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (1.0, 0.85, squash)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def add_tree(name, x, y, scale, trunk_mat, leaf_mat, cone=False):
    add_cylinder(f"{name}_trunk", 0.16 * scale, 1.5 * scale, (x, y, 0.75 * scale), trunk_mat, vertices=10)
    if cone:
        add_cone(f"{name}_crown", 1.1 * scale, 2.4 * scale, (x, y, 1.9 * scale), leaf_mat, vertices=8)
    else:
        add_sphere(f"{name}_crown", 1.05 * scale, (x, y, 1.95 * scale), leaf_mat)


def add_ground(mat, name="Ground"):
    return add_box(name, (20.0, 20.0, 0.2), (0.0, 0.0, -0.1), mat)


# ---------------------------------------------------------------------------
# 三个试点分组
# ---------------------------------------------------------------------------


def build_finance():
    p = PALETTES["finance"]
    stone = make_material("stone", p["stone"], roughness=0.7)
    concrete = make_material("concrete", p["concrete"], roughness=0.8)
    glass = make_material("glass", p["glass"], roughness=0.18, metallic=0.5)
    gold = make_material("gold", p["gold"], roughness=0.3, metallic=0.9)
    dark = make_material("dark", p["dark"], roughness=0.5)

    add_ground(concrete)
    add_box("Podium", (13.0, 9.0, 1.2), (0.0, 0.0, 0.6), stone, bevel=0.12, segments=2)

    towers = [
        ("TowerA", (4.2, 4.2, 15.0), (0.0, 0.0, 8.7)),
        ("TowerB", (3.2, 3.2, 10.0), (-4.4, 0.4, 6.2)),
        ("TowerC", (3.0, 3.0, 7.2), (4.2, -0.4, 4.8)),
    ]
    for name, size, loc in towers:
        add_box(name, size, loc, glass, bevel=0.14, segments=2)
        # 水平窗带
        bands = int(size[2] / 2.4)
        for i in range(1, bands):
            z = loc[2] - size[2] / 2.0 + i * 2.4
            add_box(
                f"{name}_band{i}",
                (size[0] + 0.10, size[1] + 0.10, 0.07),
                (loc[0], loc[1], z),
                dark,
            )
    # 中央塔冠与天线
    add_box("Crown", (3.4, 3.4, 1.0), (0.0, 0.0, 16.9), stone, bevel=0.1)
    add_cylinder("Antenna", 0.08, 2.2, (0.0, 0.0, 18.5), gold, vertices=12)

    # 入口雨棚与金色标识
    add_box("Canopy", (6.4, 2.2, 0.24), (0.0, -5.0, 3.2), stone, bevel=0.06)
    add_box("Sign", (2.6, 0.18, 0.6), (0.0, -5.86, 2.6), gold, bevel=0.04)
    for i, x in enumerate((-5.4, 5.4)):
        add_cylinder(f"Column{i}", 0.22, 2.6, (x, -4.6, 1.3), stone, vertices=16)

    # 广场铺装与灯柱
    add_box("Plaza", (8.0, 5.0, 0.08), (0.0, -7.0, 0.04), stone)
    for i, x in enumerate((-3.2, 3.2)):
        add_cylinder(f"LampPost{i}", 0.08, 3.0, (x, -8.4, 1.5), dark, vertices=10)
        add_sphere(f"Lamp{i}", 0.18, (x, -8.4, 3.1), gold)


def build_culture():
    p = PALETTES["culture"]
    stone = make_material("stone", p["stone"], roughness=0.75)
    sand = make_material("sand", p["sand"], roughness=0.8)
    roof = make_material("roof", p["roof"], roughness=0.45, metallic=0.2)
    glass = make_material("glass", p["glass"], roughness=0.2, metallic=0.4)
    dark = make_material("dark", p["dark"], roughness=0.6)

    add_ground(sand)
    # 台基与台阶
    add_box("Base", (13.0, 10.0, 0.6), (0.0, 0.0, 0.3), stone, bevel=0.1)
    for i in range(3):
        add_box(
            f"Step{i}",
            (11.0 - i * 0.6, 1.2, 0.2),
            (0.0, -5.8 - i * 0.55, 0.1 + i * 0.2),
            stone,
        )
    # 主殿
    add_box("Hall", (10.0, 7.0, 4.2), (0.0, 0.0, 2.7), stone, bevel=0.1)
    # 山花（正立面三角）
    add_prism("Pediment", 5.2, 3.6, 4.8, 6.6, roof, bevel=0.06)
    # 前廊立柱
    for i in range(6):
        x = -4.0 + i * 1.6
        add_cylinder(f"Column{i}", 0.34, 4.0, (x, -3.9, 2.6), stone, vertices=20)
        add_box(f"Capital{i}", (0.9, 0.9, 0.22), (x, -3.9, 4.7), stone, bevel=0.04)
    # 山墙浮雕
    add_box("Relief", (3.0, 0.16, 0.9), (0.0, -3.66, 5.5), dark, bevel=0.03)
    # 侧翼
    add_box("WingL", (2.6, 6.0, 3.0), (-6.9, 0.0, 2.1), stone, bevel=0.08)
    add_box("WingR", (2.6, 6.0, 3.0), (6.9, 0.0, 2.1), stone, bevel=0.08)
    add_box("WingRoofL", (2.9, 6.3, 0.3), (-6.9, 0.0, 3.75), roof, bevel=0.05)
    add_box("WingRoofR", (2.9, 6.3, 0.3), (6.9, 0.0, 3.75), roof, bevel=0.05)
    # 后部穹顶基座
    add_cylinder("Drum", 2.6, 2.0, (0.0, 1.6, 6.2), stone, vertices=24)
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=24, ring_count=12, radius=2.6, location=(0.0, 1.6, 7.2)
    )
    dome = bpy.context.object
    dome.name = "Dome"
    dome.scale = (1.0, 1.0, 0.62)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    dome.data.materials.append(roof)
    bpy.ops.object.shade_smooth()
    # 玻璃门与侧窗
    add_box("Door", (2.4, 0.2, 2.6), (0.0, -3.58, 2.1), glass, bevel=0.03)
    for i, x in enumerate((-6.9, 6.9)):
        add_box(f"Window{i}", (1.4, 0.18, 1.6), (x, -3.06, 2.2), glass, bevel=0.02)
    # 广场树池
    add_box("Plaza", (9.0, 3.4, 0.08), (0.0, -8.2, 0.04), stone)
    for i, x in enumerate((-3.4, 3.4)):
        add_cylinder(f"Planter{i}", 0.6, 0.5, (x, -8.2, 0.25), dark, vertices=16)
        add_sphere(f"Bush{i}", 0.8, (x, -8.2, 1.2), roof)


def build_special():
    p = PALETTES["special"]
    obsidian = make_material("obsidian", p["obsidian"], roughness=0.35, metallic=0.3)
    violet = make_material("violet", p["violet"], roughness=0.3, metallic=0.4)
    glow = make_material("glow", p["glow"], roughness=0.2, emission=1.6)
    metal = make_material("metal", p["metal"], roughness=0.25, metallic=0.9)
    ground = make_material("ground", p["ground"], roughness=0.85)

    add_ground(ground)
    # 基座圆台
    add_cylinder("Dais", 5.0, 0.6, (0.0, 0.0, 0.3), obsidian, vertices=32)
    add_cylinder("Dais2", 3.6, 0.5, (0.0, 0.0, 0.85), violet, vertices=32)
    # 扭转塔身：14 层，逐层旋转收缩
    levels = 14
    for i in range(levels):
        t = i / float(levels - 1)
        size = 3.2 - 1.2 * t
        z = 1.2 + 0.42 + i * 0.62
        rot = i * 0.13
        mat = violet if i % 3 == 1 else obsidian
        add_box(
            f"Twist{i}",
            (size, size, 0.58),
            (0.0, 0.0, z),
            mat,
            bevel=0.06,
            rotation_z=rot,
        )
    # 悬浮环与核心球
    add_torus("Ring", 3.0, 0.14, (0.0, 0.0, 11.4), metal, rotation_x=math.radians(18))
    add_sphere("Core", 1.05, (0.0, 0.0, 12.6), glow)
    # 顶端尖锥
    bpy.ops.mesh.primitive_cone_add(
        vertices=6, radius1=0.5, radius2=0.0, depth=2.4, location=(0.0, 0.0, 14.6)
    )
    spike = bpy.context.object
    spike.name = "Spike"
    spike.data.materials.append(glow)
    # 围绕基座的方尖碑
    for i in range(4):
        ang = math.radians(45 + i * 90)
        x = math.cos(ang) * 6.6
        y = math.sin(ang) * 6.6
        add_box(f"Monolith{i}", (0.9, 0.9, 5.2), (x, y, 2.6), obsidian, bevel=0.05)
        add_sphere(f"Beacon{i}", 0.24, (x, y, 5.4), glow)



def build_residence():
    p = PALETTES["residence"]
    lawn = make_material("lawn", p["lawn"], roughness=0.85)
    wall = make_material("wall", p["wall"], roughness=0.75)
    roof = make_material("roof", p["roof"], roughness=0.6)
    glass = make_material("glass", p["glass"], roughness=0.2, metallic=0.35)
    wood = make_material("wood", p["wood"], roughness=0.7)
    leaf = make_material("leaf", p["lawn"], roughness=0.8)

    add_ground(lawn)
    for row, y in enumerate((2.2, -3.4)):
        for i in range(4):
            x = -5.4 + i * 3.6
            h = 2.6 if row == 0 else 3.0
            add_box(f"House{row}{i}", (3.2, 3.0, h), (x, y, h / 2.0), wall, bevel=0.08)
            add_prism(f"Roof{row}{i}", 1.75, 1.55, h, h + 1.15, roof, bevel=0.05)
            add_box(f"Door{row}{i}", (0.8, 0.12, 1.6), (x, y - 1.56, 0.8), wood, bevel=0.03)
            add_box(f"Win{row}{i}", (0.9, 0.12, 0.9), (x + (1.0 if i % 2 == 0 else -1.0), y - 1.56, 1.9), glass)
            add_box(f"Balcony{row}{i}", (2.2, 0.8, 0.12), (x, y - 1.7, 2.2), wood, bevel=0.03)
    for i in range(9):
        add_box(f"Fence{i}", (0.12, 0.12, 1.0), (-8.4 + i * 2.1, -8.2, 0.5), wood)
    add_box("FenceRail", (17.0, 0.1, 0.1), (0.0, -8.2, 0.85), wood)
    add_tree("TreeA", -8.0, 6.8, 1.1, wood, leaf)
    add_tree("TreeB", 8.0, 6.4, 1.3, wood, leaf)
    add_tree("TreeC", 7.6, -6.4, 0.9, wood, leaf)
    add_cylinder("Lamp", 0.09, 3.0, (-7.4, -7.4, 1.5), wood, vertices=10)
    add_sphere("LampGlow", 0.2, (-7.4, -7.4, 3.1), glass)


def build_dining():
    p = PALETTES["dining"]
    paving = make_material("paving", p["paving"], roughness=0.85)
    wall = make_material("wall", p["wall"], roughness=0.75)
    awning = make_material("awning", p["awning"], roughness=0.65)
    glass = make_material("glass", p["glass"], roughness=0.2, metallic=0.3)
    wood = make_material("wood", p["wood"], roughness=0.7)
    leaf = make_material("leaf", (0.32, 0.46, 0.30), roughness=0.8)

    add_ground(paving)
    add_box("Restaurant", (8.0, 6.0, 3.2), (0.0, 1.2, 1.6), wall, bevel=0.1)
    add_box("Storefront", (7.2, 0.16, 1.8), (0.0, -1.9, 1.0), glass, bevel=0.03)
    add_box("SignBand", (7.6, 0.22, 0.7), (0.0, -2.0, 3.0), awning, bevel=0.04)
    for i in range(6):
        add_box(f"Awning{i}", (1.3, 2.2, 0.08), (-3.25 + i * 1.3, -3.0, 2.6), awning if i % 2 == 0 else wall)
    for i, x in enumerate((-3.2, 3.2)):
        add_cylinder(f"Post{i}", 0.07, 2.6, (x, -3.9, 1.3), wood, vertices=10)
    for i, (x, y) in enumerate(((-2.6, -5.2), (0.4, -5.8), (2.8, -4.9))):
        add_cylinder(f"Table{i}", 0.7, 0.08, (x, y, 0.75), wood, vertices=20)
        add_cylinder(f"TableLeg{i}", 0.08, 0.75, (x, y, 0.38), wood, vertices=10)
        for j, dx in enumerate((-0.95, 0.95)):
            add_box(f"Chair{i}{j}", (0.45, 0.45, 0.5), (x + dx, y, 0.25), wood, bevel=0.04)
    for i, x in enumerate((-4.2, 4.2)):
        add_box(f"Planter{i}", (1.0, 4.0, 0.5), (x, -2.2, 0.25), wood, bevel=0.03)
        add_sphere(f"Shrub{i}", 0.55, (x, -2.2, 0.8), leaf)


def build_retail():
    p = PALETTES["retail"]
    paving = make_material("paving", p["paving"], roughness=0.85)
    wall = make_material("wall", p["wall"], roughness=0.75)
    sign = make_material("sign", p["sign"], roughness=0.5)
    glass = make_material("glass", p["glass"], roughness=0.18, metallic=0.35)
    fabric = make_material("fabric", p["fabric"], roughness=0.7)
    metal = make_material("metal", (0.55, 0.56, 0.58), roughness=0.4, metallic=0.6)
    wood = make_material("wood", (0.42, 0.31, 0.22), roughness=0.7)

    add_ground(paving)
    add_box("Store", (9.0, 6.0, 3.6), (0.0, 1.5, 1.8), wall, bevel=0.1)
    add_box("Storefront", (8.2, 0.16, 2.2), (0.0, -1.55, 1.2), glass, bevel=0.03)
    add_box("Sign", (6.0, 0.22, 0.8), (0.0, -1.7, 3.5), sign, bevel=0.04)
    add_box("Canopy", (8.6, 1.6, 0.1), (0.0, -2.6, 2.9), fabric, bevel=0.02)
    for i, x in enumerate((-4.0, 4.0)):
        add_cylinder(f"Post{i}", 0.06, 2.9, (x, -3.3, 1.45), metal, vertices=10)
    for i, x in enumerate((-5.2, 0.0, 5.2)):
        add_box(f"StallTable{i}", (2.4, 1.6, 0.8), (x, -5.2, 0.4), wood, bevel=0.04)
        for j, dx in enumerate((-0.9, 0.9)):
            add_cylinder(f"StallPost{i}{j}", 0.05, 2.2, (x + dx, -5.2, 1.1), metal, vertices=8)
        add_box(f"StallRoof{i}", (2.8, 2.0, 0.08), (x, -5.2, 2.2), fabric if i % 2 == 0 else wall)
        add_box(f"Crate{i}", (0.7, 0.7, 0.7), (x - 0.7, -4.8, 1.15), wood, bevel=0.03)


def build_medical():
    p = PALETTES["medical"]
    paving = make_material("paving", p["paving"], roughness=0.85)
    wall = make_material("wall", p["wall"], roughness=0.6)
    red = make_material("red", p["red"], roughness=0.5)
    glass = make_material("glass", p["glass"], roughness=0.18, metallic=0.35)
    metal = make_material("metal", p["metal"], roughness=0.35, metallic=0.7)

    add_ground(paving)
    add_box("Hospital", (10.0, 7.0, 5.0), (0.0, 1.0, 2.5), wall, bevel=0.1)
    for i in range(3):
        add_box(f"Band{i}", (10.1, 7.1, 0.18), (0.0, 1.0, 1.2 + i * 1.5), glass)
    add_box("CrossV", (0.55, 0.2, 2.2), (0.0, -2.55, 3.6), red)
    add_box("CrossH", (1.8, 0.2, 0.55), (0.0, -2.55, 3.6), red)
    add_box("Entrance", (5.0, 2.4, 0.18), (0.0, -4.2, 2.9), metal)
    add_box("Door", (2.6, 0.16, 2.2), (0.0, -2.52, 1.1), glass)
    add_box("Ramp", (3.2, 3.0, 0.3), (0.0, -5.0, 0.15), metal)
    add_cylinder("Helipad", 2.3, 0.08, (0.0, 2.6, 5.06), metal, vertices=32)
    add_box("HelipadMarkV", (0.3, 1.4, 0.04), (0.0, 2.6, 5.1), red)
    add_box("HelipadMarkH1", (1.4, 0.3, 0.04), (0.0, 2.6, 5.1), red)
    for i, x in enumerate((-4.2, 4.2)):
        add_cylinder(f"Tree{i}", 0.16, 1.4, (x, -6.4, 0.7), metal, vertices=10)
        add_sphere(f"TreeCrown{i}", 0.9, (x, -6.4, 1.9), glass)


def build_education():
    p = PALETTES["education"]
    lawn = make_material("lawn", p["lawn"], roughness=0.85)
    wall = make_material("wall", p["wall"], roughness=0.75)
    roof = make_material("roof", p["roof"], roughness=0.6)
    glass = make_material("glass", p["glass"], roughness=0.18, metallic=0.35)
    metal = make_material("metal", p["metal"], roughness=0.4, metallic=0.6)
    leaf = make_material("leaf", (0.30, 0.46, 0.30), roughness=0.8)

    add_ground(lawn)
    add_box("School", (9.0, 6.0, 4.0), (0.0, 1.0, 2.0), wall, bevel=0.1)
    for i in range(2):
        add_box(f"Band{i}", (9.1, 6.1, 0.22), (0.0, 1.0, 1.6 + i * 1.6), glass)
    add_box("Tower", (2.2, 2.2, 7.5), (0.0, 1.0, 3.75), wall, bevel=0.08)
    add_box("Clock", (1.1, 0.14, 1.1), (0.0, -0.16, 7.0), glass, bevel=0.03)
    add_cone("TowerRoof", 1.7, 2.2, (0.0, 1.0, 8.6), roof, vertices=4, rotation_z=math.radians(45))
    add_box("Entrance", (3.2, 0.16, 2.0), (0.0, -2.02, 1.0), glass, bevel=0.03)
    add_cylinder("Flagpole", 0.08, 8.0, (-6.6, -6.4, 4.0), metal, vertices=10)
    add_box("Flag", (1.6, 0.06, 1.0), (-5.8, -6.4, 7.4), roof)
    for i in range(6):
        add_box(f"Fence{i}", (0.1, 0.1, 0.9), (-7.5 + i * 3.0, -8.6, 0.45), metal)
    add_tree("TreeA", 7.4, 6.6, 1.1, roof, leaf)
    add_tree("TreeB", 7.0, -6.0, 0.9, roof, leaf)
    add_tree("TreeC", -7.6, 6.2, 1.0, roof, leaf)


def build_government():
    p = PALETTES["government"]
    stone = make_material("stone", p["stone"], roughness=0.8)
    wall = make_material("wall", p["wall"], roughness=0.7)
    roof = make_material("roof", p["roof"], roughness=0.5, metallic=0.2)
    red = make_material("red", p["red"], roughness=0.6)
    metal = make_material("metal", p["metal"], roughness=0.35, metallic=0.7)

    add_ground(stone)
    add_box("Base", (14.0, 10.0, 0.7), (0.0, 0.0, 0.35), wall, bevel=0.08)
    for i in range(3):
        add_box(f"Step{i}", (12.0 - i * 0.6, 1.2, 0.2), (0.0, -5.9 - i * 0.55, 0.1 + i * 0.2), stone)
    add_box("Hall", (11.0, 7.0, 5.0), (0.0, 0.0, 3.2), wall, bevel=0.1)
    add_prism("Pediment", 5.6, 3.6, 5.7, 7.4, roof, bevel=0.05)
    for i in range(6):
        x = -4.0 + i * 1.6
        add_box(f"Col{i}", (0.55, 0.55, 4.4), (x, -3.7, 2.9), stone, bevel=0.04)
    add_box("Door", (2.6, 0.2, 3.0), (0.0, -3.44, 2.2), roof, bevel=0.03)
    add_cylinder("Flagpole", 0.09, 8.0, (0.0, -6.6, 4.0), metal, vertices=12)
    add_box("Flag", (1.8, 0.06, 1.1), (0.9, -6.6, 7.4), red)
    for i, x in enumerate((-5.6, 5.6)):
        add_cylinder(f"LampPost{i}", 0.09, 3.0, (x, -7.4, 1.5), metal, vertices=10)
        add_sphere(f"Lamp{i}", 0.22, (x, -7.4, 3.2), metal)


def build_transport():
    p = PALETTES["transport"]
    asphalt = make_material("asphalt", p["asphalt"], roughness=0.9)
    platform = make_material("platform", p["platform"], roughness=0.8)
    train = make_material("train", p["train"], roughness=0.35, metallic=0.5)
    canopy = make_material("canopy", p["canopy"], roughness=0.55)
    metal = make_material("metal", p["metal"], roughness=0.35, metallic=0.7)

    add_ground(asphalt)
    add_box("Station", (9.0, 4.5, 3.2), (0.0, -3.0, 1.6), platform, bevel=0.08)
    add_box("StationGlass", (8.2, 0.16, 1.8), (0.0, -5.2, 1.3), train)
    add_box("StationSign", (4.0, 0.2, 0.9), (0.0, -5.32, 3.6), train, bevel=0.03)
    add_box("Platform", (14.0, 3.0, 0.35), (0.0, 2.5, 0.175), platform, bevel=0.03)
    add_box("Canopy", (13.0, 4.0, 0.12), (0.0, 2.5, 3.4), canopy, bevel=0.03)
    for i, x in enumerate((-5.5, -1.8, 1.8, 5.5)):
        add_cylinder(f"CanopyPost{i}", 0.09, 3.2, (x, 2.5, 1.7), metal, vertices=10)
    add_box("Ballast", (18.0, 2.4, 0.12), (0.0, 5.2, 0.0), asphalt)
    for i, y in enumerate((4.6, 5.8)):
        add_box(f"Rail{i}", (18.0, 0.12, 0.12), (0.0, y, 0.12), metal)
    for i, x in enumerate((-3.4, 3.4)):
        add_box(f"Train{i}", (6.0, 2.0, 2.2), (x, 5.2, 1.3), train, bevel=0.1)
        add_box(f"TrainWin{i}", (5.2, 2.05, 0.6), (x, 5.2, 1.9), canopy)
    for i, x in enumerate((-8.6, 8.6)):
        add_cylinder(f"LampPost{i}", 0.08, 4.0, (x, -1.0, 2.0), metal, vertices=10)
        add_sphere(f"Lamp{i}", 0.2, (x, -1.0, 4.1), canopy)


def build_religion():
    p = PALETTES["religion"]
    stone = make_material("stone", p["stone"], roughness=0.8)
    wall = make_material("wall", p["wall"], roughness=0.75)
    roof = make_material("roof", p["roof"], roughness=0.55)
    gold = make_material("gold", p["gold"], roughness=0.3, metallic=0.85)
    green = make_material("green", p["green"], roughness=0.8)
    wood = make_material("wood", (0.40, 0.29, 0.20), roughness=0.7)

    add_ground(stone)
    add_box("Hall", (7.0, 6.0, 3.6), (0.0, 0.5, 1.8), wall, bevel=0.08)
    add_prism("Roof", 3.8, 3.2, 3.6, 4.8, roof, bevel=0.04)
    add_box("Tower", (2.4, 2.4, 5.0), (0.0, 1.2, 5.5), wall, bevel=0.06)
    add_cone("Spire", 1.8, 3.0, (0.0, 1.2, 9.5), roof, vertices=4, rotation_z=math.radians(45))
    add_sphere("Bell", 0.5, (0.0, 1.2, 8.1), gold)
    for i, x in enumerate((-2.4, -0.8, 0.8, 2.4)):
        add_cylinder(f"Col{i}", 0.28, 3.0, (x, -2.9, 1.5), stone, vertices=16)
    add_box("Door", (1.6, 0.16, 2.4), (0.0, -2.46, 1.2), wood, bevel=0.03)
    for i, x in enumerate((-3.6, 3.6)):
        add_cylinder(f"LampPost{i}", 0.07, 2.4, (x, -4.4, 1.2), wood, vertices=10)
        add_sphere(f"Lantern{i}", 0.26, (x, -4.4, 2.6), gold)
    add_tree("TreeA", -7.2, 6.6, 1.2, wood, green)
    add_tree("TreeB", 7.2, 6.2, 1.0, wood, green)
    add_tree("TreeC", 7.0, -6.6, 0.9, wood, green)


def build_industry():
    p = PALETTES["industry"]
    concrete = make_material("concrete", p["concrete"], roughness=0.9)
    wall = make_material("wall", p["wall"], roughness=0.8)
    roof = make_material("roof", p["roof"], roughness=0.5, metallic=0.3)
    brick = make_material("brick", p["brick"], roughness=0.75)
    metal = make_material("metal", p["metal"], roughness=0.3, metallic=0.8)

    add_ground(concrete)
    add_box("Factory", (10.0, 7.0, 4.0), (0.0, -0.5, 2.0), wall, bevel=0.08)
    for i in range(4):
        add_prism(f"Tooth{i}", 1.25, 3.4, 4.0, 5.3, roof, bevel=0.03)
        add_box(f"ToothGlass{i}", (0.12, 3.2, 0.7), (-3.75 + i * 2.5 + 1.25, -0.5, 4.5), metal)
    for i, (x, y) in enumerate(((-4.4, 2.8), (4.4, 2.8))):
        add_cylinder(f"Chimney{i}", 0.75, 9.0, (x, y, 4.5), brick, vertices=20)
        for j in range(3):
            add_cylinder(f"ChimneyRing{i}{j}", 0.82, 0.18, (x, y, 3.2 + j * 2.2), metal, vertices=20)
    for i, x in enumerate((-6.8, -4.6)):
        add_cylinder(f"Silo{i}", 1.2, 6.0, (x, -4.6, 3.0), metal, vertices=24)
        add_sphere(f"SiloTop{i}", 1.2, (x, -4.6, 6.0), metal)
    add_cylinder("Pipe", 0.22, 5.0, (-5.7, -2.1, 4.4), metal, vertices=12, rotation_x=math.radians(90))
    add_box("LoadingDock", (4.0, 2.0, 0.6), (3.0, -5.2, 0.3), metal, bevel=0.04)
    add_box("Door", (2.6, 0.16, 2.4), (3.0, -4.04, 1.2), roof, bevel=0.03)


def build_nature():
    p = PALETTES["nature"]
    grass = make_material("grass", p["grass"], roughness=0.9)
    hill = make_material("hill", p["hill"], roughness=0.9)
    water = make_material("water", p["water"], roughness=0.15, metallic=0.2)
    trunk = make_material("trunk", p["trunk"], roughness=0.8)
    leaf = make_material("leaf", p["leaf"], roughness=0.85)
    rock = make_material("rock", p["rock"], roughness=0.85)

    add_ground(grass)
    add_rock("HillA", 6.0, (6.5, 5.5, 1.6), hill, squash=0.45)
    add_rock("HillB", 4.2, (-6.0, 6.0, 1.0), hill, squash=0.42)
    add_cylinder("Pond", 3.8, 0.08, (-3.5, -3.0, 0.06), water, vertices=32)
    add_rock("RockA", 0.9, (2.0, -5.0, 0.45), rock)
    add_rock("RockB", 0.6, (3.2, -4.2, 0.3), rock)
    add_rock("RockC", 0.45, (-7.6, -1.0, 0.24), rock)
    add_tree("TreeA", -7.4, 3.0, 1.3, trunk, leaf, cone=True)
    add_tree("TreeB", 3.6, 3.4, 1.1, trunk, leaf, cone=True)
    add_tree("TreeC", 7.4, -3.6, 1.0, trunk, leaf)
    add_tree("TreeD", -6.8, -6.8, 0.9, trunk, leaf)
    add_tree("TreeE", 1.0, 6.6, 0.8, trunk, leaf, cone=True)
    for i in range(7):
        ang = i / 7.0 * math.tau
        add_cylinder(
            f"Reed{i}", 0.05, 0.8,
            (-3.5 + math.cos(ang) * 4.1, -3.0 + math.sin(ang) * 4.1, 0.4),
            leaf, vertices=6,
        )


# ---------------------------------------------------------------------------
# 场景与导出
# ---------------------------------------------------------------------------

GROUPS = {
    "residence": build_residence,
    "dining": build_dining,
    "retail": build_retail,
    "medical": build_medical,
    "education": build_education,
    "government": build_government,
    "transport": build_transport,
    "culture": build_culture,
    "religion": build_religion,
    "industry": build_industry,
    "finance": build_finance,
    "nature": build_nature,
    "special": build_special,
}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def scene_stats():
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    tris = 0
    for obj in meshes:
        me = obj.data
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    size = hi - lo
    return {
        "parts": len(meshes),
        "tris": tris,
        "size": [round(v, 3) for v in size],
        "center": [round(v, 3) for v in ((lo + hi) * 0.5)],
        "radius": round((hi - lo).length * 0.5, 3),
    }


def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_yup=True,
    )
    return os.path.getsize(path)


# ---------------------------------------------------------------------------
# 渲染（对比用）
# ---------------------------------------------------------------------------


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 640
    scene.render.resolution_y = 480
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.exposure = -0.35
    except Exception:
        pass

    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.10, 0.11, 0.13, 1.0)
    bg.inputs[1].default_value = 1.0

    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.2
    sun_data.angle = math.radians(5.0)
    sun = bpy.data.objects.new("Sun", sun_data)
    _link(sun)
    sun.rotation_euler = (math.radians(52.0), 0.0, math.radians(38.0))

    return scene


def add_camera(center, radius):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50.0
    cam_data.clip_end = 1000.0
    cam = bpy.data.objects.new("Cam", cam_data)
    _link(cam)
    direction = Vector((1.55, -1.55, 1.05)).normalized()
    cam.location = Vector(center) + direction * (radius * 3.05)
    look = Vector(center) - cam.location
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam

    fill_data = bpy.data.lights.new("Fill", "AREA")
    fill_data.energy = 1800.0
    fill_data.size = 18.0
    fill = bpy.data.objects.new("Fill", fill_data)
    _link(fill)
    fill.location = Vector(center) + Vector((-radius * 1.2, -radius * 1.0, radius * 1.4))
    fill.rotation_euler = (Vector(center) - fill.location).to_track_quat("-Z", "Y").to_euler()


def render_current(png_path):
    os.makedirs(os.path.dirname(png_path), exist_ok=True)
    bpy.context.scene.render.filepath = png_path
    bpy.ops.render.render(write_still=True)


def render_glb(glb_path, png_path):
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=glb_path)
    stats = scene_stats()
    setup_render()
    add_camera(stats["center"], stats["radius"])
    render_current(png_path)
    return stats


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------


def parse_args(argv):
    out = {"mode": "build", "groups": "", "out": "", "render_dir": "", "input": "", "png": ""}
    i = 0
    while i < len(argv):
        key = argv[i]
        if key in ("--groups", "--out", "--render-dir", "--input", "--png"):
            i += 1
            val = argv[i] if i < len(argv) else ""
            out[key.lstrip("-").replace("-", "_")] = val
        elif key in ("build", "render"):
            out["mode"] = key
        i += 1
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    args = parse_args(argv)
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    if args["mode"] == "render":
        glb = args["input"]
        png = args["png"] or os.path.splitext(glb)[0] + "_render.png"
        stats = render_glb(glb, png)
        print("[blender_gen] " + json.dumps({"render": png, **stats}, ensure_ascii=False))
        return 0

    names = [g.strip() for g in args["groups"].split(",") if g.strip()] or list(GROUPS)
    out_dir = args["out"]
    render_dir = args["render_dir"]
    results = []
    for name in names:
        if name not in GROUPS:
            raise SystemExit(f"未知分组：{name}（可选：{', '.join(GROUPS)}）")
        reset_scene()
        GROUPS[name]()
        stats = scene_stats()
        glb_path = os.path.join(out_dir, name + ".glb")
        size = export_glb(glb_path)
        item = {
            "group": name,
            "path": os.path.relpath(glb_path, root),
            "bytes": size,
            **stats,
        }
        if render_dir:
            setup_render()
            add_camera(stats["center"], stats["radius"])
            png = os.path.join(render_dir, name + ".png")
            render_current(png)
            item["render"] = os.path.relpath(png, root)
        results.append(item)
        print("[blender_gen] " + json.dumps(item, ensure_ascii=False))

    if args["out"]:
        man = os.path.join(out_dir, "manifest.json")
        with open(man, "w", encoding="utf-8") as fh:
            json.dump(
                {"generator": "blender_gen", "blender": bpy.app.version_string, "groups": results},
                fh,
                ensure_ascii=False,
                indent=2,
            )
            fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
