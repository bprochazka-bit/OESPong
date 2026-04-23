#!/usr/bin/env python3
"""Generates an 8 KB CHR-ROM for NES PONG.

Layout:
  Pattern table 0 (BG, tiles $00-$FF):
    $00       blank
    $01-$1A   A-Z
    $1B-$24   0-9
    $25       ':'
    $26       '-'
    $27       '.'
    $28       '!'
    $29       solid block (used for big PONG letters + paddles)
    $2A-$2D   big 'P' quadrants (TL, TR, BL, BR)
    $2E-$31   big 'O' quadrants
    $32-$35   big 'N' quadrants
    $36-$39   big 'G' quadrants
    rest      zeroes

  Pattern table 1 (sprites, tiles $00-$FF):
    $00       blank
    $01       paddle tile (solid 8x8)
    $02       ball tile (3x3 centered dot)
"""
import os, sys

FONT_W, FONT_H = 8, 8

# 5x7 glyphs (rendered into 8x8 tiles, left-aligned with 1px border)
FONT = {
  ' ': ["        "] * 7,
  'A': [" XXXXX  ",
        "X     X ",
        "X     X ",
        "XXXXXXX ",
        "X     X ",
        "X     X ",
        "X     X "],
  'B': ["XXXXXX  ",
        "X     X ",
        "X     X ",
        "XXXXXX  ",
        "X     X ",
        "X     X ",
        "XXXXXX  "],
  'C': [" XXXXX  ",
        "X     X ",
        "X       ",
        "X       ",
        "X       ",
        "X     X ",
        " XXXXX  "],
  'D': ["XXXXXX  ",
        "X     X ",
        "X     X ",
        "X     X ",
        "X     X ",
        "X     X ",
        "XXXXXX  "],
  'E': ["XXXXXXX ",
        "X       ",
        "X       ",
        "XXXXX   ",
        "X       ",
        "X       ",
        "XXXXXXX "],
  'F': ["XXXXXXX ",
        "X       ",
        "X       ",
        "XXXXX   ",
        "X       ",
        "X       ",
        "X       "],
  'G': [" XXXXX  ",
        "X     X ",
        "X       ",
        "X   XXX ",
        "X     X ",
        "X     X ",
        " XXXXX  "],
  'H': ["X     X ",
        "X     X ",
        "X     X ",
        "XXXXXXX ",
        "X     X ",
        "X     X ",
        "X     X "],
  'I': [" XXXXX  ",
        "   X    ",
        "   X    ",
        "   X    ",
        "   X    ",
        "   X    ",
        " XXXXX  "],
  'J': ["  XXXXX ",
        "     X  ",
        "     X  ",
        "     X  ",
        "     X  ",
        "X    X  ",
        " XXXX   "],
  'K': ["X    X  ",
        "X   X   ",
        "X  X    ",
        "XXX     ",
        "X  X    ",
        "X   X   ",
        "X    X  "],
  'L': ["X       ",
        "X       ",
        "X       ",
        "X       ",
        "X       ",
        "X       ",
        "XXXXXXX "],
  'M': ["X     X ",
        "XX   XX ",
        "X X X X ",
        "X  X  X ",
        "X     X ",
        "X     X ",
        "X     X "],
  'N': ["X     X ",
        "XX    X ",
        "X X   X ",
        "X  X  X ",
        "X   X X ",
        "X    XX ",
        "X     X "],
  'O': [" XXXXX  ",
        "X     X ",
        "X     X ",
        "X     X ",
        "X     X ",
        "X     X ",
        " XXXXX  "],
  'P': ["XXXXXX  ",
        "X     X ",
        "X     X ",
        "XXXXXX  ",
        "X       ",
        "X       ",
        "X       "],
  'Q': [" XXXXX  ",
        "X     X ",
        "X     X ",
        "X     X ",
        "X   X X ",
        "X    X  ",
        " XXXX X "],
  'R': ["XXXXXX  ",
        "X     X ",
        "X     X ",
        "XXXXXX  ",
        "X   X   ",
        "X    X  ",
        "X     X "],
  'S': [" XXXXXX ",
        "X       ",
        "X       ",
        " XXXXX  ",
        "      X ",
        "      X ",
        "XXXXXX  "],
  'T': ["XXXXXXX ",
        "   X    ",
        "   X    ",
        "   X    ",
        "   X    ",
        "   X    ",
        "   X    "],
  'U': ["X     X ",
        "X     X ",
        "X     X ",
        "X     X ",
        "X     X ",
        "X     X ",
        " XXXXX  "],
  'V': ["X     X ",
        "X     X ",
        "X     X ",
        "X     X ",
        " X   X  ",
        "  X X   ",
        "   X    "],
  'W': ["X     X ",
        "X     X ",
        "X     X ",
        "X  X  X ",
        "X X X X ",
        "XX   XX ",
        "X     X "],
  'X': ["X     X ",
        " X   X  ",
        "  X X   ",
        "   X    ",
        "  X X   ",
        " X   X  ",
        "X     X "],
  'Y': ["X     X ",
        " X   X  ",
        "  X X   ",
        "   X    ",
        "   X    ",
        "   X    ",
        "   X    "],
  'Z': ["XXXXXXX ",
        "     X  ",
        "    X   ",
        "   X    ",
        "  X     ",
        " X      ",
        "XXXXXXX "],
  '0': [" XXXXX  ",
        "X     X ",
        "X    XX ",
        "X   X X ",
        "X  X  X ",
        "X     X ",
        " XXXXX  "],
  '1': ["   X    ",
        "  XX    ",
        " X X    ",
        "   X    ",
        "   X    ",
        "   X    ",
        " XXXXX  "],
  '2': [" XXXXX  ",
        "X     X ",
        "      X ",
        "   XXX  ",
        "  X     ",
        " X      ",
        "XXXXXXX "],
  '3': [" XXXXX  ",
        "X     X ",
        "      X ",
        "   XXX  ",
        "      X ",
        "X     X ",
        " XXXXX  "],
  '4': ["    XX  ",
        "   X X  ",
        "  X  X  ",
        " X   X  ",
        "XXXXXXX ",
        "     X  ",
        "     X  "],
  '5': ["XXXXXXX ",
        "X       ",
        "X       ",
        "XXXXXX  ",
        "      X ",
        "X     X ",
        " XXXXX  "],
  '6': [" XXXXX  ",
        "X     X ",
        "X       ",
        "XXXXXX  ",
        "X     X ",
        "X     X ",
        " XXXXX  "],
  '7': ["XXXXXXX ",
        "     X  ",
        "    X   ",
        "   X    ",
        "  X     ",
        " X      ",
        "X       "],
  '8': [" XXXXX  ",
        "X     X ",
        "X     X ",
        " XXXXX  ",
        "X     X ",
        "X     X ",
        " XXXXX  "],
  '9': [" XXXXX  ",
        "X     X ",
        "X     X ",
        " XXXXXX ",
        "      X ",
        "X     X ",
        " XXXXX  "],
  ':': ["        ",
        "  XX    ",
        "  XX    ",
        "        ",
        "  XX    ",
        "  XX    ",
        "        "],
  '-': ["        ",
        "        ",
        "        ",
        " XXXXX  ",
        "        ",
        "        ",
        "        "],
  '.': ["        ",
        "        ",
        "        ",
        "        ",
        "        ",
        "  XX    ",
        "  XX    "],
  '!': ["   X    ",
        "   X    ",
        "   X    ",
        "   X    ",
        "   X    ",
        "        ",
        "   X    "],
}


