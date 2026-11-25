"""把「霜崽」原画抠成透明 PNG，供 Enemy 当 billboard 精灵用。

原画是一张带深色棋盘格背景的小图（棋盘格是烘焙进像素里的，不是真透明），
所以这里按「从四边泛洪 + 只吃暗色像素」把背景抠掉：
棋盘格只有两种暗蓝 / 纯黑，而小怪本体是浅薄荷绿 + 黄眼睛，亮度差得很开，
阈值取 90 就足够干净，不会啃到身体边缘的深色描边（实测最暗的描边也 > 100）。

抠完只保留**面积最大的连通块**：原画顶上还露着另一个素材的半截，
不筛掉的话它会跟着小怪一起被导出。

用法：python tools/gen_frostling_sprite.py
输出：textures/enemy_frostling.png（正方形画布、RGBA、2 的幂边长 128）
"""
import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "art", "frostling_src.png")
DST = os.path.join(ROOT, "textures", "enemy_frostling.png")

DARK = 90          # 判定为背景的亮度上限（三通道最大值）
PAD = 2            # 裁剪后留的边距（像素）
OUT = 128          # 输出画布边长


def key_background(img: Image.Image) -> Image.Image:
    w, h = img.size
    px = img.load()
    bg = bytearray(w * h)

    def is_dark(x: int, y: int) -> bool:
        r, g, b, _ = px[x, y]
        return max(r, g, b) < DARK

    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_dark(x, y) and not bg[y * w + x]:
                bg[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_dark(x, y) and not bg[y * w + x]:
                bg[y * w + x] = 1
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not bg[ny * w + nx] and is_dark(nx, ny):
                bg[ny * w + nx] = 1
                q.append((nx, ny))
    return bg


def largest_component(w: int, h: int, bg: bytearray) -> list:
    """返回面积最大的前景连通块的像素列表（4 邻接）。"""
    seen = bytearray(w * h)
    best = []
    for i in range(w * h):
        if bg[i] or seen[i]:
            continue
        comp = []
        q = deque([i])
        seen[i] = 1
        while q:
            cur = q.popleft()
            comp.append(cur)
            x, y = cur % w, cur // w
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    ni = ny * w + nx
                    if not bg[ni] and not seen[ni]:
                        seen[ni] = 1
                        q.append(ni)
        if len(comp) > len(best):
            best = comp
    return best


def main() -> None:
    img = Image.open(SRC).convert("RGBA")
    w, h = img.size
    bg = key_background(img)
    keep = set(largest_component(w, h, bg))
    print("source=%dx%d  background=%d  keep=%d" % (w, h, sum(bg), len(keep)))

    # 只保留主体，其余（含顶上露出的半截素材）全部透明
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    src = img.load()
    dst = out.load()
    for i in keep:
        dst[i % w, i // w] = src[i % w, i // w]

    box = out.getbbox()
    if box is None:
        raise SystemExit("抠图失败：没有剩下任何前景像素")
    x0, y0, x1, y1 = box
    x0, y0 = max(0, x0 - PAD), max(0, y0 - PAD)
    x1, y1 = min(w, x1 + PAD), min(h, y1 + PAD)
    body = out.crop((x0, y0, x1, y1))
    print("bbox=%s  body=%dx%d" % (box, body.size[0], body.size[1]))

    # 摆进正方形画布：等比缩放，底部留 2px（游戏里模型底边贴地）
    k = min((OUT - 4) / body.size[0], (OUT - 4) / body.size[1])
    size = (max(1, int(round(body.size[0] * k))), max(1, int(round(body.size[1] * k))))
    # 预乘 alpha 再缩放：否则透明区域（RGB 是白的）会把白色混进边缘，
    # 游戏里小怪周围会出现一圈白雾
    body = body.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
    canvas = Image.new("RGBA", (OUT, OUT), (255, 255, 255, 0))
    canvas.paste(body, ((OUT - size[0]) // 2, OUT - 2 - size[1]), body)

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    canvas.save(DST)
    print("wrote %s (%dx%d)" % (os.path.relpath(DST, ROOT), OUT, OUT))


if __name__ == "__main__":
    main()
