#!/usr/bin/env python3
"""Generate the boss card's diagram primitives.

The whole point of the boss card is that a picture per boss is unaffordable, so
the picture is composed at runtime from a handful of shapes. These are those
shapes. They are generated rather than drawn by hand so the geometry is exact
and a tweak is a number here rather than a round trip through an image editor.

Everything is emitted white with an alpha channel, so the addon tints each one
with SetVertexColor and the same file serves every verdict colour.

    python tools/gen-diagram-textures.py

Writes into media/diagram/. No third-party dependencies -- PNG is simple enough
to emit directly, and requiring Pillow to build a texture would be a worse trade
than thirty lines of encoder.
"""

import math
import os
import struct
import sys
import zlib

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "media", "diagram")

SIZE = 256
SUPERSAMPLE = 4  # per axis, so 16 samples a pixel


def write_png(path, width, height, pixels):
    """pixels: a flat bytearray of RGBA, width*height*4."""
    rows = b"".join(
        b"\x00" + bytes(pixels[y * width * 4:(y + 1) * width * 4])
        for y in range(height)
    )

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows, 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as handle:
        handle.write(png)


def render(coverage_fn, size=SIZE):
    """Supersample coverage_fn(x, y) -> 0..1 into a white RGBA image."""
    pixels = bytearray(size * size * 4)
    step = 1.0 / SUPERSAMPLE
    offset = step / 2.0

    for py in range(size):
        for px in range(size):
            total = 0.0
            for sy in range(SUPERSAMPLE):
                for sx in range(SUPERSAMPLE):
                    total += coverage_fn(px + offset + sx * step, py + offset + sy * step)
            alpha = total / (SUPERSAMPLE * SUPERSAMPLE)
            if alpha <= 0.0:
                continue
            index = (py * size + px) * 4
            pixels[index + 0] = 255
            pixels[index + 1] = 255
            pixels[index + 2] = 255
            pixels[index + 3] = min(255, int(alpha * 255 + 0.5))
    return pixels


def cone(half_angle_deg, size=SIZE):
    """A wedge with its apex at the centre of the image, opening upwards.

    The apex sits at the centre so the addon can rotate the texture about its
    own middle and have the cone pivot around the boss it is attached to. The
    radius is half the image, which keeps the wedge inside the inscribed circle
    at every rotation -- rotate a wedge that reached into the corners and the
    tip would be clipped away at 45 degrees.
    """
    centre = size / 2.0
    radius = size / 2.0
    half_angle = math.radians(half_angle_deg)
    # Fade the last of the radius rather than ending on a hard rim, so the cone
    # reads as a threat volume rather than a solid slab.
    fade_from = radius * 0.55

    def coverage(x, y):
        dx = x - centre
        dy = centre - y  # image y grows downwards; we want "up" positive
        distance = math.hypot(dx, dy)
        if distance > radius or distance < 1.0:
            return 0.0
        if abs(math.atan2(dx, dy)) > half_angle:
            return 0.0
        if distance <= fade_from:
            return 1.0
        return 1.0 - (distance - fade_from) / (radius - fade_from)

    return render(coverage, size)


def arrow(size=SIZE):
    """A stubby up-arrow: shaft plus head, centred, pointing up."""
    centre = size / 2.0
    shaft_half = size * 0.075
    head_half = size * 0.22
    head_base = size * 0.42   # y, in image coords
    tip = size * 0.10
    tail = size * 0.90

    def coverage(x, y):
        dx = x - centre
        if head_base <= y <= tail:
            return 1.0 if abs(dx) <= shaft_half else 0.0
        if tip <= y < head_base:
            # Linear taper from the head's base up to the tip.
            span = head_half * (y - tip) / (head_base - tip)
            return 1.0 if abs(dx) <= span else 0.0
        return 0.0

    return render(coverage, size)


def ring(thickness_ratio=0.13, size=SIZE):
    """An annulus, used as the halo around a token."""
    centre = size / 2.0
    outer = size / 2.0 - 1.0
    inner = outer * (1.0 - thickness_ratio * 2.0)

    def coverage(x, y):
        distance = math.hypot(x - centre, centre - y)
        return 1.0 if inner <= distance <= outer else 0.0

    return render(coverage, size)


def disc(size=SIZE):
    """A filled circle, used for the group blob and token backings."""
    centre = size / 2.0
    outer = size / 2.0 - 1.0

    def coverage(x, y):
        return 1.0 if math.hypot(x - centre, centre - y) <= outer else 0.0

    return render(coverage, size)


TEXTURES = [
    ("cone60.png", lambda: cone(30)),
    ("cone90.png", lambda: cone(45)),
    ("cone120.png", lambda: cone(60)),
    ("arrow.png", arrow),
    ("ring.png", ring),
    ("disc.png", disc),
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, build in TEXTURES:
        path = os.path.join(OUT_DIR, name)
        write_png(path, SIZE, SIZE, build())
        print("wrote %s (%d bytes)" % (os.path.relpath(path, os.getcwd()), os.path.getsize(path)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
