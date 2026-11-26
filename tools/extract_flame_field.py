"""从效果图里抽出「地面火焰」序列帧，去掉烘焙进 RGB 的棋盘格背景。

源图 91x466：8 段地上一摊摊小火的图（喷火方向的地块被点燃的样子），
背景同样是深色棋盘格（(30,30,46) / (20,20,20)，alpha 全 255），
所以和 extract_flame_jet.py 一样：用亮度算 alpha，再对平均背景色反预乘。
"""

from PIL import Image
import numpy as np
import os

SRC = r"C:\Users\ants\AppData\Local\CodeBuddyExtension\Data\373187ef-f258-4ae2-bc4c-8ce547b364f1\CodeBuddyIDE\373187ef-f258-4ae2-bc4c-8ce547b364f1\history\fbe5bcee90b2827fb601c6731aa2dd33\c25b2aa2c15842fbbb8947a50270c886\assets\image.08460f83f9.png"
OUT_DIR = r"d:\code\godot\game\merge_maze_td\textures"

ALPHA_LO = 42.0
ALPHA_HI = 100.0
BG = np.array([25.0, 25.0, 33.0], dtype=np.float32)

img = Image.open(SRC).convert("RGB")
a = np.asarray(img).astype(np.float32)
h, w, _ = a.shape

luma = 0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2]
alpha = np.clip((luma - ALPHA_LO) / (ALPHA_HI - ALPHA_LO), 0.0, 1.0)
fg = BG + (a - BG) / np.maximum(alpha, 1e-3)[..., None]
rgba = np.dstack([np.clip(fg, 0, 255), alpha * 255.0]).astype(np.uint8)

row_active = (alpha > 0.08).sum(axis=1) > 2
bands = []
start = None
for y in range(h):
    if row_active[y] and start is None:
        start = y
    elif not row_active[y] and start is not None:
        if y - start >= 6:
            bands.append((start, y - 1))
        start = None
if start is not None:
    bands.append((start, h - 1))

# 小碎片（<12 行）是同一帧甩上天的火星，并回上一帧
merged = []
for b in bands:
    if merged and b[1] - b[0] + 1 < 12:
        merged[-1] = (merged[-1][0], b[1])
    else:
        merged.append(b)
bands = merged

print("frames:", len(bands))
for b in bands:
    print("  band", b, "h=", b[1] - b[0] + 1)

if not bands:
    raise SystemExit("没找到帧")

# 统一画布：宽取原图宽，高取最高的一帧（各帧居中），这样循环播放时不会上下跳
pad = 2
canvas_h = max(b[1] - b[0] + 1 for b in bands) + pad * 2
for i, (y0, y1) in enumerate(bands):
    crop = rgba[max(0, y0 - pad):min(h, y1 + 1 + pad), :, :]
    out = np.zeros((canvas_h, w, 4), dtype=np.uint8)
    top = (canvas_h - crop.shape[0]) // 2
    out[top:top + crop.shape[0]] = crop
    Image.fromarray(out, "RGBA").save(os.path.join(OUT_DIR, "fx_flame_field_%d.png" % i))

print("canvas:", w, "x", canvas_h)
