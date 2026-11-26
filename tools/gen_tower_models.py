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
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lowpoly_kit import *  # noqa: F401,F403  (图元 + 色板 + save_glb)
import gen_dragon_model as dragon_mod  # noqa: E402  火塔塔顶的火龙造型

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


# ---------------------------------------------------------------- 箭塔·八角木骨
## KR 箭塔（go_towers_archers）最好认的结构：一圈木柱 + 柱间石墙板 + 八角箭台 +
## 八角栏杆 + 正面红白靶心。下面三个变异都复用这套骨架，再各自加一层完全不同的"帽子"，
## 保证远远看过去三座塔的轮廓互不相同。
WOOD_L = (0.58, 0.41, 0.24)
MARBLE = (0.87, 0.89, 0.91)
GALE = (0.42, 0.88, 0.56)       # 疾风弩：青绿
GALE_D = shade(GALE, 0.66)
PIERCE = (0.80, 0.84, 0.36)     # 裂空箭：橄榄黄
SPLIT = (0.36, 0.88, 1.00)      # 穿云矢：冰青
SPLIT_D = shade(SPLIT, 0.62)


def rot_y(tris, center, a):
    """绕自身中心转 Y —— box() 的 ry 是绕原点转的，用在环状排布上会把零件甩飞。"""
    return xf(tris, ry=a, pivot=center) if a else tris


def oct_frame(center, r, count, h, wood, panel, panel_scale=0.86, post=0.055):
    """八角木骨：一圈立柱 + 柱间墙板。"""
    cx, cy, cz = center
    side = 2.0 * r * math.sin(math.pi / count)
    t = []
    for i in range(count):
        a = TAU * i / count + math.pi / count
        px, pz = cx + math.cos(a) * r, cz + math.sin(a) * r
        t += rot_y(box((px, cy + h * 0.5, pz), (post, h, post), wood), (px, cy + h * 0.5, pz), -a)
        if panel:
            qx, qz = cx + math.cos(a) * r * 0.955, cz + math.sin(a) * r * 0.955
            t += rot_y(box((qx, cy + h * 0.5, qz), (0.035, h * 0.88, side * panel_scale), panel),
                       (qx, cy + h * 0.5, qz), -a)
    return t


def oct_deck(cx, cz, y, r, col, seg=8, h=0.07):
    """八角箭台（带一点外沿，像木板挑出来的栈台）。"""
    return lathe([(r * 0.98, 0.0), (r * 1.12, h * 0.45), (r * 1.02, h)], col, seg=seg,
                 center=(cx, y, cz))


def oct_rail(center, r, count, h, col):
    """八角栏杆：短立柱 + 顶栏。"""
    cx, cy, cz = center
    side = 2.0 * r * math.sin(math.pi / count)
    t = []
    for i in range(count):
        a = TAU * i / count + math.pi / count
        px, pz = cx + math.cos(a) * r, cz + math.sin(a) * r
        t += rot_y(box((px, cy + h * 0.5, pz), (0.032, h, 0.032), col), (px, cy + h * 0.5, pz), -a)
        t += rot_y(box((px, cy + h, pz), (0.028, 0.028, side * 0.92), col), (px, cy + h, pz), -a)
    return t


def bullseye(y, z, scale=1.0, outer=WHITE, inner=RED):
    """正面靶心：白-红-白-红同心圆（箭塔的招牌特征）。"""
    t = []
    for k, (rr, cc) in enumerate(((0.125, outer), (0.096, inner), (0.060, outer), (0.026, inner))):
        t += cyl_z((0.0, y, z + k * 0.011), rr * scale, rr * scale, 0.011, cc, seg=12)
    return t


def pennant(y, x, z, h, col, flip=1.0):
    """三角小旗：细杆 + 布面（用两个三角面表达，省三角形）。"""
    t = cyl((x, y, z), 0.013, 0.010, h + 0.10, WOOD_D, seg=5)
    top = y + h + 0.08
    w = 0.085 * flip
    a = (x, top, z)
    b = (x, top - 0.11, z)
    c = (x + w, top - 0.045, z)
    t += [(a, b, c, col), (a, c, b, col)]
    return t


