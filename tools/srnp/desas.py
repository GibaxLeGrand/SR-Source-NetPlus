"""Désassembleur du DOL combiné (main.dol + _Main.rel relogé à 0x803FBD00), avec capstone.

python -I desas.py dis <adresse> [n]        : n instructions depuis l'adresse
python -I desas.py fn <adresse>             : la fonction qui contient l'adresse (du prologue au blr final)
python -I desas.py appels <adresse>         : les bl vers cette adresse
python -I desas.py adr <début> <fin>        : les paires lis/addi (ou lis/ori, lis + d(r)) qui visent [début, fin)
python -I desas.py off <décalage> [reg]     : les accès mémoire à ce décalage (d(rX)), dans le texte du REL

Adresses SRR (REL lié à 0x81800000) : retirer 0x01404300.
"""
import os
import struct
import sys

import capstone as cs

DOL = os.environ.get("SRNP_DOL", "D:/_SonicRidersSource/work/combined/sys/main.dol")
d = open(DOL, "rb").read()
SECS = []
for i in range(18):
    off, addr, size = (struct.unpack_from(">I", d, b + 4 * i)[0] for b in (0, 0x48, 0x90))
    if size:
        SECS.append((addr, size, off, i < 7))
TEXT = [(a, s, o) for a, s, o, t in SECS if t]
REL_TEXT = (0x803FBDBC, 0x803FBDBC + 0x1C10DC)

md = cs.Cs(cs.CS_ARCH_PPC, cs.CS_MODE_32 | cs.CS_MODE_BIG_ENDIAN | cs.CS_MODE_PS)
md.detail = False


def word(a):
    for addr, size, off, _ in SECS:
        if addr <= a < addr + size:
            return struct.unpack_from(">I", d, off + a - addr)[0]
    return None


def ins(a):
    w = word(a)
    if w is None:
        return None
    b = struct.pack(">I", w)
    for i in md.disasm_lite(b, a, 1):
        return i[2], i[3]
    return ".word", f"0x{w:08X}"


def fmt(a):
    r = ins(a)
    if r is None:
        return f"{a:08X}: ?"
    m, o = r
    return f"{a:08X}: {word(a):08X}  {m:8s} {o}"


def debut_fn(a):
    """Remonte jusqu'au blr précédent (+4) : approximation du début de fonction."""
    x = a - 4
    while word(x) not in (None, 0x4E800020):
        x -= 4
    return x + 4


def fin_fn(a):
    """Avance jusqu'au blr suivi d'un prologue (stwu r1 / mflr) ou de padding."""
    x = a
    while True:
        w = word(x)
        if w is None:
            return x
        if w == 0x4E800020:
            n = word(x + 4)
            if n is None or n == 0 or (n >> 16) == 0x9421 or n == 0x7C0802A6:
                return x + 4
        x += 4


def textes(rel_seul=False):
    for a, s, o in TEXT:
        if rel_seul and a != REL_TEXT[0]:
            continue
        for x in range(a, a + s, 4):
            yield x, struct.unpack_from(">I", d, o + x - a)[0]


def appels(cible):
    for x, w in textes():
        if (w >> 26) == 18 and (w & 3) == 1:
            li = w & 0x03FFFFFC
            if li & 0x02000000:
                li -= 0x04000000
            if x + li == cible:
                yield x


def s16(v):
    return v - 0x10000 if v & 0x8000 else v


def adresses(lo, hi):
    """lis rX,H suivi (dans les 12 instructions) de addi/ori/d(rX) : adresse H<<16 + bas dans [lo, hi)."""
    hauts = {}
    prec = []
    for x, w in textes():
        op = w >> 26
        if op == 15 and ((w >> 16) & 31) == 0:  # lis rD, imm
            prec.append((x, (w >> 21) & 31, (w & 0xFFFF) << 16))
            prec = prec[-12:]
            continue
        ra = (w >> 16) & 31
        for (xl, rd, h) in prec:
            if ra == rd and x - xl <= 48:
                if op in (14,):  # addi
                    v = (h + s16(w & 0xFFFF)) & 0xFFFFFFFF
                elif op == 24:  # ori
                    v = h | (w & 0xFFFF)
                elif op in (32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55):
                    v = (h + s16(w & 0xFFFF)) & 0xFFFFFFFF
                else:
                    continue
                if lo <= v < hi:
                    yield x, v
                break


def main():
    c = sys.argv[1]
    if c == "dis":
        a = int(sys.argv[2], 16)
        n = int(sys.argv[3]) if len(sys.argv) > 3 else 40
        for i in range(n):
            print(fmt(a + 4 * i))
    elif c == "fn":
        a = int(sys.argv[2], 16)
        b = debut_fn(a)
        e = fin_fn(a)
        print(f"; fonction {b:08X}-{e:08X} ({(e - b) // 4} instructions)")
        for x in range(b, e, 4):
            print(fmt(x))
    elif c == "appels":
        a = int(sys.argv[2], 16)
        for x in appels(a):
            print(f"{x:08X}  (dans {debut_fn(x):08X})")
    elif c == "adr":
        lo, hi = int(sys.argv[2], 16), int(sys.argv[3], 16)
        for x, v in adresses(lo, hi):
            print(f"{x:08X} -> {v:08X}  (dans {debut_fn(x):08X})  {fmt(x)[10:]}")
    elif c == "off":
        o = int(sys.argv[2], 16)
        for x, w in textes(rel_seul=True):
            op = w >> 26
            if 32 <= op <= 55 and (w & 0xFFFF) == o:
                print(fmt(x))


if __name__ == "__main__":
    main()
