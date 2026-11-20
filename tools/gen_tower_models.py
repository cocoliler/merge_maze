#!/usr/bin/env python3
"""参照 Kingdom Rush 2D 立绘的造型特征，程序化生成低多边形防御塔 GLB。

7 种塔各挑了一个素材原型（注释里的编号是 encyclopedia_towers-<n>）：
    箭塔    #61-64  木屋 + 干草尖顶 + 正面红白靶心
    炮塔    #21-24  砖石鼓座 + 粗黑炮管上扬 + 木炮车
    冰塔    #9-12   白蓝石座 + 悬浮冰晶 + 冰刺
    狙击塔  #77-80  高石塔 + 弩炮横臂 + 蓝旗
    电塔    #37-40  金托碗 + 发光蓝球 + 金翼片
    火塔    #41-44  暗红石座 + 火盆 + 紫色晶簇 + 尖角
    弹射塔  #69-71  木桶铁箍 + 机械发射槽 + 石足

比例参考：现有 Kenney 塔在 SCALE=2.0 下约 4.9 世界单位高、底宽 2.0，
所以这里所有模型都按「高:宽 ≈ 2.1」来配比，游戏侧再统一按高度缩放。

等级推进 = 加高一层石砌 + 多一圈雕饰/旗/尖刺，和素材 L1→L4 的加料节奏一致。

输出：models/towers/tower_<类型>_l<等级>.glb
坐标约定见 tools/lowpoly_kit.py（原点脚底、+Y 向上、正面 +Z）。

用法：
    python tools/gen_tower_models.py
"""

from __future__ import annotations

import argparse
import math
import os

from lowpoly_kit import *  # noqa: F401,F403  (图元 + 色板 + save_glb)

BOUNCE_GLOW = (0.45, 0.95, 0.62)
TESLA_ORB = (0.70, 0.94, 1.00)
COURSE = 0.17          # 石砌单圈高度



# ---------------------------------------------------------------- 公共件
def plinth(courses=2, r=0.30, y0=0.0, ch=COURSE, col=STONE, seg=12):
    """石砌鼓形基座：一圈圈往上砌，最上面一道压边。

    素材里几乎每座塔都有这个底座，等级越高圈数越多 —— 最省事也最像的等级语言。
    """
    t = []
    for i in range(max(courses, 1)):
        rr = r * (1.0 - 0.045 * i)
        t += cyl((0.0, y0 + i * ch, 0.0), rr, rr * 0.97, ch,
                 col if i % 2 == 0 else shade(col, 0.9), seg=seg)
    top = y0 + max(courses, 1) * ch
    t += cyl((0.0, top, 0.0), r * 0.99, r * 0.92, 0.045, shade(col, 1.12), seg=seg)
    return t


def keg(center, r, h, col=WOOD):
    """小酒桶（炮塔/箭塔侧边的点缀）。"""
    cx, cy, cz = center
    t = lathe([(r * 0.72, 0.0), (r, h * 0.28), (r, h * 0.72), (r * 0.72, h)],
              col, seg=8, center=(cx, cy, cz))
    for f in (0.26, 0.72):
        t += cyl((cx, cy + h * f, cz), r * 1.05, r * 1.05, h * 0.075, IRON, seg=8)
    return t


