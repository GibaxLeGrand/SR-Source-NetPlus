"""Compare les 8 racers (et la BSS de _Main.rel) des runners d'un lockstep de phase 2.

python -I compare_racers.py <run> <runners>
Pour chaque runner : octets des racers qui diffèrent du runner 0 (tous, puis sans les champs qui suivent
la caméra), mots de la BSS de _Main.rel qui diffèrent ; puis l'état des racers du runner 0.
"""
import os
import struct
import sys

BASE = 0x80000000
RACERS, T = 0x80609440, 0x1080
BSS = (0x805FB080, 0x806B5774)
CAMERA = [(0x370, 0x394), (0x8C0, 0x8C4), (0xDC4, 0xE74), (0xFD8, 0xFDC), (0x1000, 0x1004), (0x102C, 0x102D), (0x1036, 0x1037), (0x105C, 0x1060)]


def charge(d):
    return open(os.path.join(d, "mem1_lo.bin"), "rb").read()


def masque(i):
    return any(a <= i % T < b for a, b in CAMERA)


run, n = sys.argv[1], int(sys.argv[2])
mems = []
for r in range(n):
    try:
        mems.append(charge(os.path.join(run, f"runner{r}")))
    except OSError:
        mems.append(None)
ref = mems[0]
if ref is None:
    sys.exit("pas de MEM1 pour le runner 0")
rr = ref[RACERS - BASE:RACERS - BASE + 8 * T]
for r in range(1, n):
    m = mems[r]
    if m is None:
        print(f"runner {r} : pas de MEM1")
        continue
    x = m[RACERS - BASE:RACERS - BASE + 8 * T]
    tous = [i for i in range(8 * T) if x[i] != rr[i]]
    hors = [i for i in tous if not masque(i)]
    bss = sum(1 for a in range(BSS[0], BSS[1], 4) if m[a - BASE:a - BASE + 4] != ref[a - BASE:a - BASE + 4])
    detail = " ".join(f"r{i // T}+{i % T:X}" for i in hors[:12])
    print(f"runner {r} / runner 0 : racers {len(tous)} octets différents, {len(hors)} hors champs de caméra "
          f"{detail} ; BSS de _Main.rel {bss} mots")
fini = ref[0x806129B4 - BASE], ref[0x806129B5 - BASE]
print(f"compteur 0x801AF9F0 : {struct.unpack_from('>I', ref, 0x801AF9F0 - BASE)[0]}, phase de course "
      f"0x{struct.unpack_from('>I', ref, 0x801DFC80 - BASE)[0]:X}, octets 0x806129B4/B5 : {fini}")
for k in range(8):
    b = rr[k * T:(k + 1) * T]
    x, y, z = struct.unpack_from(">fff", b, 0x1E4)
    v = struct.unpack_from(">f", b, 0xAAC)[0] * 216
    print(f"  racer {k} : BC={b[0xBC]} pad={struct.unpack_from('>I', b, 0)[0]:08X} pos=({x:8.1f},{y:7.1f},{z:8.1f}) "
          f"v={v:6.1f} km/h état={b[0x1034]}")
