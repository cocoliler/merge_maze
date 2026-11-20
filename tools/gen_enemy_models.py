#!/usr/bin/env python3
"""参照 Kingdom Rush 2D 立绘的造型语言，程序化生成低多边形敌人 GLB。

为什么这么做：
    素材本身是 2D 图集（TexturePacker 紧密排布 + 元数据字节码），直接当 3D 用不现实；
    但它的「造型语言」很明确 —— 粗壮比例、大武器、护肩、破布、土色系配色。
    这里用纯几何图元重建这套语言，产出的 GLB 可以直接被
    `Enemy._build_custom_body()` 接管（它会按目标身高自动缩放、贴地、居中）。

工程约定见 tools/lowpoly_kit.py（图元、变换、glTF 写出都在那里）。

用法：
    python tools/gen_enemy_models.py
"""

from __future__ import annotations

import argparse
import math
import os

from lowpoly_kit import *  # noqa: F401,F403  (图元 + 色板 + save_glb)

# ---------------------------------------------------------------- 造型：兽人底盘
def orc(col, w=1.0, tall=1.0, armor=0.0, tusks=True, pad=True):
    """兽人躯干。参考素材里最典型的一类单位：粗腿、窄腰、宽胸、大护肩。

    w    横向肥瘦（重甲 1.25 / 首领 1.35）
    tall 纵向拉伸
    armor 0~1，越大叠的甲片越多
    """
    t = []
    skin = col
    skin_d = shade(col, 0.74)
    stone = mix(STEEL_D, col, 0.25) if armor > 0.5 else LEATHER

    # 腿 + 脚（腿要占到全高约 1/3，否则整个人像墩子）
    for sx in (-1, 1):
        t += box((sx * 0.135 * w, 0.045 * tall, 0.035),
                 (0.19 * w, 0.09 * tall, 0.27 * w), LEATHER_D)
        t += taper((sx * 0.135 * w, 0.20 * tall, 0.0),
                   (0.17 * w, 0.17 * w), (0.145 * w, 0.145 * w), 0.22 * tall, skin_d)
        if armor > 0.3:
            t += box((sx * 0.135 * w, 0.19 * tall, 0.075 * w),
                     (0.20 * w, 0.19 * tall, 0.08 * w), stone)
    # 腰 / 腹（收窄，衬出宽胸）
    t += taper((0.0, 0.41 * tall, 0.0), (0.30 * w, 0.23 * w),
               (0.36 * w, 0.26 * w), 0.13 * tall, LEATHER)
    # 胸（上宽下窄的棱台，比纯方块更有体块感）
    t += taper((0.0, 0.545 * tall, 0.0), (0.36 * w, 0.26 * w),
               (0.42 * w, 0.28 * w), 0.16 * tall, skin)
    # 胸甲 / 皮带
    if armor > 0.05:
        t += box((0.0, 0.55 * tall, 0.125 * w),
                 (0.30 * w, 0.20 * tall, 0.05 * w), stone)
        t += box((0.0, 0.60 * tall, 0.15 * w),
                 (0.24 * w, 0.04 * tall, 0.03 * w), GOLD if armor < 0.4 else STEEL)
    else:
        t += box((0.0, 0.52 * tall, 0.12 * w),
                 (0.09 * w, 0.24 * tall, 0.04 * w), LEATHER_L)
    # 护肩（缩小并贴回躯干，否则整只怪变成"两个大方块"）
    if pad:
        for sx in (-1, 1):
            t += taper((sx * 0.235 * w, 0.625 * tall, 0.0),
                       (0.22 * w, 0.26 * w), (0.16 * w, 0.20 * w),
                       0.11 * tall, stone if armor > 0.2 else LEATHER_L)
    # 手臂
    for sx in (-1, 1):
        t += taper((sx * 0.255 * w, 0.50 * tall, 0.02),
                   (0.12 * w, 0.12 * w), (0.105 * w, 0.105 * w), 0.19 * tall, skin_d)
        t += box((sx * 0.255 * w, 0.375 * tall, 0.04),
                 (0.115 * w, 0.09 * tall, 0.14 * w), LEATHER)
    # 颈 / 头（头要够大，卡通比例就靠这个撑起来）
    t += box((0.0, 0.655 * tall, 0.0), (0.13 * w, 0.05, 0.13 * w), skin_d)
    t += taper((0.0, 0.795 * tall, 0.015), (0.25 * w, 0.24 * w),
               (0.27 * w, 0.26 * w), 0.235 * tall, skin)
    # 下颚 + 獠牙
    t += box((0.0, 0.705 * tall, 0.10 * w),
             (0.21 * w, 0.075, 0.10 * w), shade(skin, 0.88))
    if tusks:
        for sx in (-1, 1):
            t += cone((sx * 0.08 * w, 0.705 * tall, 0.135 * w), 0.030, 0.095, BONE, seg=5)
    # 眉骨 + 眼：有眉骨才像一张脸，否则只是一块砖
    t += box((0.0, 0.855 * tall, 0.125 * w), (0.24 * w, 0.05, 0.05), shade(skin, 0.55))
    for sx in (-1, 1):
        t += box((sx * 0.075 * w, 0.815 * tall, 0.135 * w),
                 (0.06 * w, 0.045, 0.03), DARK)
        t += box((sx * 0.075 * w, 0.815 * tall, 0.147 * w),
                 (0.033 * w, 0.028, 0.02), GLOW)
    # 头巾 / 头盔
    if armor > 0.45:
        t += taper((0.0, 0.905 * tall, 0.0), (0.27 * w, 0.26 * w),
                   (0.21 * w, 0.20 * w), 0.10 * tall, stone)
        t += box((0.0, 0.845 * tall, 0.13 * w),
                 (0.235 * w, 0.03, 0.03), DARK)
    else:
        t += box((0.0, 0.905 * tall, 0.0), (0.27 * w, 0.055, 0.26 * w), LEATHER)
    return t