# ---------------------------------------------------------------- 箭塔
def build_arrow(level):
    """#61-64：木屋 + 干草尖顶 + 正面靶心。靶心是这个原型最好认的特征。"""
    t = plinth(2, 0.30, col=STONE)
    y0 = 2 * COURSE + 0.045
    w = 0.46 + 0.02 * (level - 1)
    hw = w * 0.5

    # 木屋主体 + 竖向木板
    t += taper((0.0, y0 + 0.28, 0.0), (w + 0.03, w + 0.03), (w, w), 0.56, WOOD)
    for i in (-1, 1):
        t += box((i * hw * 0.55, y0 + 0.28, hw + 0.006), (0.022, 0.52, 0.012),
                 shade(WOOD, 1.32))

    # 正面靶心：白-红-白-红同心圆
    ty = y0 + 0.30
    tz = hw + 0.010
    for k, (rr, cc) in enumerate(((0.125, WHITE), (0.096, RED),
                                  (0.060, WHITE), (0.026, RED))):
        t += cyl_z((0.0, ty, tz + k * 0.011), rr, rr, 0.011, cc, seg=12)

    # 干草尖顶：檐口 + 收尖
    ry = y0 + 0.56
    t += lathe([(0.315, ry - 0.015), (0.345, ry + 0.030)], THATCH_D, seg=12)
    t += lathe([(0.305, ry + 0.020), (0.275, ry + 0.130),
                (0.115, ry + 0.420), (0.015, ry + 0.540)], THATCH, seg=12)

    if level >= 2:
        t += crenels((0.0, y0 + 0.005, 0.0), hw + 0.055, 8, 0.078, 0.090, STONE_L)
        t += keg((hw + 0.085, y0 - 0.06, 0.10), 0.048, 0.125)
    if level >= 3:
        t += cyl((0.0, ry + 0.520, 0.0), 0.012, 0.010, 0.22, WOOD_D, seg=6)
        t += taper((0.075, ry + 0.640, 0.0), (0.125, 0.016), (0.07, 0.016), 0.140, RED)
        t += keg((-hw - 0.075, y0 - 0.06, 0.08), 0.048, 0.125)
        t += box((0.0, ry + 0.095, hw + 0.02), (0.13, 0.05, 0.03), GOLD)
    return t


# ---------------------------------------------------------------- 炮塔
def twin_barrels(y1, r, ln):
    """双管齐射（cannon_twin）：两根细管嵌在同一个炮座上，整体上扬。

    要点是「一体」——共用一个木炮座、一根中间轴套和同一个后座，
    而不是把单管复制成两根各自摇摆的独立零件。
    """
    rr = r * 0.58
    ll = ln * 0.80
    g = box((0.0, 0.0, -0.045), (0.235, 0.135, 0.20), WOOD_D)
    g += cyl_z((0.0, 0.0, 0.030), 0.095, 0.088, 0.085, IRON, seg=10)     # 中间轴套
    g += cyl_z((0.0, 0.0, -0.145), 0.070, 0.062, 0.075, IRON, seg=8)     # 后座
    for sx in (-1, 1):
        tube = cyl_z((0.0, 0.0, 0.0), rr, rr * 1.10, ll, IRON, seg=9)
        for f in (0.28, 0.62):
            tube += cyl_z((0.0, 0.0, f * ll), rr * 1.22, rr * 1.22, 0.022,
                          shade(IRON, 1.5), seg=9)
        tube += cyl_z((0.0, 0.0, ll), rr * 1.14, rr * 1.34, 0.052, BRONZE, seg=9)
        tube += cyl_z((0.0, 0.0, ll + 0.052), rr * 0.92, rr * 0.92, 0.007, DARK, seg=9)
        g += xf(tube, t=(sx * 0.088, 0.0, 0.055))
    # 后方弹药箱：弹幕路线最直观的辨识点
    g += box((0.0, 0.085, -0.155), (0.145, 0.085, 0.10), WOOD)
    g += cyl_z((0.0, 0.085, -0.205), 0.030, 0.030, 0.020, BRONZE, seg=8)
    return xf(g, t=(0.0, y1 + 0.125, -0.135), rx=-0.44)


