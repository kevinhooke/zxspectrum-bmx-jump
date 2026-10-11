#!/usr/bin/env python3
"""
Convert the ASCII pixel art in src/sprites.txt into sjasmplus DB lines.

Usage: gen_sprites.py <sprites.txt> <out.asm>

Each sprite becomes a label followed by its bytes in cell order: the
sprite is split into 8x8 cells, emitted left to right then top to
bottom, 8 bytes (one per pixel row, MSB = leftmost pixel) per cell.
"""
import sys


def parse(path):
    sprites = []
    name, rows = None, []
    with open(path) as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith(";"):
                continue
            if line.endswith(":"):
                if name:
                    sprites.append((name, rows))
                name, rows = line[:-1].strip(), []
                continue
            if name is None:
                sys.exit(f"{path}:{lineno}: pixel row before any 'Name:' header")
            if set(line) - {".", "#"}:
                sys.exit(f"{path}:{lineno}: rows may only contain '.' and '#'")
            rows.append(line)
    if name:
        sprites.append((name, rows))
    return sprites


def cells(name, rows):
    height, width = len(rows), len(rows[0])
    if any(len(r) != width for r in rows):
        sys.exit(f"{name}: all rows must be the same width")
    if width % 8 or height % 8:
        sys.exit(f"{name}: size {width}x{height} is not a multiple of 8")
    for cy in range(height // 8):
        for cx in range(width // 8):
            yield [
                int(rows[cy * 8 + y][cx * 8 : cx * 8 + 8].replace(".", "0").replace("#", "1"), 2)
                for y in range(8)
            ]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out = sys.argv[1], sys.argv[2]
    lines = [f"; Generated from {src} by gen_sprites.py - do not edit."]
    for name, rows in parse(src):
        lines.append(f"{name}:")
        for cell in cells(name, rows):
            lines.append("    DB " + ",".join(f"${b:02X}" for b in cell))
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