# ---------------------------------------------------------------- 箭塔·疾风弩（gale）
def build_arrow_gale():
    """疾风弩：矮而宽的**开放式**箭台 + 高旗杆 + 双联轻弩。

    轮廓要点：没有屋顶（顶部敞开，能看到弩）、塔身压得低、四周插满细旗杆，
    远看就是一团青绿色的"风"；和另外两条线的"封闭高塔 / 晶环"完全不一样。
    """
    r = 0.34
    t = plinth(2, 0.36, col=STONE_L)
    y0 = 2 * COURSE + 0.045

    # 八角木屋（墙板换成浅木色，塔身比另外两条线更"方"）
    t += oct_frame((0.0, y0, 0.0), r, 8, 0.58, WOOD_L, shade(WOOD, 0.80))
    py = y0 + 0.58

    # 箭台 + 栏杆 + 靶心
    t += oct_deck(0.0, 0.0, py - 0.03, r * 1.04, shade(WOOD, 1.18))
    t += oct_rail((0.0, py + 0.04, 0.0), r * 1.04, 8, 0.14, shade(WOOD, 1.30))
    t += bullseye(py - 0.24, r * 1.10, 0.56, WHITE, GALE_D)

    # 四角旗杆 + 青绿旗（"疾风"的视觉语言）
    for i in range(4):
        a = TAU * i / 4.0 + math.pi / 4.0
        px, pz = math.cos(a) * r * 0.92, math.sin(a) * r * 0.92
        hh = 0.64 if i % 2 == 0 else 0.46
        t += pennant(py + 0.10, px, pz, hh, GALE if i % 2 == 0 else GALE_D)

    # 抬高的弩架：四根细腿托起一个小圆台，把双联轻弩举到接近塔顶
    # （子弹是从弩口飞出去的，弩举得够高才不会看起来"从塔肚子里射箭"）
    ry = py + 0.50
    for i in range(4):
        a = TAU * i / 4.0 + math.pi / 4.0
        lx, lz = math.cos(a) * 0.185, math.sin(a) * 0.185
        t += xf(cyl((0.0, 0.0, 0.0), 0.020, 0.016, 0.54, WOOD_D, seg=5),
                t=(lx, py + 0.01, lz), rx=-math.sin(a) * 0.08, rz=math.cos(a) * 0.08)
    t += lathe([(0.195, 0.0), (0.222, 0.022), (0.195, 0.044)], shade(WOOD, 1.15), seg=8,
               center=(0.0, ry, 0.0))

    # 塔身挂两个箭袋：一眼就是"快速连射"的塔
    for sx in (-1, 1):
        t += keg((sx * (r + 0.052), y0 + 0.22, 0.05), 0.045, 0.18)

    # 顶部双联轻弩（独立 Turret，会跟着目标转）
    pivot = (0.0, ry + 0.05, 0.0)
    u = cyl((0.0, 0.0, 0.0), 0.10, 0.088, 0.05, WOOD_D, seg=10)
    u += box((0.0, 0.068, -0.03), (0.15, 0.062, 0.17), shade(WOOD, 1.05))
    u += box((0.0, 0.112, 0.06), (0.088, 0.042, 0.30), shade(WOOD, 1.16))
    for sx in (-1, 1):
        # 一对轻弩臂（向前张开）
        u += xf(box((0.0, 0.0, 0.0), (0.235, 0.026, 0.030), shade(WOOD, 0.86)),
                t=(sx * 0.072, 0.132, 0.10), ry=sx * 0.60)
        u += box((sx * 0.088, 0.132, 0.16), (0.170, 0.008, 0.008), BONE)
        # 双箭
        u += cyl_z((sx * 0.042, 0.134, 0.09), 0.010, 0.009, 0.20, BONE, seg=6)
        u += xf(cone((0.0, 0.0, 0.0), 0.017, 0.055, STEEL, seg=5),
                t=(sx * 0.042, 0.134, 0.29), rx=math.pi * 0.5)
    u += pennant(0.10, 0.0, -0.115, 0.19, GALE)
    u = xf(u, t=pivot)
    return t, u, pivot


