#!/usr/bin/env python3
import math
import os
import struct
import sys
import zlib


def clamp(value):
    return max(0, min(255, int(value)))


def blend(dst, src):
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    a = sa + da * (1 - sa)
    if a <= 0:
        return (0, 0, 0, 0)
    return (
        (sr * sa + dr * da * (1 - sa)) / a,
        (sg * sa + dg * da * (1 - sa)) / a,
        (sb * sa + db * da * (1 - sa)) / a,
        a,
    )


def ellipse_alpha(x, y, cx, cy, rx, ry, softness=1.2):
    d = math.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
    return max(0.0, min(1.0, (1.0 - d) * softness + 0.5))


def draw_icon(size, transparent=False):
    scale = 3
    w = h = size
    pixels = []
    for yy in range(h):
        row = []
        for xx in range(w):
            x = xx + 0.5
            y = yy + 0.5
            if transparent:
                color = (0, 0, 0, 0)
            else:
                color = (18, 21, 28, 1)
            # Back blue glass disc.
            a = ellipse_alpha(x, y, w / 2, h / 2, w * 0.44, h * 0.44, 1.8)
            if a > 0:
                radial = math.sqrt((x - w * 0.42) ** 2 + (y - h * 0.32) ** 2) / (w * 0.7)
                blue = (
                    19 + 10 * (1 - radial),
                    92 + 80 * (1 - radial),
                    210 + 35 * (1 - radial),
                    min(1, a),
                )
                color = blend(color, blue)
            # White almond.
            a = ellipse_alpha(x, y, w / 2, h / 2, w * 0.34, h * 0.20, 2.2)
            if a > 0:
                color = blend(color, (245, 248, 255, min(1, a)))
            # Cyan iris.
            a = ellipse_alpha(x, y, w / 2, h / 2, w * 0.18, h * 0.18, 2.0)
            if a > 0:
                color = blend(color, (36, 177, 222, min(1, a)))
            # Deep pupil.
            a = ellipse_alpha(x, y, w / 2, h / 2, w * 0.085, h * 0.085, 2.0)
            if a > 0:
                color = blend(color, (16, 27, 54, min(1, a)))
            # Catch light.
            a = ellipse_alpha(x, y, w * 0.46, h * 0.43, w * 0.034, h * 0.034, 2.5)
            if a > 0:
                color = blend(color, (255, 255, 255, min(0.9, a)))
            # Subtle ring.
            d = math.sqrt(((x - w / 2) / (w * 0.44)) ** 2 + ((y - h / 2) / (h * 0.44)) ** 2)
            if 0.92 < d < 1.02:
                color = blend(color, (105, 193, 255, 0.42))
            row.append(tuple(clamp(c * 255) if i < 3 else clamp(c * 255) for i, c in enumerate(color)))
        pixels.append(row)
    return pixels


def write_png(path, pixels):
    h = len(pixels)
    w = len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw.extend([r, g, b, a])
    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )
    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(data)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    iconset = os.path.join(out, "ObserverIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for size, name in sizes:
        write_png(os.path.join(iconset, name), draw_icon(size))
    write_png(os.path.join(out, "ObserverStatus.png"), draw_icon(64, transparent=True))


if __name__ == "__main__":
    main()