def club(col=WOOD, x=0.34, y=0.30, z=0.10, skew=0.0):
    """粗木棒：素材里最常见的兽人武器，棒头比棒身明显粗一圈。"""
    t = []
    t += xf(cyl((0.0, 0.0, 0.0), 0.036, 0.045, 0.52, WOOD_D, seg=6), t=(x, y, z), rz=skew)
    t += taper((x + math.sin(skew) * 0.52, y + math.cos(skew) * 0.52, z),
               (0.14, 0.14), (0.11, 0.11), 0.20, shade(col, 0.85))
    for dz in (-0.07, 0.07):
        t += box((x + math.sin(skew) * 0.60, y + math.cos(skew) * 0.60, z + dz),
                 (0.03, 0.14, 0.03), STEEL_D)
    return t


# ---------------------------------------------------------------- 各单位
def build_grunt(col):
    """小兵（蚀民）：最标准的兽人步卒，短棒 + 皮甲，剪影一眼能认出。"""
    t = orc(col, w=1.0, tall=1.0)
    t += club(x=0.33, y=0.26, z=0.13, skew=0.12)
    return t


def build_runner(col):
    """疾行者（裂足）：瘦长、前倾、长腿长臂、背刺，强调"在跑"。"""
    t = []
    skin = col
    skin_d = shade(col, 0.74)
    for sx in (-1, 1):
        # 大腿 + 小腿（前倾折线，像在蹬地）
        t += xf(taper((0.0, 0.0, 0.0), (0.13, 0.13), (0.11, 0.11), 0.22, skin_d),
               t=(sx * 0.10, 0.30, -0.02), rx=-0.55)
        t += xf(taper((0.0, 0.0, 0.0), (0.10, 0.10), (0.085, 0.085), 0.24, skin),
               t=(sx * 0.10, 0.13, 0.09), rx=0.45)
        t += box((sx * 0.10, 0.045, 0.19), (0.12, 0.09, 0.24), LEATHER_D)
    # 躯干：明显前倾
    t += xf(taper((0.0, 0.0, 0.0), (0.26, 0.20), (0.30, 0.22), 0.26, skin),
           t=(0.0, 0.42, 0.0), rx=-0.28)
    t += xf(taper((0.0, 0.0, 0.0), (0.30, 0.22), (0.22, 0.18), 0.16, skin_d),
           t=(0.0, 0.58, 0.07), rx=-0.28)
    # 长臂（前后摆动）
    for sx, sw in ((-1, 1.0), (1, -1.0)):
        t += xf(taper((0.0, 0.0, 0.0), (0.095, 0.095), (0.08, 0.08), 0.30, skin_d),
               t=(sx * 0.19, 0.60, 0.02), rx=sw * 0.75)
        t += box((sx * 0.19, 0.34, 0.02 + sw * 0.24), (0.10, 0.09, 0.13), LEATHER)
    # 头（小、前伸）
    t += box((0.0, 0.72, 0.16), (0.20, 0.17, 0.21), skin)
    t += box((0.0, 0.695, 0.275), (0.13, 0.06, 0.06), shade(skin, 0.85))
    for sx in (-1, 1):
        t += box((sx * 0.055, 0.745, 0.265), (0.04, 0.035, 0.02), GLOW)
    # 背刺
    for i, (yy, zz, hh) in enumerate(((0.66, -0.10, 0.16), (0.55, -0.13, 0.13),
                                      (0.45, -0.15, 0.10))):
        t += xf(cone((0.0, 0.0, 0.0), 0.035, hh, BONE, seg=5),
               t=(0.0, yy, zz), rx=-1.0)
    # 颈后飘带
    t += xf(box((0.0, 0.0, 0.0), (0.10, 0.28, 0.02), shade(col, 0.55)),
           t=(0.0, 0.56, -0.20), rx=1.15)
    return t