def build_cannon(level, twin=False):
    """#21-24：石座 + 木炮车 + 上扬的粗炮管。炮口要夸张，远看就是一个黑洞。

    炮车和炮管单独返回（turret），游戏里绕炮座中心转向目标。
    twin=True 时换成「双管齐射」变异的外观：一体的双炮管 + 弹药箱。
    """
    t = plinth(level, 0.31, col=STONE)
    y0 = level * COURSE

    # 主鼓身（炮塔比箭塔矮壮，这是原型的特征）
    t += cyl((0.0, y0, 0.0), 0.275, 0.265, 0.52, BRICK, seg=12)
    t += cyl((0.0, y0 + 0.24, 0.0), 0.285, 0.285, 0.045, shade(BRICK, 1.15), seg=12)
    t += cyl((0.0, y0 + 0.50, 0.0), 0.29, 0.30, 0.055, STONE_L, seg=12)
    y1 = y0 + 0.555

    # 炮车（会转的部分）
    u = taper((0.0, y1 + 0.065, 0.0), (0.44, 0.36), (0.38, 0.32), 0.13, WOOD_D)
    for sx in (-1, 1):
        u += wheel((sx * 0.225, y1 + 0.085, 0.03), 0.085, 0.055, WOOD)

    # 炮管：局部坐标构建 → 整体上扬 → 落位
    r = 0.075 + 0.014 * (level - 1)
    ln = 0.36 + 0.06 * (level - 1)
    if twin:
        u += twin_barrels(y1, r, ln)
    else:
        bar = cyl_z((0.0, 0.0, 0.0), r, r * 1.10, ln, IRON, seg=10)
        for f in (0.22, 0.52, 0.82):
            bar += cyl_z((0.0, 0.0, f * ln), r * 1.22, r * 1.22, 0.028,
                         shade(IRON, 1.5), seg=10)
        bar += cyl_z((0.0, 0.0, ln), r * 1.16, r * 1.36, 0.060, BRONZE, seg=10)
        bar += cyl_z((0.0, 0.0, ln + 0.060), r * 0.92, r * 0.92, 0.008, DARK, seg=10)
        u += xf(bar, t=(0.0, y1 + 0.125, -0.145), rx=-0.44)

    if level >= 2:
        t += keg((0.245, y0 + 0.02, 0.02), 0.058, 0.145)
        u += box((0.0, y1 + 0.145, -0.14), (0.17, 0.10, 0.11), WOOD_D)
    if level >= 3:
        t += keg((-0.245, y0 + 0.02, 0.02), 0.058, 0.145)
        t += spikes(6, (0.0, y0 + 0.04, 0.0), 0.305, 0.085, 0.030, IRON, tilt=0.9, phase=0.3)
        u += box((0.0, y1 + 0.13, -0.30), (0.15, 0.11, 0.07), IRON)
    return t, u, (0.0, y1, 0.0)


# ---------------------------------------------------------------- 冰塔
def build_frost(level):
    """#9-12：白蓝石座 + 冰柱 + 悬浮冰晶。造型要"细高 + 冷"。"""
    t = []
    t += lathe([(0.275, 0.0), (0.305, 0.065), (0.285, 0.125)], ICE_L, seg=12)
    t += lathe([(0.285, 0.120), (0.235, 0.165)], ICE_D, seg=12)

    h = 0.55 + 0.10 * (level - 1)
    t += lathe([(0.185, 0.160), (0.135, 0.160 + h * 0.55), (0.175, 0.160 + h)], ICE, seg=12)
    t += spikes(4, (0.0, 0.140, 0.0), 0.245, 0.135, 0.036, ICE_D, tilt=0.60, phase=0.78)

    cy = 0.160 + h + 0.150
    t += cyl((0.0, cy - 0.075, 0.0), 0.095, 0.120, 0.026, ICE_D, seg=12)
    t += octa((0.0, cy, 0.0), 0.088 + 0.014 * level, 0.175 + 0.025 * level, ICE_L)

    if level >= 2:
        t += spikes(3, (0.0, 0.160 + h, 0.0), 0.165, 0.155, 0.030, ICE_L, tilt=0.95, phase=0.30)
    if level >= 3:
        t += spikes(5, (0.0, cy, 0.0), 0.145, 0.125, 0.024, ICE_L, tilt=1.15, phase=0.62)
        t += sph((0.0, cy, 0.0), 0.052, WHITE, seg=8, rings=5)
        t += lathe([(0.335, 0.0), (0.355, 0.028)], shade(ICE_D, 0.9), seg=12)
    return t


