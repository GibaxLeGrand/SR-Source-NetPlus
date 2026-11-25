"""Classe les sites de dispatch (STATICRECOMP_DISPATCH_SAMPLES=1) d'un run.
usage: python -I analyse_sites.py <run> <generated.h> <main.dol combiné>
Pour chaque site : retour après un appel (bl / bctrl / blrl : vers quelle fonction), entrée de
fonction, ou milieu de fonction (cas d'une table de sauts, tête de boucle...). Agrège par fonction."""
import bisect, collections, re, struct, sys
from pathlib import Path

run, gen_h, dol = sys.argv[1:4]
sites = [(int(a, 16), int(n)) for a, n in re.findall(r"dispatch-site pc=([0-9a-f]+) samples=(\d+)",
                                                      Path(run, "runner.log").read_text(errors="replace"))]
funcs = sorted({int(a, 16) for a in re.findall(r"void func_([0-9A-Fa-f]{8})\(CPUState\* ctx\);",
                                                Path(gen_h).read_text(errors="replace"))})
d = open(dol, "rb").read()
secs = []
for i in range(18):
    off, addr, size = (struct.unpack_from(">I", d, base + 4 * i)[0] for base in (0, 0x48, 0x90))
    if size:
        secs.append((addr, size, off))
def word(a):
    for addr, size, off in secs:
        if addr <= a < addr + size:
            return struct.unpack_from(">I", d, off + a - addr)[0]
    return None
def fonction(a):
    i = bisect.bisect_right(funcs, a) - 1
    return funcs[i] if i >= 0 else None
def a_bctr(f):
    i = funcs.index(f)
    fin = funcs[i + 1] if i + 1 < len(funcs) else f + 0x1000
    return any(word(x) == 0x4E800420 for x in range(f, fin, 4))
tot = sum(n for _, n in sites)
classes = collections.Counter()
par_appele = collections.Counter()     # retours : fonction appelée (bl direct) ou « indirect »
par_fonction_milieu = collections.Counter()
par_entree = collections.Counter()
for a, n in sites:
    avant = word(a - 4)
    f = fonction(a)
    if avant is not None and avant >> 26 == 18 and avant & 1:
        li = avant & 0x03FFFFFC
        if li & 0x02000000:
            li -= 0x04000000
        cible = (a - 4 + li) & 0xFFFFFFFF if not avant & 2 else li & 0xFFFFFFFF
        classes["retour d'un bl"] += n
        par_appele[cible] += n
    elif avant in (0x4E800421, 0x4E800021):
        classes["retour d'un bctrl/blrl"] += n
        par_appele["indirect"] += n
    elif f == a:
        classes["entrée de fonction"] += n
        par_entree[a] += n
    else:
        classes["milieu de fonction"] += n
        par_fonction_milieu[f] += n
print(f"{len(sites)} sites, {tot} relevés (1 dispatch sur 4096)")
for k, v in classes.most_common():
    print(f"  {100 * v / tot:5.1f} %  {k}")
print("\nretours : fonctions appelées les plus coûteuses (bctr = table de sauts dedans)")
for c, n in par_appele.most_common(20):
    extra = "" if c == "indirect" else (" bctr" if c in funcs and a_bctr(c) else "")
    print(f"  {100 * n / tot:5.1f} %  {c if c == 'indirect' else f'0x{c:08X}'}{extra}")
print("\nmilieux de fonction, par fonction (bctr = table de sauts dedans)")
for f, n in par_fonction_milieu.most_common(20):
    print(f"  {100 * n / tot:5.1f} %  0x{f:08X}{' bctr' if a_bctr(f) else ''}")
print("\nentrées de fonction (atteintes par le répartiteur)")
for f, n in par_entree.most_common(12):
    print(f"  {100 * n / tot:5.1f} %  0x{f:08X}")