def build_tank(col, armor=0.85):
    """重甲（石膛）：宽体、厚甲、小头，盾牌一样的剪影。"""
    w = 1.12
    t = orc(col, w=w, tall=1.02, armor=armor, tusks=False)
    # 额外甲片 / 铆钉
    for sx in (-1, 1):
        t += box((sx * 0.17 * w, 0.50, 0.145), (0.18, 0.15, 0.05), mix(STEEL, col, 0.35))
    t += box((0.0, 0.44, 0.15), (0.46, 0.09, 0.05), STEEL_D)
    t += box((0.0, 0.78, 0.13), (0.18, 0.045, 0.04), GOLD)
    # 巨拳
    for sx in (-1, 1):
        t += box((sx * 0.325, 0.35, 0.06), (0.17, 0.16, 0.18), mix(STEEL_D, col, 0.3))
    return t


def build_shield(col):
    """壳卫（护盾怪）：一只手举着厚圆盾挡住正面，盾面比身体更抢眼。"""
    t = orc(col, w=0.92, tall=0.98, armor=0.5, tusks=True, pad=False)
    cx = -0.30
    # 盾：主盘 + 外圈 + 中心凸台 + 三颗铆钉
    t += cyl_z((cx, 0.46, 0.20), 0.32, 0.32, 0.055, shade(col, 0.55), seg=12)
    t += cyl_z((cx, 0.46, 0.185), 0.36, 0.36, 0.03, STEEL, seg=12)
    t += cyl_z((cx, 0.46, 0.25), 0.09, 0.09, 0.05, GOLD, seg=8)
    for i in range(3):
        a = TAU * i / 3.0 + 0.4
        t += box((cx + math.cos(a) * 0.22, 0.46 + math.sin(a) * 0.22, 0.255),
                 (0.05, 0.05, 0.03), STEEL_D)
    # 持盾手臂
    t += box((-0.30, 0.44, 0.12), (0.14, 0.14, 0.20), shade(col, 0.8))
    return t


