"""把「雪人王」原画抠成透明 PNG（像素风，保持原生分辨率，游戏里用 NEAREST 采样）。

原画是一张带 UI 边框的截图：上面一条蓝色标题栏，下面一个带浅边框的面板，
面板底色是深蓝灰 (37, 42, 54)，外围更暗 (28, 31, 40)。雪人自己的描边比面板底色**更暗**
（12, 23, 30），所以不能用「亮度阈值」抠图 —— 会把描边一起吃掉。
这里改成「按颜色接近背景 + 从边框泛洪」：只有贴着面板底的连通背景才会被删，描边保留。

用法：python tools/gen_snowking_sprite.py
输出：textures/enemy_snowking.png（RGBA，原生像素尺寸，四周留 2px 透明边）
"""
import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "art", "snowking_src.png")
DST = os.path.join(ROOT, "textures", "enemy_snowking.png")

PANEL_BG = (37, 42, 54)     # 面板底色
OUTER_BG = (28, 31, 40)     # 面板外的底色
TOL = 10                    # 单通道容差：面板底有轻微噪点，但描边(12,23,30)离这里足够远
PAD = 2


def near(px, ref, tol=TOL) -> bool:
    return (abs(px[0] - ref[0]) <= tol
            and abs(px[1] - ref[1]) <= tol
            and abs(px[2] - ref[2]) <= tol)


def find_panel(img: Image.Image):
    """返回面板内区（纯背景色）的包围盒，用来裁掉标题栏与边框。"""
    w, h = img.size
    px = img.load()
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if near(px[x, y], PANEL_BG):
                if x < x0:
                    x0 = x
                if y < y0:
                    y0 = y
                if x > x1:
                    x1 = x
                if y > y1:
                    y1 = y
    return x0, y0, x1 + 1, y1 + 1


def main() -> None:
    img = Image.open(SRC).convert("RGBA")
    box = find_panel(img)
    print("panel bg bbox =", box)
    # 往里收 4px，确保裁掉浅色边框本身
    inset = 4
    crop = img.crop((box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset))
    w, h = crop.size
    px = crop.load()
    print("crop = %dx%d" % (w, h))

    # 从四边泛洪，只吃「接近背景色」的像素
    bg = bytearray(w * h)
    q = deque()

    def is_bg(x: int, y: int) -> bool:
        p = px[x, y]
        return near(p, PANEL_BG) or near(p, OUTER_BG)

    for x in range(w):
        for y in (0, h - 1):
            if is_bg(x, y) and not bg[y * w + x]:
                bg[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(x, y) and not bg[y * w + x]:
                bg[y * w + x] = 1
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not bg[ny * w + nx] and is_bg(nx, ny):
                bg[ny * w + nx] = 1
                q.append((nx, ny))

    # 只保留最大前景连通块（面板里可能有别的残留像素）
    seen = bytearray(w * h)
    best = []
    for i in range(w * h):
        if bg[i] or seen[i]:
            continue
        comp = []
        qq = deque([i])
        seen[i] = 1
        while qq:
            cur = qq.popleft()
            comp.append(cur)
            x, y = cur % w, cur // w
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    ni = ny * w + nx
                    if not bg[ni] and not seen[ni]:
                        seen[ni] = 1
                        qq.append(ni)
        if len(comp) > len(best):
            best = comp
    keep = set(best)
    print("background=%d keep=%d" % (sum(bg), len(keep)))

    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    src = crop.load()
    dst = out.load()
    for i in keep:
        dst[i % w, i // w] = src[i % w, i // w]

    bb = out.getbbox()
    if bb is None:
        raise SystemExit("抠图失败：没有剩下任何前景像素")
    x0, y0, x1, y1 = bb
    body = out.crop((max(0, x0 - PAD), max(0, y0 - PAD), min(w, x1 + PAD), min(h, y1 + PAD)))
    print("body = %dx%d  (bbox %s)" % (body.size[0], body.size[1], bb))

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    body.save(DST)
    print("wrote %s" % os.path.relpath(DST, ROOT))


if __name__ == "__main__":
    main()
