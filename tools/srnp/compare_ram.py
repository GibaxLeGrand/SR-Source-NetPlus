"""Compare la MEM1 de deux runs (mem1_lo.bin + mem1_hi.bin) et regroupe les différences.

usage: python -I compare_ram.py <run_a> <run_b> [écart_max_pour_regrouper]
Sortie : nombre de mots de 32 bits différents, puis les zones (début, fin, mots différents),
les plus grosses d'abord, et où elles tombent (DOL, _Main.rel, BSS du REL, au-delà).
"""
import sys
from pathlib import Path

BASE = 0x80000000
ZONES = [
    (0x80000000, 0x80003100, "globales de l'OS"),
    (0x80003100, 0x800E2F20, "code du DOL"),
    (0x800E2F20, 0x80125E00, "données du DOL"),
    (0x80125E00, 0x8021CFA4, "BSS et sdata du DOL"),
    (0x803FBD00, 0x805BCE98, "code de _Main.rel"),
    (0x805BCE98, 0x805FB050, "données de _Main.rel"),
    (0x805FB080, 0x806B5774, "BSS de _Main.rel"),
]


def zone(addr):
    for a, b, name in ZONES:
        if a <= addr < b:
            return name
    return "tas / reste"


def load(run):
    run = Path(run)
    return (run / "mem1_lo.bin").read_bytes() + (run / "mem1_hi.bin").read_bytes()


a, b = load(sys.argv[1]), load(sys.argv[2])
# Compteur de frames du jeu (0x801AF9F0, 25/11 : +2 quand la pause de l'automatisation tombe 2 frames plus
# tard). La pause est demandée par un fil de l'hôte : sous charge, elle peut glisser d'une frame ou plus,
# et la comparaison ne vaut alors rien.
FRAME = 0x801AF9F0 - BASE
fa, fb = (int.from_bytes(x[FRAME:FRAME + 4], "big") for x in (a, b))
print(f"compteur de frames (0x801AF9F0) : {fa} / {fb}" + ("" if fa == fb else "  !! PAUSES À DES FRAMES DIFFÉRENTES"))
gap = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x100
diffs = [o for o in range(0, min(len(a), len(b)), 4) if a[o:o + 4] != b[o:o + 4]]
print(f"mots différents : {len(diffs)} sur {len(a) // 4}")
groups = []
for o in diffs:
    if groups and o - groups[-1][1] <= gap:
        groups[-1][1] = o
        groups[-1][2] += 1
    else:
        groups.append([o, o, 1])
groups.sort(key=lambda g: -g[2])
for start, end, n in groups[:40]:
    print(f"  0x{BASE + start:08X}-0x{BASE + end + 4:08X} : {n:7d} mots  ({zone(BASE + start)})")
if len(groups) > 40:
    print(f"  ... {len(groups) - 40} zones de plus")
by_zone = {}
for o in diffs:
    by_zone[zone(BASE + o)] = by_zone.get(zone(BASE + o), 0) + 1
print("par zone :", ", ".join(f"{k} {v}" for k, v in sorted(by_zone.items(), key=lambda kv: -kv[1])))
# Ligne lisible par les scripts (ASCII) : mots différents dans la BSS de _Main.rel, et en tout.
print(f"RESUME BSS_REL={by_zone.get('BSS de _Main.rel', 0)} TOTAL={len(diffs)} FRAMES={fa}/{fb}" + ("" if fa == fb else " DECALEES"))
