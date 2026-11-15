"""Minimal RGBA pixel canvas with a pure-Python PNG writer (no Pillow needed).

Colours are (r, g, b) or (r, g, b, a) tuples. `None` means transparent.
"""
import struct
import zlib


def _rgba(c):
    if c is None:
        return None
    if len(c) == 3:
        return (c[0], c[1], c[2], 255)
    return tuple(c)


class Canvas:
    def __init__(self, w, h, fill=None):
        self.w, self.h = w, h
        self.px = [_rgba(fill)] * (w * h)

    # -- pixel access -------------------------------------------------
    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y * self.w + x]
        return None

    def set(self, x, y, c):
        """Set a pixel; translucent colours blend over what is already there."""
        if c is None or not (0 <= x < self.w and 0 <= y < self.h):
            return
        c = _rgba(c)
        if c[3] < 255:
            under = self.px[y * self.w + x]
            if under is not None and under[3] > 0:
                a = c[3] / 255.0
                c = (int(c[0] * a + under[0] * (1 - a)),
                     int(c[1] * a + under[1] * (1 - a)),
                     int(c[2] * a + under[2] * (1 - a)),
                     max(under[3], c[3]))
        self.px[y * self.w + x] = c

    def clear(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y * self.w + x] = None

    # -- primitives ---------------------------------------------------
    def rect(self, x0, y0, x1, y1, c):
        """Filled rectangle, inclusive coordinates."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, c)

    def hline(self, x0, x1, y, c):
        for x in range(x0, x1 + 1):
            self.set(x, y, c)

    def vline(self, x, y0, y1, c):
        for y in range(y0, y1 + 1):
            self.set(x, y, c)

    def line(self, x0, y0, x1, y1, c):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def ellipse(self, cx, cy, rx, ry, c):
        """Filled ellipse centred on (cx, cy); radii in pixels."""
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                nx = (x + 0.5 - cx) / max(rx, 0.5)
                ny = (y + 0.5 - cy) / max(ry, 0.5)
                if nx * nx + ny * ny <= 1.0:
                    self.set(x, y, c)

    # -- whole-canvas operations -------------------------------------
    def blit(self, src, dx, dy):
        for y in range(src.h):
            for x in range(src.w):
                p = src.px[y * src.w + x]
                if p is not None:
                    self.set(x + dx, y + dy, p)

    def crop(self, x, y, w, h):
        out = Canvas(w, h)
        for yy in range(h):
            for xx in range(w):
                out.px[yy * w + xx] = self.get(x + xx, y + yy)
        return out

    def flip_h(self):
        out = Canvas(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                out.px[y * self.w + (self.w - 1 - x)] = self.px[y * self.w + x]
        return out

    def outline(self, color):
        """Add a 1px outline around opaque pixels (only onto fully transparent ones)."""
        color = _rgba(color)
        marks = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y * self.w + x] is not None:
                    continue
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    p = self.get(nx, ny)
                    if p is not None and p[3] >= 200:
                        marks.append((x, y))
                        break
        for x, y in marks:
            self.px[y * self.w + x] = color

    def remove_rows(self, y0, y1):
        """Delete rows y0..y1 (inclusive); everything above shifts down so size is unchanged."""
        n = y1 - y0 + 1
        out = Canvas(self.w, self.h)
        for y in range(y0):
            for x in range(self.w):
                out.px[(y + n) * self.w + x] = self.px[y * self.w + x]
        for y in range(y1 + 1, self.h):
            for x in range(self.w):
                out.px[y * self.w + x] = self.px[y * self.w + x]
        return out

    def scaled(self, n):
        out = Canvas(self.w * n, self.h * n)
        for y in range(self.h):
            for x in range(self.w):
                p = self.px[y * self.w + x]
                for yy in range(n):
                    for xx in range(n):
                        out.px[(y * n + yy) * out.w + x * n + xx] = p
        return out

    # -- output -------------------------------------------------------
    def png_bytes(self):
        raw = bytearray()
        for y in range(self.h):
            raw.append(0)
            for x in range(self.w):
                p = self.px[y * self.w + x]
                if p is None:
                    raw.extend((0, 0, 0, 0))
                else:
                    raw.extend(p)

        def chunk(tag, data):
            body = tag + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

        ihdr = struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0)
        return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
                + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))

    def save(self, path):
        with open(path, "wb") as f:
            f.write(self.png_bytes())


def shade(c, f):
    """Multiply RGB by f (keeps alpha)."""
    out = [max(0, min(255, int(v * f))) for v in c[:3]]
    return tuple(out) + tuple(c[3:])


def mix(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))
