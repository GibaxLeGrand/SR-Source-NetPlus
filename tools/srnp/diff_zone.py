"""Mots différents entre deux runs dans une zone (par défaut la BSS de _Main.rel), avec leurs valeurs
en hexadécimal et en flottant. usage: python -I diff_zone.py <run_a> <run_b> [<début> <fin>]"""
import struct
import sys
from pathlib import Path


def load(run):
    run = Path(run)
    return (run / "mem1_lo.bin").read_bytes() + (run / "mem1_hi.bin").read_bytes()


a, b = load(sys.argv[1]), load(sys.argv[2])
lo = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x805FB080
hi = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x806B5774
for o in range(lo - 0x80000000, hi - 0x80000000, 4):
    x, y = a[o:o + 4], b[o:o + 4]
    if x != y:
        fx, fy = struct.unpack(">f", x)[0], struct.unpack(">f", y)[0]
        print(f"0x{0x80000000 + o:08X}: {x.hex()} -> {y.hex()}   ({fx:.6g} -> {fy:.6g})")