# ---------------------------------------------------------------- 箭塔·裂空箭（pierce）
def build_arrow_pierce():
    """裂空箭：高而瘦的重装塔 —— 石砌塔身 + 三道铁箍 + 四道扶壁 + 一台巨型穿甲弩。

    轮廓要点：三座里最高最窄，塔身正面嵌一根铁质长箭浮雕，弩臂特别长、箭特别粗，
    颜色是橄榄黄 + 铁灰，和"木色小箭台""青色晶塔"完全分得开。
    """
    t = plinth(3, 0.30, ch=0.20, col=STONE_D)
    y0 = 3 * 0.20 + 0.045

    # 高瘦石鼓
    t += cyl((0.0, y0, 0.0), 0.255, 0.222, 0.86, shade(STONE, 0.92), seg=10)
    for fy in (0.12, 0.40, 0.68):
        t += cyl((0.0, y0 + fy, 0.0), 0.264, 0.264, 0.034, IRON, seg=10)

    # 四道扶壁（下宽上窄，给"重装"的份量）
    for i in range(4):
        a = TAU * i / 4.0 + math.pi / 4.0
        px, pz = math.cos(a) * 0.245, math.sin(a) * 0.245
        b = taper((0.0, 0.0, 0.0), (0.115, 0.085), (0.055, 0.055), 0.40, STONE_L)
        t += xf(b, t=(px, y0 + 0.20, pz), ry=-a)

    # 顶部平台 + 城垛
    py = y0 + 0.86
    t += cyl((0.0, py, 0.0), 0.268, 0.300, 0.055, STONE_L, seg=10)
    t += oct_frame((0.0, py + 0.055, 0.0), 0.285, 8, 0.10, IRON, None, post=0.045)

    # 正面：铁质长箭浮雕（取代靶心 —— 这条线是"穿透"不是"打靶"）
    rz = 0.268
    t += box((0.0, py - 0.34, rz), (0.052, 0.46, 0.022), IRON)
    t += xf(cone((0.0, 0.0, 0.0), 0.062, 0.16, STEEL, seg=4),
            t=(0.0, py - 0.09, rz), rx=math.pi * 0.5)
    for sx in (-1, 1):
        t += box((sx * 0.070, py - 0.50, rz), (0.026, 0.10, 0.018), PIERCE)

    # 两侧窄长旗 + 底部铁刺
    for sx in (-1, 1):
        t += banner((sx * 0.315, py - 0.26, 0.0), 0.095, 0.34, 0.13, PIERCE)
    t += spikes(6, (0.0, y0 + 0.01, 0.0), 0.30, 0.10, 0.030, IRON, tilt=0.85, phase=0.2)

    # 顶部巨型穿甲弩（独立 Turret）
    pivot = (0.0, py + 0.10, 0.0)
    u = cyl((0.0, 0.0, 0.0), 0.115, 0.100, 0.052, IRON, seg=10)
    u += box((0.0, 0.070, -0.03), (0.16, 0.075, 0.19), shade(WOOD, 0.92))
    u += box((0.0, 0.120, 0.06), (0.105, 0.058, 0.44), shade(WOOD, 0.80))   # 弩身
    u += box((0.0, 0.152, 0.06), (0.030, 0.014, 0.42), IRON)                # 滑轨
    limb = 0.30
    for sx in (-1, 1):
        u += xf(box((0.0, 0.0, 0.0), (limb, 0.046, 0.038), STEEL_D),
                t=(sx * 0.175, 0.150, 0.02), ry=sx * 0.92)
        u += box((sx * 0.20, 0.150, -0.10), (0.012, 0.010, 0.34), BONE)     # 弦
        u += box((sx * 0.115, 0.130, 0.02), (0.045, 0.085, 0.045), IRON)    # 铁夹
    # 巨箭：粗杆 + 钢箭头 + 尾羽
    u += cyl_z((0.0, 0.148, -0.10), 0.024, 0.021, 0.66, WOOD_D, seg=8)
    u += xf(cone((0.0, 0.0, 0.0), 0.048, 0.155, STEEL, seg=6),
            t=(0.0, 0.148, 0.555), rx=math.pi * 0.5)
    for sx in (-1, 1):
        u += box((sx * 0.035, 0.148, -0.30), (0.010, 0.055, 0.10), PIERCE)
    u = xf(u, t=pivot)
    return t, u, pivot