# ---------------------------------------------------------------- 狙击塔
def build_sniper(level):
    """#77-80：高石塔 + 弩炮横臂 + 侧面蓝旗。塔身必须高，才像"远程"。

    弩炮座单独返回（turret），游戏里跟着目标水平转向；石塔和旗子不动。
    """
    t = []
    courses = level + 2
    t += plinth(courses, 0.27, ch=0.22, col=STONE)
    y0 = courses * 0.22 + 0.045
    t += cyl((0.0, y0, 0.0), 0.275, 0.305, 0.055, STONE_L, seg=12)
    py = y0 + 0.055

    if level >= 2:
        t += crenels((0.0, py, 0.0), 0.315, 8, 0.072, 0.065, STONE_L, phase=0.4)

    # 弩炮：托座 + 木枕 + 双翼 + 弦 + 弩箭
    u = box((0.0, py + 0.040, 0.0), (0.125, 0.070, 0.125), WOOD_D)
    u += box((0.0, py + 0.085, 0.03), (0.075, 0.048, 0.38), WOOD)
    limb = 0.21 + 0.022 * level
    for sx in (-1, 1):
        u += xf(box((0.0, 0.0, 0.0), (limb, 0.030, 0.032), shade(WOOD, 0.85)),
                t=(sx * limb * 0.45, py + 0.098, 0.080), ry=sx * 0.55)
    u += box((0.0, py + 0.098, 0.0), (limb * 0.92, 0.010, 0.010), BONE)
    u += cyl_z((0.0, py + 0.110, 0.02), 0.014, 0.012, 0.24 + 0.03 * level, BONE, seg=6)
    u += cone((0.0, py + 0.110, 0.0), 0.021, 0.055, STEEL, seg=5)

    # 蓝旗
    t += banner((-0.315, py + 0.19, 0.0), 0.105, 0.22, 0.13, BANNER)
    if level >= 3:
        t += banner((0.315, py + 0.19, 0.0), 0.105, 0.22, 0.13, BANNER)
        t += cyl((0.0, py + 0.11, 0.0), 0.017, 0.013, 0.24, WOOD_D, seg=6)
        t += box((0.0, py + 0.37, 0.0), (0.058, 0.048, 0.058), GOLD)
        u += box((0.0, py + 0.055, -0.30), (0.17, 0.08, 0.055), WOOD_D)
    return t, u, (0.0, py, 0.0)


# ---------------------------------------------------------------- 电塔
def build_tesla(level):
    """#37-40：金托碗 + 发光蓝球 + 金色翼片。球要够大，远看就是一团光。"""
    t = plinth(level, 0.29, col=WHITE)
    y0 = level * COURSE

    t += lathe([(0.265, y0), (0.315, y0 + 0.060), (0.245, y0 + 0.130)], GOLD, seg=12)
    t += cyl((0.0, y0 + 0.130, 0.0), 0.215, 0.195, 0.30, WHITE, seg=12)
    t += cyl((0.0, y0 + 0.430, 0.0), 0.205, 0.245, 0.055, GOLD, seg=12)
    cy = y0 + 0.485

    r = 0.150 + 0.018 * (level - 1)
    t += sph((0.0, cy + r * 0.92, 0.0), r, TESLA_ORB, seg=12, rings=8)
    for i in range(4):
        a = TAU * i / 4.0 + 0.785
        t += xf(box((0.0, 0.0, 0.0), (0.055, 0.125, 0.016), GOLD),
                t=(math.cos(a) * r * 1.30, cy + r * 0.92, math.sin(a) * r * 1.30),
                ry=-a, rz=0.28)

    if level >= 2:
        t += cyl((0.0, cy + r * 1.86, 0.0), 0.115, 0.085, 0.042, GOLD, seg=10)
        for sx in (-1, 1):
            t += box((sx * 0.275, y0 + 0.06, 0.0), (0.065, 0.115, 0.175), GOLD)
    if level >= 3:
        for i in range(4):
            a = TAU * i / 4.0 + 0.39
            t += cyl((math.cos(a) * 0.200, cy + 0.02, math.sin(a) * 0.200),
                     0.017, 0.013, 0.17, BRONZE, seg=6)
            t += octa((math.cos(a) * 0.200, cy + 0.22, math.sin(a) * 0.200),
                      0.030, 0.048, GOLD)
        t += octa((0.0, cy + r * 1.98, 0.0), 0.038, 0.085, GOLD)
    return t


