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


def smoothstep(edge0, edge1, value):
    if edge0 == edge1:
        return 1.0 if value >= edge1 else 0.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def organic_disk_alpha(x, y, cx, cy, rx, ry):
    theta = math.atan2(y - cy, x - cx)
    wobble_x = 1.0 + 0.030 * math.sin(theta * 3.0 + 0.6) + 0.018 * math.sin(theta * 5.0 - 1.2)
    wobble_y = 1.0 + 0.025 * math.cos(theta * 2.0 - 0.4)
    d = math.sqrt(((x - cx) / (rx * wobble_x)) ** 2 + ((y - cy) / (ry * wobble_y)) ** 2)
    return smoothstep(1.04, 0.96, d)


def droplet_alpha(x, y, cx, cy, width, height):
    top = cy - height * 0.56
    bottom = cy + height * 0.56
    if y < top or y > bottom:
        return 0.0
    t = (y - top) / (bottom - top)
    lobe = math.sin(math.pi * t)
    local_width = width * (0.03 + 0.97 * (lobe ** 0.74)) * (0.38 + 0.62 * t)
    local_width *= 1.0 + 0.060 * math.sin(t * math.pi * 2.0 + 0.8)
    if local_width <= 0:
        return 0.0
    dx = abs(x - cx) / local_width
    edge_x = smoothstep(1.04, 0.90, dx)
    edge_y = smoothstep(1.02, 0.94, abs(t * 2.0 - 1.0))
    return edge_x * edge_y


def capsule_highlight_alpha(x, y, cx, cy, rx, ry):
    alpha = ellipse_alpha(x, y, cx, cy, rx, ry, 2.2)
    shine_cut = ellipse_alpha(x, y, cx + rx * 0.18, cy + ry * 0.30, rx * 1.05, ry * 0.95, 1.5)
    return max(0.0, alpha - shine_cut * 0.72)


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
                    color = blend(color, (7, 18, 48, min(1, tile)))
                    color = blend(color, (20, 62, 138, max(0, (1 - radial) * 0.58) * tile))
                    color = blend(color, (255, 255, 255, max(0, 1 - y / h) * 0.08 * tile))

            cx = w * 0.50
            cy = h * 0.51
            shadow = ellipse_alpha(x, y, cx, cy + h * 0.09, w * 0.32, h * 0.24, 1.7)
            if shadow > 0:
                color = blend(color, (0, 0, 0, min(0.24, shadow * 0.24)))

            # Organic nazar glass: intentionally less geometric than the old target-like icon.
            body = organic_disk_alpha(x, y, cx, cy, w * 0.360, h * 0.330)
            if body > 0:
                dist = math.sqrt(((x - cx) / (w * 0.37)) ** 2 + ((y - cy) / (h * 0.34)) ** 2)
                light = max(0.0, 1.0 - math.sqrt((x - w * 0.39) ** 2 + (y - h * 0.35) ** 2) / (w * 0.46))
                base = (
                    8 + 22 * light,
                    36 + 56 * light,
                    150 + 92 * light,
                    0.98 * body,
                )
                color = blend(color, base)
                edge = smoothstep(0.76, 1.00, dist) * body
                color = blend(color, (10, 48, 185, 0.30 * edge))
                color = blend(color, (70, 166, 255, 0.18 * smoothstep(1.02, 0.88, dist) * body))

            rim = soft_circle_ring(x, y, cx, cy, w * 0.345, w * 0.034) * organic_disk_alpha(x, y, cx, cy, w * 0.37, h * 0.34)
            if rim > 0:
                color = blend(color, (58, 135, 255, 0.34 * rim))

            white_drop = droplet_alpha(x, y, cx, cy + h * 0.004, w * 0.220, h * 0.400)
            if white_drop > 0:
                color = blend(color, (246, 250, 255, 0.97 * white_drop))

            iris_outer = ellipse_alpha(x, y, cx + w * 0.010, cy + h * 0.050, w * 0.112, h * 0.110, 2.3)
            if iris_outer > 0:
                color = blend(color, (35, 190, 230, 0.84 * iris_outer))
            iris_inner = ellipse_alpha(x, y, cx + w * 0.012, cy + h * 0.050, w * 0.074, h * 0.071, 2.4)
            if iris_inner > 0:
                color = blend(color, (102, 216, 246, 0.60 * iris_inner))

            pupil = ellipse_alpha(x, y, cx + w * 0.012, cy + h * 0.050, w * 0.043, h * 0.049, 2.4)
            if pupil > 0:
                color = blend(color, (6, 12, 30, min(1, pupil)))
            highlight = ellipse_alpha(x, y, w * 0.455, h * 0.425, w * 0.030, h * 0.030, 2.5)
            if highlight > 0:
                color = blend(color, (255, 255, 255, min(0.82, highlight * 0.82)))
            gloss = capsule_highlight_alpha(x, y, w * 0.40, h * 0.34, w * 0.13, h * 0.050)
            if gloss > 0:
                color = blend(color, (255, 255, 255, min(0.24, gloss * 0.24)))
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
