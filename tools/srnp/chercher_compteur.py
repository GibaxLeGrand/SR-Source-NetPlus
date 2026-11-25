"""Cherche des compteurs de frames : mots qui diffèrent entre deux runs d'un petit écart entier.
usage: python -I chercher_compteur.py <run_a> <run_b> [<run_c> ...]
Pour chaque paire (a, x), liste les adresses où b-a est entre 1 et 600 (et le même pour plusieurs mots)."""
import collections, struct, sys
from pathlib import Path
def load(run):
    run = Path(run)
    return (run / "mem1_lo.bin").read_bytes() + (run / "mem1_hi.bin").read_bytes()
runs = sys.argv[1:]
a = load(runs[0])
n = len(a) // 4
wa = struct.unpack(f">{n}I", a)
for other in runs[1:]:
    wb = struct.unpack(f">{n}I", load(other))
    deltas = collections.Counter()
    exemples = collections.defaultdict(list)
    for i in range(n):
        if wa[i] != wb[i]:
            d = (wb[i] - wa[i]) & 0xFFFFFFFF
            if d >= 0x80000000:
                d -= 0x100000000
            if 1 <= abs(d) <= 600 and wa[i] < 0x10000000:
                deltas[d] += 1
                if len(exemples[d]) < 6:
                    exemples[d].append(f"0x{0x80000000 + 4 * i:08X}={wa[i]}->{wb[i]}")
    print(f"== {Path(runs[0]).name} -> {Path(other).name}")
    for d, c in deltas.most_common(6):
        print(f"  écart {d:+d} : {c} mots, ex. {', '.join(exemples[d])}")
