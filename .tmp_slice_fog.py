"""临时脚本：把冰雾参考图抠成带透明通道的正方形贴图（雾团居中）。"""
from PIL import Image

SRC = r"C:\Users\ants\AppData\Local\CodeBuddyExtension\Data\373187ef-f258-4ae2-bc4c-8ce547b364f1\CodeBuddyIDE\373187ef-f258-4ae2-bc4c-8ce547b364f1\history\fbe5bcee90b2827fb601c6731aa2dd33\c25b2aa2c15842fbbb8947a50270c886\assets\image.b93047dad4.png"
OUT = r"d:\code\godot\game\merge_maze_td\textures\fx_frost_fog.png"
BG = 25.0
SPAN = 200.0
SIZE = 256

im = Image.open(SRC).convert("RGB")
w, h = im.size
px = im.load()

keyed = Image.new("RGBA", (w, h), (0, 0, 0, 0))
dst = keyed.load()
for y in range(h):
    for x in range(w):
        r, g, b = px[x, y]
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        a = (lum - BG) / SPAN
        a = 0.0 if a < 0.0 else (1.0 if a > 1.0 else a)
        if a <= 0.02:
            continue
        inv = 1.0 / a
        dst[x, y] = (
            max(0, min(255, int(round((r - BG * (1.0 - a)) * inv)))),
            max(0, min(255, int(round((g - BG * (1.0 - a)) * inv)))),
            max(0, min(255, int(round((b - BG * (1.0 - a)) * inv)))),
            max(0, min(255, int(round(a * 255)))),
        )

# 按 alpha 加权求重心，让雾团在正方形里居中（后面要当径向贴图用）
sum_a = 0.0
cx = 0.0
cy = 0.0
for y in range(h):
    for x in range(w):
        a = dst[x, y][3]
        if a:
            sum_a += a
            cx += x * a
            cy += y * a
cx /= max(sum_a, 1.0)
cy /= max(sum_a, 1.0)

side = int(max(w, h) * 1.10)
box = (
    int(round(cx - side * 0.5)),
    int(round(cy - side * 0.5)),
    int(round(cx + side * 0.5)),
    int(round(cy + side * 0.5)),
)
out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
out.paste(keyed.crop((0, 0, w, h)), (-box[0], -box[1]))
out = out.resize((SIZE, SIZE), Image.LANCZOS)
out.save(OUT)

px2 = out.load()
edge = [px2[i, SIZE // 2][3] for i in (0, 1, SIZE - 2, SIZE - 1)]
print("wrote", OUT, out.size, "centroid", round(cx, 1), round(cy, 1), "edge alpha", edge)