# ---------------------------------------------------------------- 箭塔·穿云矢（split）
def build_arrow_split():
    """穿云矢：白石塔身 + 青色冰晶肋 + 一圈悬浮碎晶 + 水晶双叉弩。

    轮廓要点：中等身高，但塔顶套着一圈**浮空晶环**（环和塔身之间是空的，读起来像魔法），
    颜色是白石 + 冰青，一眼就是"会弹射的箭"。
    """
    r = 0.36
    t = plinth(2, 0.35, col=MARBLE)
    y0 = 2 * COURSE + 0.045

    # 白石鼓身 + 收口（比疾风弩细、比裂空箭矮）
    t += cyl((0.0, y0, 0.0), 0.286, 0.258, 0.90, MARBLE, seg=12)
    t += cyl((0.0, y0 + 0.88, 0.0), 0.264, 0.282, 0.045, shade(MARBLE, 1.06), seg=12)

    # 四道冰晶肋（竖向晶体条，塔身的"魔法纹路"）
    for i in range(4):
        a = TAU * i / 4.0 + math.pi / 4.0
        px, pz = math.cos(a) * 0.272, math.sin(a) * 0.272
        t += xf(octa((0.0, 0.0, 0.0), 0.028, 0.34, SPLIT), t=(px, y0 + 0.44, pz))
    # 正面靶心（保留箭塔的识别符号，换成青白配色）
    t += bullseye(y0 + 0.44, 0.284, 0.70, ICE_L, SPLIT_D)

    py = y0 + 0.925

    # 八角箭台 + 栏杆
    t += oct_deck(0.0, 0.0, py - 0.02, r * 1.02, shade(MARBLE, 0.98))
    t += oct_rail((0.0, py + 0.04, 0.0), r * 1.02, 8, 0.13, shade(MARBLE, 1.10))

    # 悬浮晶环：一圈细环 + 6 颗浮空碎晶（环与塔身留空，看得出是"悬"的）
    ry = py + 0.30
    t += lathe([(0.372, 0.0), (0.390, 0.014), (0.372, 0.028)], SPLIT, seg=8,
               center=(0.0, ry, 0.0))
    for i in range(6):
        a = TAU * i / 6.0
        cx, cz = math.cos(a) * 0.378, math.sin(a) * 0.378
        t += octa((cx, ry + 0.055 + 0.012 * (i % 2), cz), 0.036, 0.080, SPLIT)
        t += octa((cx, ry + 0.055 + 0.012 * (i % 2), cz), 0.018, 0.036, ICE_L)

    # 两侧冰青旗
    for sx in (-1, 1):
        t += banner((sx * 0.30, py + 0.02, 0.0), 0.09, 0.26, 0.11, SPLIT_D, trim=SPLIT)

    # 水晶双叉弩（独立 Turret）
    pivot = (0.0, py + 0.11, 0.0)
    u = cyl((0.0, 0.0, 0.0), 0.095, 0.085, 0.05, shade(MARBLE, 1.05), seg=10)
    u += box((0.0, 0.070, -0.02), (0.13, 0.055, 0.16), shade(MARBLE, 0.94))
    u += octa((0.0, 0.145, 0.02), 0.062, 0.105, SPLIT)          # 中央晶核
    u += octa((0.0, 0.145, 0.02), 0.032, 0.055, ICE_L)
    for sx in (-1, 1):
        # 晶臂：向外上方张开的两截晶体
        u += xf(octa((0.0, 0.0, 0.0), 0.040, 0.185, SPLIT),
                t=(sx * 0.175, 0.185, 0.06), rz=sx * 1.20)
        u += xf(octa((0.0, 0.0, 0.0), 0.026, 0.085, ICE_L),
                t=(sx * 0.255, 0.235, 0.06), rz=sx * 1.35)
        u += box((sx * 0.085, 0.150, 0.12), (0.115, 0.007, 0.007), ICE_L)   # 弦
    # 短矢：青白晶杆 + 亮头
    u += cyl_z((0.0, 0.150, 0.06), 0.013, 0.011, 0.24, ICE_L, seg=6)
    u += xf(cone((0.0, 0.0, 0.0), 0.022, 0.07, SPLIT, seg=5),
            t=(0.0, 0.150, 0.29), rx=math.pi * 0.5)
    u = xf(u, t=pivot)
    return t, u, pivot


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