def tile_from_glyph(rows):
    """Convert 7 rows of 8-char strings -> 16 bytes of CHR data (two planes)."""
    # Pad to 8 rows
    rows = list(rows) + ["        "] * (8 - len(rows))
    plane0 = bytearray()
    plane1 = bytearray()
    for r in rows:
        p0 = 0
        for i, c in enumerate(r):
            if c != ' ':
                p0 |= (1 << (7 - i))
        plane0.append(p0)
        plane1.append(0)  # color plane 2 unused; colour comes from palette idx 1
    return bytes(plane0 + plane1)


def solid_tile():
    return bytes([0xFF] * 8 + [0x00] * 8)


def ball_tile():
    # centered 3x3 block
    rows = [
        "        ",
        "        ",
        "        ",
        "   XXX  ",
        "   XXX  ",
        "   XXX  ",
        "        ",
        "        ",
    ]
    p0 = bytearray()
    p1 = bytearray()
    for r in rows:
        b = 0
        for i, c in enumerate(r):
            if c != ' ':
                b |= (1 << (7 - i))
        p0.append(b); p1.append(0)
    return bytes(p0 + p1)


# Big letter pieces: draw 16x16 letter, then split into 4 8x8 tiles (TL,TR,BL,BR)

BIG = {
  'P': ["XXXXXXXXXXXXX   ",
        "XXXXXXXXXXXXXX  ",
        "XX           XX ",
        "XX           XX ",
        "XX           XX ",
        "XX           XX ",
        "XX          XX  ",
        "XXXXXXXXXXXXX   ",
        "XX              ",
        "XX              ",
        "XX              ",
        "XX              ",
        "XX              ",
        "XX              ",
        "XX              ",
        "XX              "],
  'O': ["   XXXXXXXXXX   ",
        " XXXXXXXXXXXXXX ",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        " XXXXXXXXXXXXXX ",
        "   XXXXXXXXXX   "],
  'N': ["XX            XX",
        "XXX           XX",
        "XXXX          XX",
        "XX XX         XX",
        "XX  XX        XX",
        "XX   XX       XX",
        "XX    XX      XX",
        "XX     XX     XX",
        "XX      XX    XX",
        "XX       XX   XX",
        "XX        XX  XX",
        "XX         XX XX",
        "XX          XXXX",
        "XX           XXX",
        "XX            XX",
        "XX            XX"],
  'G': ["   XXXXXXXXXX   ",
        " XXXXXXXXXXXXXX ",
        "XX            XX",
        "XX              ",
        "XX              ",
        "XX              ",
        "XX              ",
        "XX              ",
        "XX      XXXXXXXX",
        "XX      XXXXXXXX",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        "XX            XX",
        " XXXXXXXXXXXXXX ",
        "   XXXXXXXXXX   "],
}


