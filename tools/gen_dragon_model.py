#!/usr/bin/env python3
"""生成三级喷火塔塔顶的「火龙」模型（低模、纯色、平面着色）。

坐标系沿用 lowpoly_kit 的约定：原点在脚底中心，+Y 向上，**正面朝 +Z**（也就是游戏镜头方向）。
游戏侧会按目标身高自动缩放，所以这里把整只龙的高度控制在 1.0 左右。

参考图：橙红色身体 + 亮黄角/背刺 + 橙黄翼膜 + 张开露出白牙的嘴。
翅膀做成「薄片双层」：翼膜左右各一层、绕序相反，避免开启背面剔除后从一边看不见。

用法：python tools/gen_dragon_model.py
产出：models/towers/dragon.glb
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lowpoly_kit import (box, cone, cyl, save_glb, sph, taper, xf)  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "models", "towers", "dragon.glb")

# ---------------------------------------------------------------- 配色
BODY = (0.84, 0.28, 0.14)      # 主体橙红
BODY_D = (0.56, 0.16, 0.09)    # 暗部 / 翼骨
BODY_L = (0.96, 0.44, 0.18)    # 亮部 / 背脊
BELLY = (0.97, 0.63, 0.28)     # 肚皮
WING = (0.96, 0.56, 0.16)      # 翼膜中段
WING_L = (1.00, 0.74, 0.32)    # 翼膜前缘亮色
WING_D = (0.62, 0.19, 0.10)    # 翼膜根部的深色
HORN = (0.96, 0.82, 0.38)      # 角 / 背刺
FANG = (0.96, 0.95, 0.88)      # 牙
EYE = (1.00, 0.92, 0.32)       # 眼
MOUTH = (0.36, 0.08, 0.08)     # 口腔
SCALE = (0.76, 0.235, 0.12)    # 鳞片（比身体略暗，靠平面着色的明暗差读出来）
BELLY_D = (0.88, 0.50, 0.21)   # 腹甲分节


# ---------------------------------------------------------------- 向量小工具
def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def norm(a):
    ln = math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2) or 1.0
    return (a[0] / ln, a[1] / ln, a[2] / ln)


def rot_to_up(d):
    """把 +Y 转到 d 的旋转函数（罗德里格斯公式）。"""
    d = norm(d)
    up = (0.0, 1.0, 0.0)
    ax = cross(up, d)
    s = math.sqrt(ax[0] ** 2 + ax[1] ** 2 + ax[2] ** 2)
    c = up[0] * d[0] + up[1] * d[1] + up[2] * d[2]
    if s < 1e-7:
        return lambda p: p if c > 0 else (-p[0], -p[1], -p[2])
    ax = mul(ax, 1.0 / s)
    ang = math.atan2(s, c)
    ca, sa = math.cos(ang), math.sin(ang)

    def f(p):
        # Rodrigues：p*cos + (axis×p)*sin + axis*(axis·p)*(1-cos)
        cr = cross(ax, p)
        dt = ax[0] * p[0] + ax[1] * p[1] + ax[2] * p[2]
        return (p[0] * ca + cr[0] * sa + ax[0] * dt * (1.0 - ca),
                p[1] * ca + cr[1] * sa + ax[1] * dt * (1.0 - ca),
                p[2] * ca + cr[2] * sa + ax[2] * dt * (1.0 - ca))
    return f


def apply(tris, f, t=(0.0, 0.0, 0.0)):
    out = []
    for a, b, c, col in tris:
        out.append((add(f(a), t), add(f(b), t), add(f(c), t), col))
    return out


def seg(p0, p1, r0, r1, col, pieces=8):
    """从 p0 长到 p1 的锥柱（脖子 / 四肢 / 尾巴 / 角）。"""
    d = sub(p1, p0)
    h = math.sqrt(d[0] ** 2 + d[1] ** 2 + d[2] ** 2) or 1e-4
    return apply(cyl((0.0, 0.0, 0.0), r0, r1, h, col, seg=pieces), rot_to_up(d), p0)


def spike(p0, p1, r, col, pieces=6):
    """从 p0 指向 p1 的尖刺。"""
    d = sub(p1, p0)
    h = math.sqrt(d[0] ** 2 + d[1] ** 2 + d[2] ** 2) or 1e-4
    return apply(cone((0.0, 0.0, 0.0), r, h, col, seg=pieces), rot_to_up(d), p0)


def plate(pts, col, thick=0.012):
    """平面扇形（翼膜）：正反两层、绕序相反，单面剔除也不会缺一半。"""
    n = norm(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])))
    off = mul(n, thick * 0.5)
    out = []
    for i in range(1, len(pts) - 1):
        a, b, c = pts[0], pts[i], pts[i + 1]
        out.append((add(a, off), add(b, off), add(c, off), col))
        out.append((sub(a, off), sub(c, off), sub(b, off), col))
    return out


def tilt_box(c, s, col, rz=0.0):
    """绕自身中心在 XY 面内倾斜的方块（怒眉 / 甲片）。"""
    t = box(c, s, col)
    return xf(t, rz=rz, pivot=c) if rz else t


def ellip_point(center, radii, u, v):
    """椭球表面点：u 是绕 Y 的方位角（0 = +Z 正前，π/2 = +X 右侧），v 是纬度（+ 为上）。"""
    cx, cy, cz = center
    a, b, c = radii
    sv, cv = math.sin(v), math.cos(v)
    return (cx + a * cv * math.sin(u), cy + b * sv, cz + c * cv * math.cos(u))


def ellip_normal(center, radii, p):
    a, b, c = radii
    return norm(((p[0] - center[0]) / (a * a),
                 (p[1] - center[1]) / (b * b),
                 (p[2] - center[2]) / (c * c)))


def scale_at(p, n, w, h, col, rise=0.012, along=(0.0, 1.0, 0.0)):
    """在表面点 p（外法线 n）上贴一枚四棱锥鳞片：底面 w×h，尖高 rise。
    along 是切平面里的参考方向（默认竖直），鳞片的 w 边与它垂直。"""
    n = norm(n)
    t1 = cross(n, along)
    if t1[0] ** 2 + t1[1] ** 2 + t1[2] ** 2 < 1e-8:
        t1 = cross(n, (1.0, 0.0, 0.0))
    t1 = norm(t1)
    t2 = norm(cross(n, t1))
    hw, hh = w * 0.5, h * 0.5
    base = [sub(sub(p, mul(t1, hw)), mul(t2, hh)),
            add(sub(p, mul(t2, hh)), mul(t1, hw)),
            add(add(p, mul(t1, hw)), mul(t2, hh)),
            sub(add(p, mul(t2, hh)), mul(t1, hw))]
    apex = add(p, mul(n, rise))
    return [(apex, base[i], base[(i + 1) % 4], col) for i in range(4)]


def ring_scale(c, axis, r, h, col, seg=8):
    """沿 axis 在 c 处套一圈薄鳞环（四肢 / 尾巴 / 脖子分节）。"""
    d = norm(axis)
    return apply(cyl((0.0, 0.0, 0.0), r, r, h, col, seg=seg, caps=False),
                 rot_to_up(d), sub(c, mul(d, h * 0.5)))


def mirror_x(tris):
    """左右镜像：翻转 x 并反转绕序，法线才不会整体朝里。"""
    out = []
    for a, b, c, col in tris:
        out.append(((-a[0], a[1], a[2]), (-c[0], c[1], c[2]), (-b[0], b[1], b[2]), col))
    return out


# ---------------------------------------------------------------- 各部位
def torso():
    t = []
    # 胸腹主干：前胸略高、后腰略收
    t += xf(sph((0.0, 0.47, -0.01), 0.19, BODY, seg=12, rings=7),
            s=(1.05, 0.95, 1.42), pivot=(0.0, 0.47, -0.01))
    t += xf(sph((0.0, 0.43, 0.08), 0.155, BELLY, seg=12, rings=6),
            s=(0.92, 0.80, 1.15), pivot=(0.0, 0.43, 0.08))
    # 髋部
    t += xf(sph((0.0, 0.42, -0.20), 0.165, BODY, seg=10, rings=6),
            s=(1.0, 0.92, 0.95), pivot=(0.0, 0.42, -0.20))
    # 肩峰（左右各一）
    for sx in (-1, 1):
        t += sph((sx * 0.12, 0.56, 0.02), 0.085, BODY_L, seg=8, rings=5)
    return t


def neck_head():
    t = []
    # 颈部：加粗、抬头挺胸，撑得住更大的头
    t += seg((0.0, 0.540, 0.09), (0.0, 0.695, 0.185), 0.142, 0.118, BODY, pieces=10)
    t += seg((0.0, 0.695, 0.185), (0.0, 0.815, 0.250), 0.118, 0.102, BODY, pieces=10)
    # 喉部亮色
    t += seg((0.0, 0.565, 0.165), (0.0, 0.800, 0.300), 0.060, 0.050, BELLY, pieces=8)

    # 头骨：后脑圆弧 + 方正主块，块面硬朗才有重量感
    t += xf(sph((0.0, 0.878, 0.250), 0.122, BODY, seg=10, rings=6),
            s=(1.0, 0.92, 0.92), pivot=(0.0, 0.878, 0.250))
    t += box((0.0, 0.882, 0.318), (0.214, 0.196, 0.238), BODY)
    # 吻部：头骨 → 吻后段 → 吻前段逐级收窄，正面才有台阶感，而不是一块砖
    t += box((0.0, 0.856, 0.428), (0.150, 0.122, 0.155), BODY)
    t += box((0.0, 0.848, 0.525), (0.120, 0.104, 0.115), BODY)
    t += box((0.0, 0.928, 0.470), (0.040, 0.048, 0.176), BODY_L)   # 鼻梁中脊（正面破开平板的脸）
    t += box((0.0, 0.840, 0.590), (0.090, 0.072, 0.028), BODY_D)   # 鼻端
    # 下颌：以咬合点 (0, 0.798, 0.355) 为轴张开 ~29°，连带下牙一起转
    jaw = box((0.0, -0.022, 0.105), (0.130, 0.055, 0.215), BODY_D)
    jaw += box((0.0, 0.004, 0.160), (0.098, 0.024, 0.070), BELLY)
    for sx in (-1, 1):
        jaw += spike((sx * 0.044, 0.010, 0.150), (sx * 0.044, 0.064, 0.145), 0.014, FANG, pieces=5)
        jaw += spike((sx * 0.044, 0.010, 0.050), (sx * 0.044, 0.056, 0.046), 0.012, FANG, pieces=5)
    jaw = apply(xf(jaw, rx=0.50, pivot=(0.0, 0.0, 0.0)), lambda p: p, (0.0, 0.798, 0.355))
    t += jaw
    # 口腔（上下颌之间的一块暗色）
    t += box((0.0, 0.800, 0.462), (0.072, 0.040, 0.135), MOUTH)
    # 上牙：每侧三颗，獠牙更长
    for sx in (-1, 1):
        t += spike((sx * 0.046, 0.812, 0.560), (sx * 0.046, 0.750, 0.560), 0.014, FANG)
        t += spike((sx * 0.050, 0.814, 0.498), (sx * 0.050, 0.756, 0.498), 0.013, FANG)
        t += spike((sx * 0.060, 0.816, 0.428), (sx * 0.060, 0.762, 0.428), 0.013, FANG)
    # 眼睛：扁长的金色眼球，被眉骨压住上半，像猛兽的细眼而不是圆圆的卡通眼
    for sx in (-1, 1):
        t += box((sx * 0.080, 0.886, 0.422), (0.058, 0.066, 0.086), BODY_D)
        eye = sph((sx * 0.094, 0.892, 0.434), 0.030, EYE, seg=8, rings=5)
        t += xf(eye, s=(1.0, 0.68, 1.0), pivot=(sx * 0.094, 0.892, 0.434))
    # 怒眉：内侧下压、外侧上挑；往下压住眼球上半，眼神才凶
    for sx in (-1, 1):
        c = (sx * 0.072, 0.936, 0.422)
        t += tilt_box(c, (0.114, 0.048, 0.096), BODY_D, rz=sx * 0.34)
    t += box((0.0, 0.954, 0.406), (0.050, 0.048, 0.078), BODY_D)   # 眉间棱
    # 主角：起点抬到头顶、向后上方掠，正面看是尖锐的两撇而不是横着的王冠
    for sx in (-1, 1):
        t += spike((sx * 0.072, 0.958, 0.276), (sx * 0.150, 1.112, 0.082), 0.042, HORN, pieces=7)
        t += spike((sx * 0.055, 0.945, 0.232), (sx * 0.126, 1.048, 0.100), 0.030, HORN, pieces=6)
        t += spike((sx * 0.090, 0.900, 0.208), (sx * 0.176, 0.966, 0.126), 0.022, HORN, pieces=5)
        t += spike((sx * 0.104, 0.848, 0.286), (sx * 0.170, 0.812, 0.256), 0.020, HORN, pieces=5)
        t += spike((sx * 0.104, 0.826, 0.352), (sx * 0.162, 0.786, 0.340), 0.016, HORN, pieces=5)
    # 头顶冠刺（中线一排，连到背脊）
    t += spike((0.0, 0.972, 0.392), (0.0, 1.032, 0.452), 0.024, HORN, pieces=6)
    t += spike((0.0, 0.974, 0.288), (0.0, 1.044, 0.236), 0.022, HORN, pieces=5)
    t += spike((0.0, 0.954, 0.212), (0.0, 1.016, 0.160), 0.018, HORN, pieces=5)
    # 颈部两圈鳞环（上粗下细，跟着脖子走）
    t += ring_scale((0.0, 0.618, 0.138), (0.0, 0.155, 0.095), 0.134, 0.015, SCALE, seg=10)
    t += ring_scale((0.0, 0.755, 0.218), (0.0, 0.120, 0.065), 0.114, 0.013, SCALE, seg=10)
    return t


def wing():
    """右翼（+X 侧）：四片扇形翼膜 + 翼指骨 + 腕爪。局部在 XY 平面，之后整体贴到肩上。"""
    root = (0.02, 0.02, 0.0)
    wrist = (0.24, 0.24, 0.0)      # 腕关节
    f_a = (0.82, 0.42, 0.0)        # 指 1：最外最高
    f_b = (0.78, 0.08, 0.0)        # 指 2
    f_c = (0.60, -0.24, 0.0)       # 指 3
    f_d = (0.34, -0.32, 0.0)       # 指 4
    f_e = (0.10, -0.24, 0.0)       # 后缘接根
    t = []
    # 翼膜四片扇形：前缘亮 → 中段 → 根部深，指骨把膜撑出分叉的轮廓
    t += plate([wrist, f_a, f_b], WING_L, thick=0.016)
    t += plate([wrist, f_b, f_c], WING, thick=0.016)
    t += plate([wrist, f_c, f_d], WING, thick=0.016)
    t += plate([root, wrist, f_d, f_e], WING_D, thick=0.016)
    # 翼骨：根部一根粗骨 + 四根指骨 + 一根后缘骨
    t += seg(root, wrist, 0.032, 0.022, BODY_D, pieces=6)
    t += seg(wrist, f_a, 0.024, 0.008, BODY_D, pieces=6)
    t += seg(wrist, f_b, 0.020, 0.007, BODY_D, pieces=6)
    t += seg(wrist, f_c, 0.018, 0.007, BODY_D, pieces=5)
    t += seg(wrist, f_d, 0.015, 0.006, BODY_D, pieces=5)
    t += seg(root, f_e, 0.014, 0.006, BODY_D, pieces=5)
    # 腕部短钩爪（原来那根太长，像插了根针）
    t += spike(wrist, (0.32, 0.34, 0.0), 0.018, HORN, pieces=5)
    return t


def legs():
    """右后腿 + 右前腿（左腿靠 mirror_x）。"""
    t = []
    # 后腿：髋 → 膝 → 踝 → 脚
    hip = (0.135, 0.40, -0.20)
    knee = (0.175, 0.235, -0.10)
    ankle = (0.165, 0.075, -0.14)
    t += seg(hip, knee, 0.082, 0.062, BODY, pieces=8)
    t += seg(knee, ankle, 0.060, 0.045, BODY, pieces=8)
    t += box((0.165, 0.022, -0.075), (0.115, 0.045, 0.155), BODY_D)
    for i, dx in enumerate((-0.035, 0.0, 0.035)):
        t += spike((0.165 + dx, 0.026, 0.0), (0.165 + dx, 0.020, 0.075), 0.014, HORN, pieces=5)
    # 前腿：肩 → 肘 → 脚
    sh = (0.115, 0.42, 0.10)
    el = (0.155, 0.215, 0.145)
    ft = (0.150, 0.065, 0.175)
    t += seg(sh, el, 0.065, 0.050, BODY, pieces=8)
    t += seg(el, ft, 0.048, 0.040, BODY, pieces=8)
    t += box((0.150, 0.022, 0.215), (0.100, 0.045, 0.135), BODY_D)
    for dx in (-0.030, 0.0, 0.030):
        t += spike((0.150 + dx, 0.026, 0.275), (0.150 + dx, 0.020, 0.345), 0.012, HORN, pieces=5)
    return t


def tail():
    t = []
    p = [(0.0, 0.44, -0.30), (0.0, 0.38, -0.46), (0.02, 0.31, -0.60),
         (0.05, 0.25, -0.71), (0.09, 0.21, -0.79)]
    r = [0.105, 0.082, 0.058, 0.036, 0.018]
    for i in range(len(p) - 1):
        t += seg(p[i], p[i + 1], r[i], r[i + 1], BODY, pieces=8)
        # 每节中段套一圈鳞环，尾巴就有分节感
        t += ring_scale(mul(add(p[i], p[i + 1]), 0.5), sub(p[i + 1], p[i]),
                        (r[i] + r[i + 1]) * 0.5 + 0.005, 0.018, SCALE)
    # 尾尖的骨刺
    t += spike(p[-1], (0.15, 0.20, -0.87), 0.030, HORN, pieces=6)
    # 尾脊刺
    for i in range(3):
        base = (0.0 + 0.02 * i, 0.42 - 0.05 * i, -0.36 - 0.12 * i)
        t += spike(base, (base[0], base[1] + 0.075, base[2] - 0.03), 0.022, HORN, pieces=5)
    return t


def back_spines():
    t = []
    pts = [(0.0, 0.665, 0.13), (0.0, 0.655, 0.05), (0.0, 0.645, -0.04),
           (0.0, 0.63, -0.13), (0.0, 0.60, -0.21)]
    for i, b in enumerate(pts):
        h = 0.075 - 0.008 * i
        t += spike(b, (0.0, b[1] + h, b[2] - 0.012), 0.020 - 0.002 * i, HORN, pieces=5)
    return t


# ---------------------------------------------------------------- 鳞片
def torso_scales():
    """背部和两侧的细鳞（只做右半，左侧靠镜像）：越靠背脊越大越厚。"""
    center, radii = (0.0, 0.47, -0.01), (0.1995, 0.1805, 0.2698)
    t = []
    for v_deg in (10.0, 32.0, 54.0, 76.0):
        for u_deg in (20.0, 55.0, 90.0, 125.0, 160.0):
            u, v = math.radians(u_deg), math.radians(v_deg)
            p = ellip_point(center, radii, u, v)
            n = ellip_normal(center, radii, p)
            k = min(1.0, u_deg / 160.0)        # 1 = 背脊，0 = 前胸侧
            t += scale_at(p, n, 0.034 + 0.012 * k, 0.040 + 0.010 * k,
                          SCALE, rise=0.005 + 0.005 * k)
    return t


def belly_scales():
    """腹部亮色区：横向排布的扁腹甲片。"""
    center, radii = (0.0, 0.43, 0.08), (0.1426, 0.1240, 0.1780)
    t = []
    for v_deg in (-26.0, -4.0, 18.0):
        for u_deg in (-24.0, 0.0, 24.0):
            u, v = math.radians(u_deg), math.radians(v_deg)
            p = ellip_point(center, radii, u, v)
            n = ellip_normal(center, radii, p)
            t += scale_at(p, n, 0.052, 0.038, BELLY_D, rise=0.008)
    return t


def limb_scales():
    """右前腿 / 右后腿的鳞环（左侧靠镜像）。"""
    hip, knee = (0.135, 0.40, -0.20), (0.175, 0.235, -0.10)
    ankle = (0.165, 0.075, -0.14)
    sh, el = (0.115, 0.42, 0.10), (0.155, 0.215, 0.145)
    ft = (0.150, 0.065, 0.175)
    t = []
    for p0, p1, tt, r, h in ((hip, knee, 0.55, 0.076, 0.020),
                             (knee, ankle, 0.45, 0.058, 0.018),
                             (sh, el, 0.55, 0.061, 0.018),
                             (el, ft, 0.45, 0.048, 0.016)):
        d = sub(p1, p0)
        t += ring_scale(add(p0, mul(d, tt)), d, r, h, SCALE)
    return t


def head_scales():
    """颊部鳞片：贴在头骨侧面，压住眼后到颊刺之间的空当。"""
    t = []
    for sx in (-1, 1):
        t += scale_at((sx * 0.108, 0.908, 0.284), (sx * 0.97, 0.20, -0.14),
                      0.044, 0.038, SCALE, rise=0.008)
        t += scale_at((sx * 0.108, 0.874, 0.334), (sx * 0.97, 0.10, 0.22),
                      0.040, 0.034, SCALE, rise=0.007)
    return t


# ---------------------------------------------------------------- 组装
def build():
    tris = []
    tris += torso()
    tris += neck_head()
    tris += tail()
    tris += back_spines()
    # 鳞片：躯干（右半 → 镜像）、腹部、头部
    body_scales = torso_scales()
    tris += body_scales
    tris += mirror_x(body_scales)
    tris += belly_scales()
    tris += head_scales()
    # 右侧肢体 + 腿上的鳞环 → 镜像到左侧
    right = legs()
    right += limb_scales()
    tris += right
    tris += mirror_x(right)
    # 右翼：贴到右肩，稍微向后偏 + 后掠
    w = wing()
    w = xf(w, ry=0.45, rz=0.10)                         # 后掠（翼尖往后）+ 微抬
    w = xf(w, t=(0.115, 0.585, 0.02))
    tris += w
    tris += mirror_x(w)
    return tris


def main():
    tris = build()
    n, m = save_glb(OUT, tris, "dragon")
    print("dragon.glb: %d 三角形, %d 材质 -> %s" % (n, m, os.path.abspath(OUT)))


if __name__ == "__main__":
    main()