## 塔顶火龙的缩放（L1 → L3 逐渐长大）
FLAME_DRAGON_SCALE = (0.34, 0.39, 0.44)

## 龙脚相对火盆底面的高度（火盆顶在 y0 + 0.42）
FLAME_DRAGON_Y = 0.42


def build_flame(level):
    """#41-44：暗红石座 + 火盆 + 火龙。

    底座 / 石塔身 / 铁箍 / 紫晶簇 / 铁刺全部沿用原来的造型，只把火盆里那簇
    火焰锥换成一只完整的火龙（tools/gen_dragon_model.py 的 build()）。
    龙单独作为 Turret 节点返回：塔身不动，只有龙围着塔顶转向敌人喷火。
    """
    t = plinth(level, 0.30, col=BRICK)
    y0 = level * COURSE

    t += cyl((0.0, y0, 0.0), 0.265, 0.235, 0.26, shade(BRICK, 0.85), seg=12)
    # 火盆（外壁 + 炭火面 + 铁箍）
    t += lathe([(0.165, y0 + 0.26), (0.300, y0 + 0.320), (0.325, y0 + 0.420)],
               shade(BRICK, 0.74), seg=12)
    t += lathe([(0.280, y0 + 0.412), (0.255, y0 + 0.432)], EMBER, seg=12)
    t += cyl((0.0, y0 + 0.360, 0.0), 0.328, 0.328, 0.024, IRON, seg=12)

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

    # 龙脚边的一圈小火舌：让「龙从火盆里站起来」有个出处
    fy = y0 + 0.418
    for i in range(5):
        a = TAU * i / 5.0 + 0.3
        t += cone((math.cos(a) * 0.180, fy, math.sin(a) * 0.180),
                  0.055, 0.10 + 0.02 * level, EMBER, seg=5)

    # 火龙：整体缩放后踩在炭火面上，作为可转向的 Turret
    s = FLAME_DRAGON_SCALE[level - 1]
    pivot = (0.0, y0 + FLAME_DRAGON_Y, 0.0)
    drg = dragon_mod.build()
    drg = xf(drg, s=(s, s, s), t=pivot)
    return t, drg, pivot


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


POISON_GLOW = (0.42, 0.95, 0.25)
POISON_D = (0.16, 0.50, 0.14)
CLOTH = (0.88, 0.86, 0.80)
FUR_CAT = (0.86, 0.68, 0.44)


