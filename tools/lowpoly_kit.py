#!/usr/bin/env python3
"""低模建模套件：图元 + 变换 + glTF 2.0 写出（纯标准库）。

给 gen_enemy_models.py / gen_tower_models.py 共用。

坐标系约定（和 merge_maze_td 现有管线一致）：
    * 原点在**脚底中心**，+Y 向上，正面朝 +Z
    * 高度约 1.0（真正尺寸由游戏侧按目标身高缩放）
    * 平面着色：每个三角形独立法线
    * 逐三角形纯色 → 按颜色合并成多个 material，不用贴图
"""

from __future__ import annotations

import json
import math
import os
import struct

TAU = math.pi * 2.0

# ---------------------------------------------------------------- 色板
# 参考 KR 素材：土色皮革 + 铁灰 + 骨白 + 单位主色，四层叠加。
LEATHER = (0.30, 0.20, 0.13)
LEATHER_L = (0.44, 0.31, 0.20)
LEATHER_D = (0.18, 0.12, 0.08)
STEEL = (0.60, 0.64, 0.70)
STEEL_D = (0.33, 0.36, 0.41)
BONE = (0.87, 0.83, 0.71)
WOOD = (0.45, 0.31, 0.18)
WOOD_D = (0.30, 0.20, 0.12)
GOLD = (0.92, 0.74, 0.32)
DARK = (0.09, 0.08, 0.10)
GLOW = (1.00, 0.93, 0.62)

# 建筑用
STONE = (0.55, 0.53, 0.49)
STONE_D = (0.36, 0.35, 0.33)
STONE_L = (0.68, 0.66, 0.61)
BRICK = (0.50, 0.42, 0.36)
THATCH = (0.82, 0.68, 0.32)
THATCH_D = (0.62, 0.48, 0.20)
ICE = (0.52, 0.80, 0.95)
ICE_L = (0.86, 0.95, 1.00)
ICE_D = (0.24, 0.52, 0.74)
BANNER = (0.26, 0.45, 0.78)
RED = (0.80, 0.24, 0.20)
WHITE = (0.94, 0.95, 0.96)
EMBER = (0.95, 0.42, 0.10)
FIRE = (1.00, 0.62, 0.16)
FIRE_HOT = (1.00, 0.90, 0.45)
AMETHYST = (0.62, 0.36, 0.85)
IRON = (0.32, 0.33, 0.37)
BRONZE = (0.68, 0.50, 0.24)


def shade(c, f):
    return (min(c[0] * f, 1.0), min(c[1] * f, 1.0), min(c[2] * f, 1.0))


def mix(a, b, t):
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))


# ---------------------------------------------------------------- 图元
def _out(tris, center):
    """把每片法线翻到朝外（对凸体足够稳），省去手工推导绕序。"""
    cx, cy, cz = center
    out = []
    for a, b, c, col in tris:
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        nx = uy * vz - uz * vy
        ny = uz * vx - ux * vz
        nz = ux * vy - uy * vx
        gx = (a[0] + b[0] + c[0]) / 3.0 - cx
        gy = (a[1] + b[1] + c[1]) / 3.0 - cy
        gz = (a[2] + b[2] + c[2]) / 3.0 - cz
        if nx * gx + ny * gy + nz * gz < 0.0:
            out.append((c, b, a, col))
        else:
            out.append((a, b, c, col))
    return out


