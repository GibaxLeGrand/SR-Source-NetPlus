"""cherche_suite.py <run> <dumps:valeur>... : les octets de MEM1 (lo) qui valent chaque valeur dans chaque dump
(ex. l1a:1 l1b:1 l2a:2 l3a:3)."""
import sys
import os

run = sys.argv[1]
paires = [(n.split(":")[0], int(n.split(":")[1], 0)) for n in sys.argv[2:]]
dumps = [(open(os.path.join(run, n + "_lo.bin"), "rb").read(), v) for n, v in paires]
d0, v0 = dumps[0]
o = d0.find(bytes([v0]))
trouves = []
while o != -1:
    if all(d[o] == v for d, v in dumps[1:]):
        trouves.append(o)
    o = d0.find(bytes([v0]), o + 1)
print(len(trouves), "octets")
for o in trouves[:40]:
    print(f"  {0x80000000 + o:08X}")
