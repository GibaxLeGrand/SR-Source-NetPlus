"""diff_groupes.py <a1.bin> <a2.bin>... -- <b1.bin> <b2.bin>... : les mots de 4 octets constants dans le groupe A,
constants dans le groupe B, et différents de A à B (MEM1 lo : 0x80000000). Petites valeurs d'abord."""
import sys

args = sys.argv[1:]
i = args.index("--")
A = [memoryview(open(p, "rb").read()) for p in args[:i]]
B = [memoryview(open(p, "rb").read()) for p in args[i + 1:]]
res = []
for o in range(0, len(A[0]), 4):
    a = A[0][o:o + 4]
    if any(x[o:o + 4] != a for x in A[1:]):
        continue
    b = B[0][o:o + 4]
    if a == b or any(x[o:o + 4] != b for x in B[1:]):
        continue
    res.append((0x80000000 + o, int.from_bytes(a, "big"), int.from_bytes(b, "big")))
print(len(res), "mots")
res.sort(key=lambda r: (max(r[1], r[2]) >= 0x10000, r[0]))
for adr, va, vb in res[:80]:
    print(f"  {adr:08X}  {va:08x} -> {vb:08x}")