# ---------------------------------------------------------------- 火塔
def build_flame(level):
    """#41-44：暗红石座 + 火盆 + 紫色晶簇。火焰用三层锥做体积。"""
    t = plinth(level, 0.30, col=BRICK)
    y0 = level * COURSE

    t += cyl((0.0, y0, 0.0), 0.265, 0.235, 0.26, shade(BRICK, 0.85), seg=12)
    # 火盆（外壁 + 炭火面 + 铁箍）
    t += lathe([(0.165, y0 + 0.26), (0.300, y0 + 0.320), (0.325, y0 + 0.420)],
               shade(BRICK, 0.74), seg=12)
    t += lathe([(0.280, y0 + 0.412), (0.255, y0 + 0.432)], EMBER, seg=12)
    t += cyl((0.0, y0 + 0.360, 0.0), 0.328, 0.328, 0.024, IRON, seg=12)

    # 火焰：外焰 → 中焰 → 亮芯
    fy = y0 + 0.425
    t += cone((0.0, fy, 0.0), 0.150, 0.36 + 0.06 * level, EMBER, seg=7)
    t += cone((0.0, fy, 0.0), 0.095, 0.50 + 0.07 * level, FIRE, seg=7)
    t += cone((0.050, fy, -0.040), 0.060, 0.42 + 0.05 * level, FIRE_HOT, seg=6)
    t += cone((-0.055, fy, 0.035), 0.048, 0.34 + 0.05 * level, FIRE_HOT, seg=6)

    # 底部紫晶簇
    for i in range(4):
        a = TAU * i / 4.0 + 0.5
        t += octa((math.cos(a) * 0.285, y0 * 0.55, math.sin(a) * 0.285),
                  0.036, 0.065, AMETHYST)
    if level >= 2:
        for i in range(4):
            a = TAU * i / 4.0 + 0.785
            t += box((math.cos(a) * 0.270, y0 + 0.055, math.sin(a) * 0.270),
                     (0.055, 0.10, 0.055), IRON, ry=-a)
    if level >= 3:
        for sx in (-1, 1):
            t += xf(cone((0.0, 0.0, 0.0), 0.052, 0.20, BONE, seg=5),
                    t=(sx * 0.285, y0 + 0.400, 0.0), rz=sx * 0.62)
        t += spikes(5, (0.0, fy + 0.50, 0.0), 0.125, 0.095, 0.024, EMBER, tilt=0.7, phase=0.9)
    return t


