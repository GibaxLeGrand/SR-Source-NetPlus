"""Compare les racers vidés (SRNP_CKDUMP) de deux runs, runner par runner (même frame).

python -I compare_ab.py <run A> <run B> [runner] [--tout]
Pour chaque frame vidée par les deux : les mots des racers qui diffèrent (hors champs de caméra connus,
sauf --tout), la première frame d'écart par champ, et si les positions (+0x1E4) diffèrent.
"""
import collections
import os
import re
import struct
import sys

T = 0x1080
CAMERA = [(0x370, 0x394), (0x8B4, 0x8B8), (0x8C0, 0x8C4), (0xDC4, 0xE74), (0xFD8, 0xFDC), (0x1000, 0x1004),
          (0x1036, 0x1037), (0x105C, 0x1060)]

args = [a for a in sys.argv[1:] if not a.startswith("--")]
tout = "--tout" in sys.argv
a, b = args[0], args[1]
r = args[2] if len(args) > 2 else "0"


def frames(run):
    d = os.path.join(run, f"runner{r}", "ck")
    return {int(m.group(1)) for f in os.listdir(d) if (m := re.match(r"racers_(\d+)\.bin$", f))}


communes = sorted(frames(a) & frames(b))
premier = {}
compte = collections.Counter()
pos = None
for f in communes:
    x = open(os.path.join(a, f"runner{r}", "ck", f"racers_{f}.bin"), "rb").read()
    y = open(os.path.join(b, f"runner{r}", "ck", f"racers_{f}.bin"), "rb").read()
    for k in range(8):
        for o in range(0, T, 4):
            i = k * T + o
            if x[i:i + 4] != y[i:i + 4]:
                if not tout and any(lo <= o < hi for lo, hi in CAMERA):
                    continue
                compte[(k, o)] += 1
                premier.setdefault((k, o), (f, struct.unpack_from(">I", x, i)[0], struct.unpack_from(">I", y, i)[0]))
        if pos is None and x[k * T + 0x1E4:k * T + 0x1F0] != y[k * T + 0x1E4:k * T + 0x1F0]:
            pos = (f, k)
print(f"{len(communes)} frames communes ; positions : " + (f"différentes dès la frame {pos[0]} (racer {pos[1]})" if pos else "identiques partout"))
for (k, o), n in sorted(premier.items(), key=lambda kv: kv[1][0]):
    f, va, vb = premier[(k, o)]
    print(f"  racer {k} +0x{o:04X} : {compte[(k, o)]:3d} fois, d'abord frame {f} : {va:08X} / {vb:08X}")