def build_poison(level):
    """炼金塔：石座 + 一锅绿汤 + 锅后一只猫耳炼金师。

    参考图的两个识别点都保留：**占了半个塔身的大铁锅**（绿色液面必须最亮），
    和**猫耳 + 米色袍子的小人**。举着瓶子的那条手臂单独做成 Turret，游戏里会跟着目标转。
    """
    # 底鼓直径压到 0.54：再宽一层，按身高缩放后整座塔会超出格子（其他塔约 2.2 世界单位宽）
    # 基座最多两层：模型会被归一化到固定身高，再往上堆石圈只会把锅挤成一只矮碗，
    # 等级越高越头重脚轻 —— 高度留给「更大的锅」。
    courses = min(level, 2)
    t = plinth(courses, 0.27, col=STONE)
    y0 = courses * COURSE + 0.045
    k = 1.0 + 0.07 * (level - 1)        # 满级锅放大 14%：等级语言靠「锅变大」

    # 垫锅的三块石头：锅不能直接「悬」在基座上
    for i in range(3):
        a = TAU * i / 3.0 + 0.6
        t += box((math.cos(a) * 0.19, y0 + 0.035, math.sin(a) * 0.19 + 0.09),
                 (0.13, 0.075, 0.13), STONE_D, ry=-a)

    up = []      # 锅 + 炼金师：整体按 k 围绕 y0 放大
    # 大铁锅：鼓肚 → 外翻的锅沿 → 绿色液面
    # 锅沿 profile 最后要**往回收口并下压**（0.262,0.312 → 0.238,0.312 → 0.236,0.288）：
    # lathe 会拿最后一点当圆心补一块整圆盖板，收在 0.262 就等于给锅扣了个锅盖，
    # 朝上的盖板被顶光一照还是一片惨白，整锅绿汤就消失（第一版就栽在这）。
    cy = y0 + 0.075
    cz = 0.09
    up += lathe([(0.158, 0.0), (0.253, 0.105), (0.266, 0.225), (0.233, 0.286)],
                shade(IRON, 0.86), seg=14, center=(0.0, cy, cz))
    up += lathe([(0.234, 0.272), (0.268, 0.292), (0.262, 0.312),
                 (0.238, 0.312), (0.236, 0.288)],
                shade(IRON, 1.35), seg=14, center=(0.0, cy, cz))
    # 液面塞在收口里侧、比锅沿顶面低一丝：这样看到的是「一锅汤」而不是「一个绿盖子」
    up += cyl((0.0, cy + 0.286, cz), 0.241, 0.241, 0.026, POISON_GLOW, seg=14)
    # 汤面上浮几块更暗的绿：远看就是一锅正在冒泡的汤
    for i in range(3 + level):
        a = TAU * i / float(3 + level) + 0.4
        rr = 0.030 + 0.020 * (i % 3)
        up += sph((math.cos(a) * (0.045 + 0.035 * (i % 4)), cy + 0.315,
                   cz + math.sin(a) * (0.040 + 0.032 * (i % 3))),
                  rr, POISON_D, seg=8, rings=5, squash=0.5)
    if level >= 2:
        # 锅身的铁箍：不封顶的空心圆管，只加一圈比锅面稍大的壳，等级一眼能看出来
        up += cyl((0.0, cy + 0.150, cz), 0.262, 0.260, 0.024,
                  shade(IRON, 1.18), seg=14, caps=False)
    if level >= 3:
        up += cyl((0.0, cy + 0.058, cz), 0.222, 0.220, 0.022,
                  shade(IRON, 1.18), seg=14, caps=False)

    # 炼金师：米色袍子 + 猫耳 + 小眼睛，站在锅后面。
    # 锅沿顶面在 cy+0.312，人**必须整体高过它**：只抬一点的话袍子全被锅吃掉，
    # 只剩一颗头浮在汤面上（第一版就是这样）。这里让袍子下摆藏进锅后、上身完整露出来。
    fz = -0.150
    up += taper((0.0, y0 + 0.385, fz), (0.275, 0.24), (0.195, 0.18), 0.34, CLOTH)
    up += box((0.0, y0 + 0.450, fz), (0.28, 0.035, 0.245), LEATHER)      # 腰带
    up += sph((0.0, y0 + 0.665, fz + 0.02), 0.146, FUR_CAT, seg=10, rings=6, squash=0.96)
    for sx in (-1, 1):
        up += xf(cone((0.0, 0.0, 0.0), 0.058, 0.115, FUR_CAT, seg=5),
                 t=(sx * 0.088, y0 + 0.778, fz + 0.02), rz=-sx * 0.28)
        up += box((sx * 0.064, y0 + 0.670, fz + 0.128), (0.040, 0.030, 0.028), DARK)
    up += box((0.0, y0 + 0.622, fz + 0.134), (0.052, 0.026, 0.028), shade(FUR_CAT, 0.82))
    # 挂在锅沿外沿的小瓶子（等级越高越多）。半径必须**大于锅沿** 0.268，
    # 挂在沿口上会被锅沿吃掉半截，远看就是锅边糊了几个绿疙瘩。
    for i in range(level - 1):
        a = 0.9 + i * 1.15
        up += sph((math.cos(a) * 0.303, cy + 0.245, cz + math.sin(a) * 0.303), 0.045,
                  POISON_GLOW, seg=8, rings=5, squash=1.2)
        up += cyl((math.cos(a) * 0.303, cy + 0.293, cz + math.sin(a) * 0.303),
                  0.014, 0.016, 0.035, POISON_GLOW, seg=6)

    if level >= 3:
        # 满级：汤面冒起几缕绿汽。环心往 +Z 挪一点，后侧那几缕就不会从炼金师袍子前面钻出来
        up += spikes(4, (0.0, cy + 0.345, cz + 0.035), 0.135, 0.115, 0.026,
                     shade(POISON_GLOW, 0.92), tilt=0.22, phase=0.9)

    # 举瓶子的手臂（Turret）：横向朝 +Z 伸出去，托着药瓶。
    # 枢轴要**低于下巴**：抬到脸的高度时，瓶子转到正前方就把猫脸糊住了。
    piv = (0.0, y0 + 0.455, fz + 0.02)
    u = []
    u += box((0.0, 0.0, 0.120), (0.078, 0.074, 0.27), FUR_CAT)
    u += sph((0.0, 0.004, 0.252), 0.058, FUR_CAT, seg=8, rings=5)
    u += sph((0.0, 0.048, 0.270), 0.063, POISON_GLOW, seg=8, rings=5, squash=1.15)
    u += cyl((0.0, 0.104, 0.270), 0.020, 0.025, 0.046, POISON_GLOW, seg=6)
    u += cyl((0.0, 0.136, 0.270), 0.027, 0.027, 0.023, WOOD_D, seg=6)
    # 手臂斜向**右前方**（ry）：正对着 +Z 端着瓶子时，瓶身正好压在猫脸下沿上
    u = xf(u, t=piv, ry=0.55)

    # 锅和人一起按 k 放大，炮塔枢轴也得跟着走，否则举手的位置和身体对不上
    t += xf(up, s=(k, k, k), pivot=(0.0, y0, 0.0))
    u = xf(u, s=(k, k, k), pivot=(0.0, y0, 0.0))
    piv = (0.0, y0 + (piv[1] - y0) * k, piv[2] * k)
    return t, u, piv