def box(c, s, col, ry=0.0):
    cx, cy, cz = c
    sx, sy, sz = s
    x0, x1 = cx - sx * 0.5, cx + sx * 0.5
    y0, y1 = cy - sy * 0.5, cy + sy * 0.5
    z0, z1 = cz - sz * 0.5, cz + sz * 0.5
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
         (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    faces = [(0, 1, 2), (0, 2, 3), (5, 4, 7), (5, 7, 6),
             (4, 0, 3), (4, 3, 7), (1, 5, 6), (1, 6, 2),
             (4, 5, 1), (4, 1, 0), (3, 2, 6), (3, 6, 7)]
    tris = _out([(v[a], v[b], v[cc], col) for a, b, cc in faces], c)
    return xf(tris, ry=ry) if ry else tris


def taper(center, s_bot, s_top, h, col, ry=0.0):
    """棱台：上窄下宽（或反过来），比纯 box 更像手绘的体积。"""
    cx, cy, cz = center
    bx, bz = s_bot[0] * 0.5, s_bot[1] * 0.5
    tx, tz = s_top[0] * 0.5, s_top[1] * 0.5
    cy0 = cy - h * 0.5
    cy1 = cy + h * 0.5
    b = [(cx - bx, cy0, cz - bz), (cx + bx, cy0, cz - bz),
         (cx + bx, cy0, cz + bz), (cx - bx, cy0, cz + bz)]
    t = [(cx - tx, cy1, cz - tz), (cx + tx, cy1, cz - tz),
         (cx + tx, cy1, cz + tz), (cx - tx, cy1, cz + tz)]
    tris = []
    for i in range(4):
        j = (i + 1) % 4
        tris += [(b[i], b[j], t[j], col), (b[i], t[j], t[i], col)]
    for i in (1, 2):
        tris += [(b[0], b[i + 1], b[i], col), (t[0], t[i], t[i + 1], col)]
    tris = _out(tris, (cx, cy, cz))
    return xf(tris, ry=ry) if ry else tris


def cyl(base, r0, r1, h, col, seg=8, caps=True):
    bx, by, bz = base
    ring0, ring1 = [], []
    for i in range(seg):
        a = TAU * i / seg
        ca, sa = math.cos(a), math.sin(a)
        ring0.append((bx + ca * r0, by, bz + sa * r0))
        ring1.append((bx + ca * r1, by + h, bz + sa * r1))
    tris = []
    for i in range(seg):
        j = (i + 1) % seg
        tris += [(ring0[i], ring0[j], ring1[j], col),
                 (ring0[i], ring1[j], ring1[i], col)]
    if caps and r0 > 1e-5:
        cb = (bx, by, bz)
        for i in range(seg):
            j = (i + 1) % seg
            tris.append((cb, ring0[j], ring0[i], col))
    if caps and r1 > 1e-5:
        ct = (bx, by + h, bz)
        for i in range(seg):
            j = (i + 1) % seg
            tris.append((ct, ring1[i], ring1[j], col))
    return _out(tris, (bx, by + h * 0.5, bz))


def cone(base, r, h, col, seg=7):
    return cyl(base, r, 0.0, h, col, seg=seg)


def lathe(profile, col, seg=12, center=(0.0, 0.0, 0.0)):
    """旋转成型：profile 是自下而上的 [(半径, 高度), ...]。

    做桶身、火盆、冰座、屋顶这类「一圈一圈收放」的东西比堆圆柱干净得多。
    """
    cx, cy, cz = center
    rings = []
    for r, y in profile:
        rings.append([(cx + math.cos(TAU * i / seg) * r, cy + y,
                       cz + math.sin(TAU * i / seg) * r) for i in range(seg)])
    tris = []
    for k in range(len(rings) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            a, b = rings[k][i], rings[k][j]
            c2, d = rings[k + 1][j], rings[k + 1][i]
            tris += [(a, b, c2, col), (a, c2, d, col)]
    ys = [q[1] for q in profile]
    y_mid = (min(ys) + max(ys)) * 0.5 + cy
    if profile[0][0] > 1e-5:
        cb = (cx, cy + profile[0][1], cz)
        for i in range(seg):
            j = (i + 1) % seg
            tris.append((cb, rings[0][j], rings[0][i], col))
    if profile[-1][0] > 1e-5:
        ct = (cx, cy + profile[-1][1], cz)
        for i in range(seg):
            j = (i + 1) % seg
            tris.append((ct, rings[-1][i], rings[-1][j], col))
    return _out(tris, (cx, y_mid, cz))


def sph(c, r, col, seg=10, rings=6, squash=1.0):
    cx, cy, cz = c
    rows = []
    for j in range(rings + 1):
        phi = math.pi * j / rings
        y = math.cos(phi) * r * squash
        rr = math.sin(phi) * r
        rows.append([(cx + math.cos(TAU * i / seg) * rr, cy + y,
                      cz + math.sin(TAU * i / seg) * rr) for i in range(seg)])
    tris = []
    top = (cx, cy + r * squash, cz)
    bot = (cx, cy - r * squash, cz)
    for i in range(seg):
        i2 = (i + 1) % seg
        tris.append((top, rows[1][i], rows[1][i2], col))
        tris.append((bot, rows[rings - 1][i2], rows[rings - 1][i], col))
    for j in range(1, rings - 1):
        for i in range(seg):
            i2 = (i + 1) % seg
            a, b = rows[j][i], rows[j][i2]
            c2, d = rows[j + 1][i2], rows[j + 1][i]
            tris += [(a, b, c2, col), (a, c2, d, col)]
    return _out(tris, c)


def octa(c, rx, ry, col):
    """上下两个锥拼成的晶体（冰晶 / 宝石 / 水晶）。"""
    cx, cy, cz = c
    t = [(cx, cy + ry, cz)]
    b = [(cx, cy - ry, cz)]
    ring = [(cx + math.cos(TAU * i / 4 + math.pi / 4) * rx, cy,
             cz + math.sin(TAU * i / 4 + math.pi / 4) * rx) for i in range(4)]
    tris = []
    for i in range(4):
        j = (i + 1) % 4
        tris += [(t[0], ring[i], ring[j], col), (b[0], ring[j], ring[i], col)]
    return _out(tris, c)


def xf(tris, t=(0.0, 0.0, 0.0), rx=0.0, ry=0.0, rz=0.0,
       s=(1.0, 1.0, 1.0), pivot=(0.0, 0.0, 0.0)):
    """缩放 → 绕 pivot 旋转（X→Y→Z）→ 平移。不用负缩放，避免法线翻转。"""
    px, py, pz = pivot
    cx_, sx_ = math.cos(rx), math.sin(rx)
    cy_, sy_ = math.cos(ry), math.sin(ry)
    cz_, sz_ = math.cos(rz), math.sin(rz)

    def f(p):
        x = (p[0] - px) * s[0]
        y = (p[1] - py) * s[1]
        z = (p[2] - pz) * s[2]
        if rx:
            y, z = y * cx_ - z * sx_, y * sx_ + z * cx_
        if ry:
            x, z = x * cy_ + z * sy_, -x * sy_ + z * cy_
        if rz:
            x, y = x * cz_ - y * sz_, x * sz_ + y * cz_
        return (x + px + t[0], y + py + t[1], z + pz + t[2])

    return [(f(a), f(b), f(c), col) for a, b, c, col in tris]


def mirror(tris):
    return xf(tris, s=(-1.0, 1.0, 1.0))


# ---------------------------------------------------------------- 组合件
def cyl_x(base, r0, r1, h, col, seg=10):
    """沿 +X 生长的圆柱（车轮、轴、横梁）。"""
    return xf(cyl((0.0, 0.0, 0.0), r0, r1, h, col, seg=seg), t=base, rz=-math.pi * 0.5)


def cyl_z(base, r0, r1, h, col, seg=10):
    """沿 +Z 生长的圆柱（盾牌、炮口、靶面）。"""
    return xf(cyl((0.0, 0.0, 0.0), r0, r1, h, col, seg=seg), t=base, rx=math.pi * 0.5)


def wheel(center, r, thick, col, seg=10):
    """带轴心的木轮：轮盘 + 外箍 + 轮辐。"""
    cx, cy, cz = center
    t = cyl_x((cx - thick * 0.5, cy, cz), r, r, thick, col, seg=seg)
    t += cyl_x((cx - thick * 0.7, cy, cz), r * 1.06, r * 1.06, thick * 1.4,
               shade(col, 0.55), seg=seg)
    for i in range(4):
        a = TAU * i / 4.0
        t += xf(box((0.0, 0.0, 0.0), (thick * 0.6, r * 1.7, 0.016), shade(col, 0.8)),
                t=(cx, cy, cz), rx=a)
    return t


def crenels(center, r, count, size, h, col, phase=0.0):
    """一圈城垛（箭塔/狙击塔的顶部特征）。"""
    cx, cy, cz = center
    t = []
    for i in range(count):
        a = TAU * i / count + phase
        t += box((cx + math.cos(a) * r, cy + h * 0.5, cz + math.sin(a) * r),
                 (size, h, size), col, ry=-a)
    return t


def spikes(count, center, r, h, rad, col, tilt=0.0, phase=0.0):
    """一圈向外倾斜的尖刺（冰刺 / 铁刺 / 骨刺通用）。"""
    cx, cy, cz = center
    t = []
    for i in range(count):
        a = TAU * i / count + phase
        px = cx + math.cos(a) * r
        pz = cz + math.sin(a) * r
        t += xf(cone((0.0, 0.0, 0.0), rad, h, col, seg=5),
                t=(px, cy, pz), rz=math.cos(a) * tilt, rx=-math.sin(a) * tilt)
    return t


def banner(center, w, h, drop, col, trim=GOLD):
    """竖直挂在塔侧的旗（带横杆和旗尾）。"""
    cx, cy, cz = center
    t = box((cx, cy + drop * 0.5, cz), (w, 0.018, 0.018), trim)
    t += box((cx, cy + drop * 0.5, cz), (0.016, drop, 0.016), WOOD_D)
    t += taper((cx, cy + drop * 0.5 - h * 0.5 - 0.02, cz),
               (w, 0.02), (w * 0.8, 0.02), h, col)
    return t


# ---------------------------------------------------------------- GLB 写出
def _lin(c):
    """sRGB → 线性。glTF 的 baseColorFactor 是线性空间的，
    直接把 Godot 里那套 sRGB 数值写进去，渲染出来会整体发白。"""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _basecolor(c):
    """glTF 的 baseColorFactor 是线性空间，而素材/数据表里那套颜色是按 sRGB 挑的，
    所以写文件前先做一次 sRGB → 线性，渲染结果才和程序化几何一致。"""
    return _lin(c)


def _add_view(buf, data, target):
    while len(buf) % 4:
        buf.append(0)
    off = len(buf)
    buf.extend(data)
    return {"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target}


def save_glb(path, tris, name, turret=None, turret_pivot=(0.0, 0.0, 0.0)):
    """写出 GLB。

    turret 不为空时，把「会转动的顶部」拆成独立节点 `Turret`：
        node[0] 根节点（名字 = name）
          ├─ node[1] Body   （静态塔身，mesh 0）
          └─ node[2] Turret （mesh 1，translation = turret_pivot）
    Turret 的几何已经按 -pivot 平移过，所以游戏里只要转它的 rotation.y，
    就是绕炮座中心原地转向，而不是绕模型脚底甩出去。
    """
    buf = bytearray()
    views, accessors, mats = [], [], []

    body_prims = _add_prims(tris, buf, views, accessors, mats)
    meshes = [{"name": name, "primitives": body_prims}]
    nodes = [{"name": name, "mesh": 0}]

    if turret:
        px, py, pz = turret_pivot
        meshes.append({"name": name + "_turret",
                       "primitives": _add_prims(xf(turret, t=(-px, -py, -pz)),
                                                buf, views, accessors, mats)})
        nodes[0]["children"] = [1, 2]
        del nodes[0]["mesh"]
        nodes.append({"name": "Body", "mesh": 0})
        nodes.append({"name": "Turret", "mesh": 1, "translation": [px, py, pz]})

    gltf = {
        "asset": {"version": "2.0", "generator": "merge_maze_td lowpoly kit"},
        "scene": 0,
        "scenes": [{"name": name, "nodes": [0]}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": mats,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(buf)}],
    }

    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    while len(buf) % 4:
        buf.append(0)

    out = bytearray()
    out += struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(buf))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js
    out += struct.pack("<II", len(buf), 0x004E4942) + bytes(buf)

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(out)
    return len(tris), len(mats)


def _add_prims(tris, buf, views, accessors, mats):
    """按颜色分组成若干个 primitive（共享同一套 buffer / 材质表）。"""
    groups = {}
    order = []
    for a, b, c, col in tris:
        key = (round(col[0], 4), round(col[1], 4), round(col[2], 4))
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append((a, b, c))

    prims = []

    for key in order:
        pos, nor = [], []
        for a, b, c in groups[key]:
            ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
            vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
            nx = uy * vz - uz * vy
            ny = uz * vx - ux * vz
            nz = ux * vy - uy * vx
            ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            nx, ny, nz = nx / ln, ny / ln, nz / ln
            for p in (a, b, c):
                pos.extend(p)
                nor.extend((nx, ny, nz))

        n_vert = len(pos) // 3
        pmin = [min(pos[i::3]) for i in range(3)]
        pmax = [max(pos[i::3]) for i in range(3)]

        views.append(_add_view(buf, struct.pack("<%df" % len(pos), *pos), 34962))
        accessors.append({"bufferView": len(views) - 1, "componentType": 5126,
                          "count": n_vert, "type": "VEC3", "min": pmin, "max": pmax})
        pos_acc = len(accessors) - 1

        views.append(_add_view(buf, struct.pack("<%df" % len(nor), *nor), 34962))
        accessors.append({"bufferView": len(views) - 1, "componentType": 5126,
                          "count": n_vert, "type": "VEC3"})
        nor_acc = len(accessors) - 1

        mats.append({"name": "m%d" % len(mats), "doubleSided": False,
                     "pbrMetallicRoughness": {
                         "baseColorFactor": [_basecolor(key[0]), _basecolor(key[1]),
                                             _basecolor(key[2]), 1.0],
                         "metallicFactor": 0.0, "roughnessFactor": 0.78}})
        prims.append({"attributes": {"POSITION": pos_acc, "NORMAL": nor_acc},
                      "material": len(mats) - 1, "mode": 4})

    return prims