# ---------------------------------------------------------------- 弹射塔
def build_bounce(level):
    """#69-71：木桶 + 铁箍 + 机械发射槽。桶身用 lathe 鼓出肚子，一眼是"桶"。

    发射槽单独返回（turret），游戏里跟着目标水平转向。
    """
    t = []
    for i in range(4):
        a = TAU * i / 4.0 + 0.785
        t += box((math.cos(a) * 0.225, 0.035, math.sin(a) * 0.225),
                 (0.105, 0.070, 0.105), STONE)
    r = 0.215 + 0.016 * (level - 1)
    t += lathe([(r * 0.66, 0.065), (r, 0.220), (r, 0.480), (r * 0.68, 0.640)], WOOD, seg=12)
    for yy in (0.210, 0.470):
        t += cyl((0.0, yy, 0.0), r * 1.03, r * 1.03, 0.028, IRON, seg=12)

    # 发射槽（局部构建 → 上扬落位）
    piv = (0.0, 0.615, -0.090)
    trough = box((0.0, 0.0, 0.0), (0.145, 0.042, 0.38), shade(WOOD, 0.85))
    for sx in (-1, 1):
        trough += box((sx * 0.073, 0.050, 0.0), (0.022, 0.052, 0.38), WOOD_D)
    for k in range(3):
        trough += cyl_z((0.0, 0.034, 0.02 + k * 0.060), 0.013, 0.013, 0.032, GOLD, seg=6)
    trough += sph((0.0, 0.060, 0.175), 0.048 + 0.007 * level, BOUNCE_GLOW, seg=10, rings=6)
    u = xf(trough, t=piv, rx=-0.52)

    if level >= 2:
        for sx in (-1, 1):
            t += xf(box((0.0, 0.0, 0.0), (0.032, 0.150, 0.032), IRON),
                    t=(sx * 0.175, 0.330, 0.095), rz=sx * 0.32)
    if level >= 3:
        for sx in (-1, 1):
            for sz in (-1, 1):
                t += xf(taper((0.0, 0.0, 0.0), (0.058, 0.058), (0.036, 0.036), 0.145, IRON),
                        t=(sx * 0.235, 0.170, sz * 0.235), rz=sx * 0.45, rx=-sz * 0.45)
        t += cyl((0.0, 0.030, 0.0), 0.105, 0.075, 0.032, BOUNCE_GLOW, seg=10)
        t += sph((0.0, 0.60, 0.0), 0.068, BOUNCE_GLOW, seg=10, rings=6)
    return t, u, piv


TOWERS = {
    "arrow": (build_arrow, "箭塔"),
    "cannon": (build_cannon, "炮塔"),
    "frost": (build_frost, "冰塔"),
    "sniper": (build_sniper, "狙击塔"),
    "tesla": (build_tesla, "电塔"),
    "flame": (build_flame, "火塔"),
    "bounce": (build_bounce, "弹射塔"),
}

MAX_LEVEL = 3


def main() -> int:
    ap = argparse.ArgumentParser()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--out", default=os.path.join(root, "models", "towers"))
    args = ap.parse_args()

    total = 0
    print("%-22s %-8s %3s %5s %5s %6s %6s %s" % ("file", "tower", "lv", "tris", "mats",
                                                 "h/w", "h", "w"))
    for suffix, (fn, label) in TOWERS.items():
        for lv in range(1, MAX_LEVEL + 1):
            res = fn(lv)
            if isinstance(res, tuple):
                body, turret, pivot = res
            else:
                body, turret, pivot = res, None, None
            tris = body + turret if turret else body
            name = "tower_%s_l%d" % (suffix, lv)
            save_glb(os.path.join(args.out, name + ".glb"), body, name,
                     turret=turret, turret_pivot=pivot or (0.0, 0.0, 0.0))
            total += len(tris)
            xs = [p[0] for a, b, c, _ in tris for p in (a, b, c)]
            ys = [p[1] for a, b, c, _ in tris for p in (a, b, c)]
            h = max(ys) - min(ys)
            w = max(xs) - min(xs)
            print("%-22s %-8s %3d %5d %5d %6.2f %6.2f %6.2f" % (
                name + ".glb", label, lv, len(tris), 0, h / w, h, w))

    # 变异专属外观：双管齐射（cannon_twin）—— 满级炮塔换成一体的双炮管
    body, turret, pivot = build_cannon(MAX_LEVEL, twin=True)
    name = "tower_cannon_l3_twin"
    save_glb(os.path.join(args.out, name + ".glb"), body, name,
             turret=turret, turret_pivot=pivot)
    total += len(body) + len(turret)
    print("%-22s %-8s %3d %5d" % (name + ".glb", "双管炮塔", MAX_LEVEL,
                                  len(body) + len(turret)))

    print("total tris = %d, out = %s" % (total, args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
