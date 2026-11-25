"""diff_etats.py <run> <groupe A> <groupe B> : les mots de 4 octets de MEM1 (lo) constants dans chaque groupe
de dumps (noms séparés par des virgules) et différents d'un groupe à l'autre. Petites valeurs d'abord."""
import sys
import os

run = sys.argv[1]
ga, gb = sys.argv[2].split(","), sys.argv[3].split(",")
lire = lambda n: memoryview(open(os.path.join(run, n + "_lo.bin"), "rb").read())
A, B = [lire(n) for n in ga], [lire(n) for n in gb]
n = len(A[0])
res = []
for o in range(0, n, 4):
    a = A[0][o:o + 4]
    if any(x[o:o + 4] != a for x in A[1:]):
        continue
    b = B[0][o:o + 4]
    if a == b or any(x[o:o + 4] != b for x in B[1:]):
        continue
    va, vb = int.from_bytes(a, "big"), int.from_bytes(b, "big")
    res.append((0x80000000 + o, va, vb))
print(len(res), "mots")
petits = [r for r in res if r[1] < 0x100 and r[2] < 0x100]
print(len(petits), "petits (< 0x100) :")
for adr, va, vb in petits:
    print(f"  {adr:08X}  {va:#x} -> {vb:#x}")
autres = [r for r in res if not (r[1] < 0x100 and r[2] < 0x100)]
print("autres (60 premiers) :")
for adr, va, vb in autres[:60]:
    print(f"  {adr:08X}  {va:08x} -> {vb:08x}")
