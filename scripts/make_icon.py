"""Генерирует иконку приложения 1024×1024 (три кольца) для iOS и watchOS."""
import sys
from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4  # суперсэмплинг для гладких краёв


def ring(draw, center, radius, width, color, fraction, bg):
    box = [center - radius, center - radius, center + radius, center + radius]
    draw.ellipse(box, outline=bg, width=width)
    start = -90
    end = start + 360 * fraction
    draw.arc(box, start=start, end=end, fill=color, width=width)
    # скруглённые концы
    import math
    for angle in (start, end):
        a = math.radians(angle)
        r = radius - width / 2
        cx = center + r * math.cos(a)
        cy = center + r * math.sin(a)
        draw.ellipse([cx - width / 2, cy - width / 2, cx + width / 2, cy + width / 2], fill=color)


def main(path):
    s = SIZE * SCALE
    img = Image.new("RGB", (s, s), (10, 12, 16))
    draw = ImageDraw.Draw(img)
    c = s // 2
    w = int(78 * SCALE)
    ring(draw, c, int(400 * SCALE), w, (31, 214, 122), 0.82, (24, 44, 36))
    ring(draw, c, int(290 * SCALE), w, (47, 140, 255), 0.64, (20, 34, 56))
    ring(draw, c, int(180 * SCALE), w, (157, 140, 255), 0.9, (36, 32, 60))
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(path, "PNG")


if __name__ == "__main__":
    main(sys.argv[1])
