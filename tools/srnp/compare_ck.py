"""Compare les racers vidés à chaque somme de contrôle (SRNP_CKDUMP) par les runners d'un lockstep.

python -I compare_ck.py <run> <runners>
Pour chaque frame vidée par tous : les racers et décalages (hors champs de caméra connus) qui diffèrent
d'un runner à l'autre, avec la valeur de chaque runner pour les premiers.
"""
import collections
import os
import re
import struct
import sys

T = 0x1080
CAMERA = [(0x370, 0x394), (0x8B4, 0x8B8), (0x8C0, 0x8C4), (0xDC4, 0xE74), (0xFD8, 0xFDC), (0x1000, 0x1004), (0x1036, 0x1037), (0x105C, 0x1060),
          (0x84C, 0x858), (0x8BC, 0x8C0), (0x8DB, 0x8DC), (0x894, 0x89C), (0x106C, 0x106D)]

# Bits de l'affichage seul (comme RacersHash) : {octet : bits laissés de côté}.
BITS = {0xBAD: 0x01, 0xBB9: 0x01}
MASQUE = bytearray(b"\xff" * T)
for a, b in CAMERA:
    MASQUE[a:b] = bytes(b - a)
for o, bits in BITS.items():
    MASQUE[o] &= ~bits & 0xFF
MASQUE = int.from_bytes(bytes(MASQUE) * 8, "big")

run, n = sys.argv[1], int(sys.argv[2])
frames = None
for r in range(n):
    d = os.path.join(run, f"runner{r}", "ck")
    fs = {int(m.group(1)) for f in os.listdir(d) if (m := re.match(r"racers_(\d+)\.bin$", f))}
    frames = fs if frames is None else frames & fs
compte = collections.Counter()
premieres = {}
for f in sorted(frames or []):
    dumps = [open(os.path.join(run, f"runner{r}", "ck", f"racers_{f}.bin"), "rb").read() for r in range(n)]
    diffs = set()
    ref = int.from_bytes(dumps[0], "big")
    for r in range(1, n):
        x = (int.from_bytes(dumps[r], "big") ^ ref) & MASQUE
        if x:
            o = x.to_bytes(8 * T, "big")
            diffs.update(i for i in range(8 * T) if o[i])
    if not diffs:
        continue
    mots = sorted({(i // T, (i % T) & ~3) for i in diffs})
    for k, o in mots:
        compte[o] += 1
        premieres.setdefault(o, (f, k, [struct.unpack_from(">I", d, k * T + o)[0] for d in dumps]))
    print(f"frame {f} : {len(mots)} mots, " + " ".join(f"r{k}+{o:X}" for k, o in mots[:16]))
print(f"{len(frames or [])} frames vidées par les {n} runners")
for o, c in sorted(compte.items()):
    f, k, vals = premieres[o]
    print(f"  +0x{o:04X} : {c} fois ; d'abord frame {f}, racer {k} : " + " ".join(f"{v:08X}" for v in vals))