def build_healer(col):
    """烛者（治疗怪）：长袍 + 兜帽 + 提灯法杖，底部收成锥形，没有腿。"""
    t = []
    robe = shade(col, 0.72)
    robe_d = shade(col, 0.5)
    # 袍身（分段锥，下摆更宽）
    t += taper((0.0, 0.14, 0.0), (0.46, 0.42), (0.34, 0.32), 0.26, robe_d)
    t += taper((0.0, 0.36, 0.0), (0.34, 0.32), (0.26, 0.25), 0.22, robe)
    t += taper((0.0, 0.55, 0.0), (0.26, 0.25), (0.22, 0.21), 0.18, robe)
    # 腰带
    t += box((0.0, 0.44, 0.0), (0.30, 0.05, 0.28), GOLD)
    # 兜帽（尖顶锥，帽檐压出阴影）
    t += cyl((0.0, 0.62, 0.0), 0.20, 0.07, 0.30, robe, seg=8)
    t += cone((0.0, 0.90, 0.0), 0.075, 0.14, robe_d, seg=7)
    t += box((0.0, 0.70, 0.10), (0.20, 0.13, 0.06), DARK)
    for sxx in (-1, 1):
        t += box((sxx * 0.055, 0.705, 0.125), (0.035, 0.03, 0.02), GLOW)
    # 袖子
    for sxx in (-1, 1):
        t += xf(taper((0.0, 0.0, 0.0), (0.14, 0.14), (0.11, 0.11), 0.18, robe),
               t=(sxx * 0.19, 0.52, 0.04), rx=-0.35)
        t += box((sxx * 0.22, 0.40, 0.10), (0.10, 0.09, 0.11), shade(col, 0.9))
    # 法杖 + 提灯
    t += cyl((-0.28, 0.02, 0.10), 0.026, 0.022, 1.02, WOOD, seg=6)
    t += sph((-0.28, 1.06, 0.10), 0.085, GLOW, seg=8, rings=5)
    t += cone((-0.28, 1.10, 0.10), 0.11, 0.09, GOLD, seg=6)
    return t


def build_splitter(col):
    """孢群（分裂怪）：一团会走的孢子，身上鼓着小孢囊，暗示"死亡分裂"。"""
    t = []
    body = mix(col, (0.55, 0.78, 0.42), 0.45)
    body_d = shade(body, 0.72)
    t += sph((0.0, 0.42, 0.0), 0.31, body, seg=11, rings=7, squash=0.92)
    # 体型压扁的一圈裙边
    t += xf(sph((0.0, 0.20, 0.0), 0.30, body_d, seg=11, rings=5, squash=0.5),
           s=(1.0, 1.0, 1.0))
    # 孢囊
    for a, yy, rr in ((0.5, 0.60, 0.12), (2.4, 0.50, 0.10), (4.2, 0.38, 0.13),
                      (5.6, 0.66, 0.09)):
        px = math.cos(a) * 0.26
        pz = math.sin(a) * 0.26
        t += sph((px, yy, pz), rr, shade(body, 1.18), seg=8, rings=5)
    # 短腿
    for sx in (-1, 1):
        for sz in (-1, 1):
            t += box((sx * 0.15, 0.055, sz * 0.15), (0.10, 0.11, 0.10), body_d)
    # 裂口 + 眼睛
    t += box((0.0, 0.36, 0.285), (0.20, 0.055, 0.03), DARK)
    for sx in (-1, 1):
        t += box((sx * 0.10, 0.53, 0.27), (0.055, 0.055, 0.03), GLOW)
    # 顶部尖刺
    for a in (0.9, 2.2, 4.4):
        t += xf(cone((0.0, 0.0, 0.0), 0.04, 0.14, BONE, seg=5),
               t=(math.cos(a) * 0.14, 0.66, math.sin(a) * 0.14), rx=0.0,
               rz=-math.cos(a) * 0.5, ry=0.0)
    return t


def build_miniboss(col):
    """潮主（小首领）：比小兵大一圈，双角 + 单手斧 + 破披风，作为强度节点。"""
    t = orc(col, w=1.10, tall=1.14, armor=0.7, tusks=True)
    # 双角
    for sx in (-1, 1):
        t += xf(cone((0.0, 0.0, 0.0), 0.07, 0.26, BONE, seg=6),
               t=(sx * 0.13, 0.93, 0.02), rz=sx * 0.55, rx=-0.15)
    # 披风
    t += xf(box((0.0, 0.0, 0.0), (0.48, 0.60, 0.03), shade(col, 0.45)),
           t=(0.0, 0.52, -0.17), rx=0.12)
    t += xf(box((0.0, 0.0, 0.0), (0.34, 0.20, 0.03), shade(col, 0.38)),
           t=(0.0, 0.20, -0.24), rx=0.35)
    # 斧
    ax, ay, az = 0.36, 0.24, 0.13
    t += cyl((ax, ay, az), 0.034, 0.028, 0.60, WOOD, seg=6)
    t += taper((ax, ay + 0.50, az), (0.28, 0.06), (0.14, 0.05), 0.24, STEEL)
    return t


