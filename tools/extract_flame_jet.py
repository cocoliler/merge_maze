"""从效果图里抽出 12 帧火焰喷流，去掉烘焙进去的棋盘格背景，输出带透明通道的序列帧。

源图 180x885：每帧都是「喷嘴在左、火焰向右展开」的一股火舌，背景是深色棋盘格
（(30,30,46) / (20,20,20)）——注意它是**烘焙进 RGB 的**，alpha 全为 255，
所以不能直接拿来当透明贴图，必须自己算 alpha 再把背景色反预乘掉。

背景是冷色且很暗（亮度约 20~32），火焰是暖色高亮（亮度 > 60）。
用亮度做 alpha（42 以下全透明，100 以上全不透明），再用平均背景色反预乘得到火焰原色。
"""

from PIL import Image
import numpy as np
import os

SRC = r"C:\Users\ants\AppData\Local\CodeBuddyExtension\Data\373187ef-f258-4ae2-bc4c-8ce547b364f1\CodeBuddyIDE\373187ef-f258-4ae2-bc4c-8ce547b364f1\history\fbe5bcee90b2827fb601c6731aa2dd33\c25b2aa2c15842fbbb8947a50270c886\assets\image.bcc05e3eb8.png"
OUT_DIR = r"d:\code\godot\game\merge_maze_td\textures"

ALPHA_LO = 42.0     # 亮度低于它就当背景（棋盘格 20 / 32 都在这条线以下）
ALPHA_HI = 100.0    # 亮度高于它就是实心火焰
BG = np.array([25.0, 25.0, 33.0], dtype=np.float32)   # 两种棋盘色的平均，用来反预乘

img = Image.open(SRC).convert("RGB")
a = np.asarray(img).astype(np.float32)

luma = 0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2]
alpha = np.clip((luma - ALPHA_LO) / (ALPHA_HI - ALPHA_LO), 0.0, 1.0)

# 反预乘：observed = fg*a + bg*(1-a)  ->  fg = bg + (observed-bg)/a
fg = BG + (a - BG) / np.maximum(alpha, 1e-3)[..., None]
fg = np.clip(fg, 0, 255)

rgba = np.dstack([fg, alpha * 255.0]).astype(np.uint8)

# 按行找每一帧的垂直范围
row_active = (alpha > 0.10).sum(axis=1) > 2
bands = []
start = None
for y in range(a.shape[0]):
    if row_active[y] and start is None:
        start = y
    elif not row_active[y] and start is not None:
        if y - start >= 6:
            bands.append((start, y - 1))
        start = None
if start is not None:
    bands.append((start, a.shape[0] - 1))

# 小于 20 行的小片段是同一帧甩出去的火星，并回上一帧（否则会被当成一帧「只剩火星」的残图）
merged = []
for b in bands:
    if merged and b[1] - b[0] + 1 < 20:
        merged[-1] = (merged[-1][0], b[1])
    else:
        merged.append(b)
bands = merged

print("frames:", len(bands))
for b in bands:
    print("  band", b, "h=", b[1] - b[0] + 1)

pad = 3
heights = [b[1] - b[0] + 1 + pad * 2 for b in bands]
canvas_h = max(heights) if heights else 1

# 源图左右各有 20 多像素的空边：裁成统一宽度，让「喷嘴」贴着贴图左边缘，
# 这样游戏里把贴图左端对齐枪口时火焰就正好从塔口喷出来。
X0, X1 = 18, 178

for i, (y0, y1) in enumerate(bands):
    crop = rgba[max(0, y0 - pad):min(a.shape[0], y1 + 1 + pad), X0:X1, :]
    ch = crop.shape[0]
    w = crop.shape[1]
    out = np.zeros((canvas_h, w, 4), dtype=np.uint8)
    top = (canvas_h - ch) // 2
    out[top:top + ch] = crop
    Image.fromarray(out, "RGBA").save(os.path.join(OUT_DIR, "fx_flame_jet_%d.png" % i))

print("canvas:", w, "x", canvas_h)
