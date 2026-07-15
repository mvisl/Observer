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


def rounded_rect_alpha(x, y, w, h, radius):
    qx = abs(x - w / 2) - (w / 2 - radius)
    qy = abs(y - h / 2) - (h / 2 - radius)
    outside = math.sqrt(max(qx, 0) ** 2 + max(qy, 0) ** 2)
    inside = min(max(qx, qy), 0)
    distance = outside + inside - radius
    return max(0.0, min(1.0, 0.5 - distance))


def soft_circle_ring(x, y, cx, cy, radius, width):
    d = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    return max(0.0, min(1.0, 1 - abs(d - radius) / width))


def draw_icon(size, transparent=False):
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
                tile = rounded_rect_alpha(x, y, w, h, w * 0.22)
                color = (0, 0, 0, 0)
                if tile > 0:
                    radial = math.sqrt((x - w * 0.43) ** 2 + (y - h * 0.30) ** 2) / (w * 0.95)
                    color = blend(color, (8, 14, 34, min(1, tile)))
                    color = blend(color, (18, 52, 112, max(0, (1 - radial) * 0.50) * tile))
                    color = blend(color, (255, 255, 255, max(0, 1 - y / h) * 0.08 * tile))

            cx = w * 0.50
            cy = h * 0.50
            shadow = ellipse_alpha(x, y, cx, cy + h * 0.06, w * 0.30, h * 0.23, 1.7)
            if shadow > 0:
                color = blend(color, (0, 0, 0, min(0.24, shadow * 0.24)))

            # Nazar-style blue glass rings.
            for radius, width, rgba in [
                (w * 0.265, w * 0.060, (31, 89, 220, 0.84)),
                (w * 0.205, w * 0.050, (27, 153, 230, 0.88)),
                (w * 0.145, w * 0.040, (238, 247, 255, 0.96)),
                (w * 0.088, w * 0.035, (19, 58, 142, 0.96)),
                (w * 0.041, w * 0.030, (8, 15, 36, 0.98)),
            ]:
                a = soft_circle_ring(x, y, cx, cy, radius, width)
                if a > 0:
                    color = blend(color, (rgba[0], rgba[1], rgba[2], rgba[3] * a))

            pupil = ellipse_alpha(x, y, cx, cy, w * 0.049, h * 0.049, 2.4)
            if pupil > 0:
                color = blend(color, (6, 12, 30, min(1, pupil)))
            highlight = ellipse_alpha(x, y, w * 0.46, h * 0.44, w * 0.035, h * 0.035, 2.5)
            if highlight > 0:
                color = blend(color, (255, 255, 255, min(0.82, highlight * 0.82)))
            row.append((
                clamp(color[0]),
                clamp(color[1]),
                clamp(color[2]),
                clamp(color[3] * 255),
            ))
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
