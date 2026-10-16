#!/usr/bin/env python
"""アプリアイコン(1024x1024)を生成する。

アイコンを変えるときは、このスクリプトを編集して再実行し、できたPNGをコミットする。
CIでは生成せずPNGをコミットしておく。CIにPython/Pillowの依存を足さないため。

使い方: pip install pillow && python scripts/make-app-icon.py
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024  # 出力サイズ。座標はこの基準で書く。
SCALE = 4  # 4倍で描いて縮小し、アンチエイリアスにする。

BG_TOP = (0x16, 0x34, 0x6F)
BG_BOTTOM = (0x0A, 0x1A, 0x3F)
WHITE = (255, 255, 255)
ACCENT = (0x22, 0xD3, 0xEE)

TRIANGLE = [(330, 260), (330, 760), (790, 510)]
TRIANGLE_RADIUS = 40
BUBBLE = (560, 640, 920, 860)
BUBBLE_RADIUS = 80
BUBBLE_TAIL = [(600, 840), (600, 930), (700, 850)]
DOT_Y, DOT_XS, DOT_R = 750, (645, 740, 835), 20


def s(v):
    return v * SCALE


def background():
    # 縦1pxの帯を作って横に伸ばす（全画素ループは遅い）。
    n = SIZE * SCALE
    col = Image.new("RGB", (1, n))
    for y in range(n):
        t = y / (n - 1)
        col.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    return col.resize((n, n))


def rounded_triangle(draw, pts, r, fill):
    """辺は元の三角形と一致し、角だけ半径rで丸める。"""
    # 各辺を内側へrだけ平行移動した三角形を求める。
    cx = sum(p[0] for p in pts) / 3
    cy = sum(p[1] for p in pts) / 3
    lines = []
    for i in range(3):
        (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % 3]
        dx, dy = x2 - x1, y2 - y1
        ln = math.hypot(dx, dy)
        nx, ny = -dy / ln, dx / ln
        if (cx - x1) * nx + (cy - y1) * ny < 0:
            nx, ny = -nx, -ny
        lines.append(((x1 + nx * r, y1 + ny * r), (dx, dy)))
    inner = []
    for i in range(3):
        (p, d), (q, e) = lines[i - 1], lines[i]
        det = d[0] * -e[1] + e[0] * d[1]
        t = ((q[0] - p[0]) * -e[1] + e[0] * (q[1] - p[1])) / det
        inner.append((p[0] + d[0] * t, p[1] + d[1] * t))
    sc = [(s(x), s(y)) for x, y in inner]
    draw.polygon(sc, fill=fill)
    for i in range(3):
        a, b = sc[i], sc[(i + 1) % 3]
        # PILのline(width=)は斜め線の端がずれて段差が出るので、幅2rの四角形で塗る。
        ex, ey = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(ex, ey)
        ox, oy = -ey / ln * s(r), ex / ln * s(r)
        draw.polygon([(a[0] + ox, a[1] + oy), (b[0] + ox, b[1] + oy), (b[0] - ox, b[1] - oy), (a[0] - ox, a[1] - oy)], fill=fill)
        draw.ellipse([a[0] - s(r), a[1] - s(r), a[0] + s(r), a[1] + s(r)], fill=fill)


def main():
    img = background()
    d = ImageDraw.Draw(img)
    rounded_triangle(d, TRIANGLE, TRIANGLE_RADIUS, WHITE)
    d.rounded_rectangle([s(v) for v in BUBBLE], radius=s(BUBBLE_RADIUS), fill=ACCENT)
    d.polygon([(s(x), s(y)) for x, y in BUBBLE_TAIL], fill=ACCENT)
    for x in DOT_XS:
        d.ellipse([s(x - DOT_R), s(DOT_Y - DOT_R), s(x + DOT_R), s(DOT_Y + DOT_R)], fill=BG_BOTTOM)
    out = Path(__file__).parent.parent / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    # アルファなしのRGBで保存する（iOSのアイコンは透過不可）。
    img.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(out)
    print(out)


if __name__ == "__main__":
    main()
