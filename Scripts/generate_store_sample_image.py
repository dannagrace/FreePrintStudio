#!/usr/bin/env python3
import math
import os
import struct
import zlib

WIDTH = 1600
HEIGHT = 1000
OUTPUT = "AppStore/Assets/sample-print-image.png"


def rgb(hex_value):
    return ((hex_value >> 16) & 255, (hex_value >> 8) & 255, hex_value & 255)


def blend(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def set_pixel(pixels, x, y, color):
    if 0 <= x < WIDTH and 0 <= y < HEIGHT:
        pixels[y][x] = color


def fill_rect(pixels, x0, y0, x1, y1, color):
    for y in range(max(0, y0), min(HEIGHT, y1)):
        row = pixels[y]
        for x in range(max(0, x0), min(WIDTH, x1)):
            row[x] = color


def fill_circle(pixels, cx, cy, radius, color):
    r2 = radius * radius
    for y in range(cy - radius, cy + radius + 1):
        for x in range(cx - radius, cx + radius + 1):
            if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2:
                set_pixel(pixels, x, y, color)


def line(pixels, x0, y0, x1, y1, width, color):
    dx = x1 - x0
    dy = y1 - y0
    steps = max(abs(dx), abs(dy), 1)
    radius = max(1, width // 2)
    for step in range(steps + 1):
        t = step / steps
        x = round(x0 + dx * t)
        y = round(y0 + dy * t)
        fill_circle(pixels, x, y, radius, color)


def fill_polygon(pixels, points, color):
    min_y = max(0, min(y for _, y in points))
    max_y = min(HEIGHT - 1, max(y for _, y in points))
    for y in range(min_y, max_y + 1):
        intersections = []
        for i in range(len(points)):
            x1, y1 = points[i]
            x2, y2 = points[(i + 1) % len(points)]
            if y1 == y2:
                continue
            if min(y1, y2) <= y < max(y1, y2):
                intersections.append(x1 + (y - y1) * (x2 - x1) / (y2 - y1))
        intersections.sort()
        for i in range(0, len(intersections), 2):
            if i + 1 >= len(intersections):
                break
            fill_rect(pixels, math.floor(intersections[i]), y, math.ceil(intersections[i + 1]), y + 1, color)


def write_png(path, pixels):
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b in row:
            raw.extend((r, g, b))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)))
    png.extend(chunk(b"IDAT", zlib.compress(bytes(raw), level=9)))
    png.extend(chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)


top = rgb(0xF8FAFC)
bottom = rgb(0xDBEAFE)
pixels = [[blend(top, bottom, y / (HEIGHT - 1)) for _ in range(WIDTH)] for y in range(HEIGHT)]

blue = rgb(0x2563EB)
teal = rgb(0x0F766E)
green = rgb(0x22C55E)
yellow = rgb(0xFACC15)
slate = rgb(0x0F172A)
light_blue = rgb(0xE0F2FE)
gray = rgb(0xCBD5E1)

line(pixels, 90, 90, 1510, 90, 24, blue)
line(pixels, 1510, 90, 1510, 910, 24, blue)
line(pixels, 1510, 910, 90, 910, 24, blue)
line(pixels, 90, 910, 90, 90, 24, blue)

fill_rect(pixels, 170, 198, 890, 286, teal)
fill_rect(pixels, 170, 322, 690, 368, gray)

fill_rect(pixels, 178, 432, 738, 792, light_blue)
line(pixels, 178, 432, 738, 432, 14, teal)
line(pixels, 738, 432, 738, 792, 14, teal)
line(pixels, 738, 792, 178, 792, 14, teal)
line(pixels, 178, 792, 178, 432, 14, teal)
fill_circle(pixels, 642, 530, 35, yellow)
fill_polygon(pixels, [(220, 760), (382, 570), (492, 670), (690, 480), (690, 760)], green)

for index in range(7):
    x = 865 + index * 88
    line(pixels, x, 470, x, 755, 16 if index % 2 == 0 else 10, blue)

for index in range(4):
    y = 490 + index * 88
    line(pixels, 855, y, 1390, y, 16 if index % 2 == 0 else 10, blue)

for index in range(3):
    fill_rect(pixels, 850, 360 + index * 85, 1210 + index * 80, 398 + index * 85, slate)

write_png(OUTPUT, pixels)
print(f"Wrote {OUTPUT}")
