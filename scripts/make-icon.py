#!/usr/bin/env python3
"""Draw an original pulse mark and pack AppIcon.icns. No third-party libraries."""
import struct, subprocess, sys, tempfile, zlib
from pathlib import Path

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

def png(size, pixels):
    raw = b"".join(b"\x00" + pixels[y * size * 4:(y + 1) * size * 4] for y in range(size))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")

def pixel(size, x, y):
    # Dark rounded plate with a teal heartbeat. Coordinates are 0..1.
    nx, ny = (x + 0.5) / size, (y + 0.5) / size
    inset = 0.08
    dx, dy = max(inset - nx, 0, nx - (1 - inset)), max(inset - ny, 0, ny - (1 - inset))
    outside = (dx * dx + dy * dy) > inset * inset
    if outside:
        return (0, 0, 0, 0)
    # Heartbeat through the middle: flat, rise, drop, small recovery, flat.
    samples = [(0.16, 0.50), (0.34, 0.50), (0.42, 0.22), (0.50, 0.78), (0.58, 0.42), (0.66, 0.50), (0.84, 0.50)]
    best = 1
    for i in range(len(samples) - 1):
        x0, y0 = samples[i]
        x1, y1 = samples[i + 1]
        span = x1 - x0
        t = min(1, max(0, (nx - x0) / span))
        px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        best = min(best, (nx - px) ** 2 + (ny - py) ** 2)
    width = 0.045 if size >= 32 else 0.07
    if best <= width * width:
        return (61, 220, 151, 255)
    return (14, 28, 36, 255)

def main():
    if len(sys.argv) != 2:
        sys.exit("usage: make-icon.py <AppIcon.icns>")
    destination = Path(sys.argv[1])
    root = Path(tempfile.mkdtemp(prefix="Pulse.", suffix=".iconset"))
    # iconutil names. @2x files are twice the point size.
    names = {
        "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
    }
    for name, size in names.items():
        pixels = bytearray()
        for y in range(size):
            for x in range(size):
                pixels.extend(pixel(size, x, y))
        path = root / name
        path.write_bytes(png(size, pixels))
        reported = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)], capture_output=True, text=True, check=True)
        print(reported.stdout.strip())
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(["iconutil", "-c", "icns", str(root), "-o", str(destination)], check=True)
    finally:
        subprocess.run(["rm", "-rf", str(root)], check=True)
    print(f"wrote {destination}")

if __name__ == "__main__":
    main()
