#!/usr/bin/env python3
"""Draws this theme's pictures from the drawings below and writes them as PNGs
beside this file (or into the folder given), with nothing but Python's own
library. Change a drawing, run it again, and copy the folder to the data
folder's themes.

In a drawing every character is one art pixel:
    #   light: drawn in the color scheme's color
    o   dark:  drawn in its background color
    .   clear: nothing drawn, what is behind shows
Every row of a drawing must be as long as the others.
"""
import os
import struct
import sys
import zlib

PICTURES = {
    # The window's frame, "border": 4 in theme.json: the four 4x4 corners
    # stay as drawn, the edges (the middle row and column) stretch along the
    # window, and the middle pixel fills it. Clipped corners, a bracket in
    # each, the window's background inside.
    "window.png": [
        "..#####..",
        ".#ooooo#.",
        "#o##o##o#",
        "#o#ooo#o#",
        "#ooooooo#",
        "#o#ooo#o#",
        "#o##o##o#",
        ".#ooooo#.",
        "..#####..",
    ],
    # The title bar, "border": [2, 2, 5, 2] (left, top, right, bottom): clipped
    # on the left, three stripes kept at its right end. The title is written
    # in the dark color, so the middle stays light.
    "titlebar.png": [
        ".####o#o#.",
        "#####o#o##",
        "#####o#o##",
        "#####o#o##",
        "#####o#o##",
        "#####o#o##",
        ".####o#o#.",
    ],
    # The hint bar, "border": 3 and "tile": "repeat": the two middle columns
    # of its top and bottom edges repeat along the bar, a dotted line.
    "hintbar.png": [
        ".######.",
        "###o####",
        "########",
        "########",
        "########",
        "###o####",
        ".######.",
    ],
    # The selected line, "border": 3: clipped corners and a dark line along
    # its foot. Its text is written in the dark color too.
    "selection.png": [
        ".#####.",
        "#######",
        "#######",
        "#######",
        "#######",
        "#ooooo#",
        ".#####.",
    ],
}

PIXELS = {"#": b"\xff\xff\xff\xff", "o": b"\x00\x00\x00\xff", ".": b"\x00\x00\x00\x00"}


def png(rows):
    """An RGBA PNG of a drawing, with no metadata."""
    width, height = len(rows[0]), len(rows)
    raw = b"".join(b"\x00" + b"".join(PIXELS[c] for c in row) for row in rows)

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    for name, rows in PICTURES.items():
        bad = {c for row in rows for c in row} - set(PIXELS)
        if bad:
            sys.exit(f"{name}: {''.join(sorted(bad))} is not one of # o .")
        if len({len(row) for row in rows}) != 1:
            sys.exit(f"{name}: its rows are not all as long")
        with open(os.path.join(folder, name), "wb") as f:
            f.write(png(rows))
        print(f"{name}: {len(rows[0])}x{len(rows)}")


if __name__ == "__main__":
    main()