TOWERS = {
    "arrow": (build_arrow, "箭塔"),
    "cannon": (build_cannon, "炮塔"),
    "frost": (build_frost, "冰塔"),
    "sniper": (build_sniper, "狙击塔"),
    "tesla": (build_tesla, "电塔"),
    "flame": (build_flame, "火塔"),
    "bounce": (build_bounce, "弹射塔"),
    "poison": (build_poison, "毒瓶塔"),
}

MAX_LEVEL = 3


TOWERS = {
    "arrow": (build_arrow, "箭塔"),
    "cannon": (build_cannon, "炮塔"),
    "frost": (build_frost, "冰塔"),
    "sniper": (build_sniper, "狙击塔"),
    "tesla": (build_tesla, "电塔"),
    "flame": (build_flame, "火塔"),
    "bounce": (build_bounce, "弹射塔"),
    "poison": (build_poison, "毒瓶塔"),
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

    # 箭塔三条变异线的专属外观：文件名后缀 = 变异 id 的最后一段
    # （arrow_gale → gale / arrow_pierce → pierce / arrow_split → split），
    # Tower.gd 的 _custom_model_path() 会自动优先加载它们。
    for name, label, fn in (
        ("tower_arrow_l3_gale", "疾风弩", build_arrow_gale),
        ("tower_arrow_l3_pierce", "裂空箭", build_arrow_pierce),
        ("tower_arrow_l3_split", "穿云矢", build_arrow_split),
    ):
        body, turret, pivot = fn()
        save_glb(os.path.join(args.out, name + ".glb"), body, name,
                 turret=turret, turret_pivot=pivot)
        tris = body + turret
        total += len(tris)
        xs = [p[0] for a, b, c, _ in tris for p in (a, b, c)]
        ys = [p[1] for a, b, c, _ in tris for p in (a, b, c)]
        h = max(ys) - min(ys)
        w = max(xs) - min(xs)
        print("%-22s %-8s %3d %5d %5d %6.2f %6.2f %6.2f" % (
            name + ".glb", label, MAX_LEVEL, len(tris), 0, h / w, h, w))

    print("total tris = %d, out = %s" % (total, args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