def big_tiles(letter):
    """Return list of 4 tiles (TL, TR, BL, BR) for a 16x16 big letter."""
    rows = BIG[letter]
    tiles = []
    for (ry, rx) in [(0,0),(0,8),(8,0),(8,8)]:
        p0 = bytearray()
        p1 = bytearray()
        for y in range(8):
            r = rows[ry + y]
            b = 0
            for x in range(8):
                if r[rx + x] != ' ':
                    b |= (1 << (7 - x))
            p0.append(b); p1.append(0)
        tiles.append(bytes(p0 + p1))
    return tiles


def build_bg():
    data = bytearray(0x1000)  # 4 KB pattern table
    def put(idx, tile):
        data[idx*16:(idx+1)*16] = tile

    # $00 blank (already zero)
    # $01-$1A letters A-Z
    for i, ch in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
        put(0x01 + i, tile_from_glyph(FONT[ch]))
    # $1B-$24 digits 0-9
    for i, ch in enumerate("0123456789"):
        put(0x1B + i, tile_from_glyph(FONT[ch]))
    put(0x25, tile_from_glyph(FONT[':']))
    put(0x26, tile_from_glyph(FONT['-']))
    put(0x27, tile_from_glyph(FONT['.']))
    put(0x28, tile_from_glyph(FONT['!']))
    put(0x29, solid_tile())
    # Big PONG letters
    for i, L in enumerate("PONG"):
        tiles = big_tiles(L)
        for j, t in enumerate(tiles):
            put(0x2A + i*4 + j, t)
    return bytes(data)


def build_sprite():
    data = bytearray(0x1000)
    def put(idx, tile):
        data[idx*16:(idx+1)*16] = tile
    # $00 blank
    put(0x01, solid_tile())       # paddle
    put(0x02, ball_tile())        # ball
    return bytes(data)


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else "chr.bin"
    bg = build_bg()
    sp = build_sprite()
    with open(out_path, "wb") as f:
        f.write(bg)
        f.write(sp)
    print(f"Wrote {out_path}: {len(bg)+len(sp)} bytes")


if __name__ == "__main__":
    main()