def build_boss(col):
    """终焉之影（大首领）：夸张的肩甲尖刺 + 巨角 + 胸核，剪影要能压住全场。"""
    t = orc(col, w=1.18, tall=1.22, armor=0.95, tusks=True)
    # 巨角（两段折线，越往外越细）
    for sx in (-1, 1):
        t += xf(cone((0.0, 0.0, 0.0), 0.095, 0.30, BONE, seg=6),
               t=(sx * 0.155, 1.00, 0.02), rz=sx * 0.35, rx=-0.10)
        t += xf(cone((0.0, 0.0, 0.0), 0.055, 0.22, BONE, seg=6),
               t=(sx * 0.315, 1.13, 0.02), rz=sx * 1.05, rx=-0.10)
    # 肩甲尖刺
    for sx in (-1, 1):
        for k in range(3):
            t += xf(cone((0.0, 0.0, 0.0), 0.05, 0.18 - k * 0.03, STEEL, seg=5),
                   t=(sx * (0.29 + k * 0.04), 0.72, -0.05 + k * 0.12), rz=sx * 0.5)
    # 胸核
    t += sph((0.0, 0.60, 0.165), 0.09, GLOW, seg=8, rings=5)
    t += cyl_z((0.0, 0.60, 0.13), 0.13, 0.13, 0.04, STEEL_D, seg=10)
    # 披风（两段，稍微展开）
    t += xf(box((0.0, 0.0, 0.0), (0.58, 0.66, 0.03), shade(col, 0.40)),
           t=(0.0, 0.56, -0.20), rx=0.10)
    t += xf(box((0.0, 0.0, 0.0), (0.42, 0.22, 0.03), shade(col, 0.32)),
           t=(0.0, 0.20, -0.28), rx=0.34)
    # 巨拳
    for sx in (-1, 1):
        t += box((sx * 0.40, 0.32, 0.07), (0.21, 0.20, 0.22), mix(STEEL_D, col, 0.3))
        t += box((sx * 0.40, 0.43, 0.07), (0.23, 0.06, 0.24), GOLD)
    return t


BUILDERS = {
    # 文件名后缀 → (构造函数, 说明)
    "grunt": (build_grunt, "小兵 · 蚀民"),
    "runner": (build_runner, "疾行者 · 裂足"),
    "tank": (build_tank, "重甲 · 石膛"),
    "shield": (build_shield, "护盾怪 · 壳卫"),
    "healer": (build_healer, "治疗怪 · 烛者"),
    "splitter": (build_splitter, "分裂怪 · 孢群"),
    "boss": (build_boss, "大首领 · 终焉之影"),
    "miniboss": (build_miniboss, "小首领 · 潮主"),
}

# 与 data/EnemyData.gd 的 DATA[kind]["color"] 保持一致，保住"颜色=类型"的可读性
COLORS = {
    "grunt": (0.88, 0.38, 0.42),
    "runner": (0.95, 0.80, 0.35),
    "tank": (0.55, 0.45, 0.85),
    "shield": (0.35, 0.75, 0.90),
    "healer": (0.40, 0.90, 0.55),
    "splitter": (0.95, 0.60, 0.25),
    "boss": (0.95, 0.20, 0.55),
    "miniboss": (0.96, 0.50, 0.20),
}


def main() -> int:
    ap = argparse.ArgumentParser()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--out", default=os.path.join(root, "models", "enemies"))
    args = ap.parse_args()

    total = 0
    print("%-22s %-16s %6s %5s %s" % ("file", "unit", "tris", "mats", "height"))
    for suffix, (fn, label) in BUILDERS.items():
        tris = fn(COLORS[suffix])
        name = "enemy_%s" % suffix
        path = os.path.join(args.out, name + ".glb")
        n_tris, n_mat = save_glb(path, tris, name)
        total += n_tris
        ys = [p[1] for a, b, c, _ in tris for p in (a, b, c)]
        zs = [p[2] for a, b, c, _ in tris for p in (a, b, c)]
        xs = [p[0] for a, b, c, _ in tris for p in (a, b, c)]
        print("%-22s %-16s %6d %5d  y0=%.2f h=%.2f  x=[%.2f,%.2f] z=[%.2f,%.2f]" % (
            name + ".glb", label, n_tris, n_mat,
            min(ys), max(ys) - min(ys), min(xs), max(xs), min(zs), max(zs)))
    print("total tris = %d, out = %s" % (total, args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
