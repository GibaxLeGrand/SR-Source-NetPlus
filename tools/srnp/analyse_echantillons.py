"""Analyse les relevés d'echantillonneur.py : partage du temps par fil, par module, par symbole.

usage: python -I analyse_echantillons.py <préfixe> [--carte NOM_MODULE=chemin.map ...] [--fil TID|auto] [--top N]
  <préfixe> : <préfixe>.bin et <préfixe>.json écrits par l'échantillonneur.
  --carte : carte de symboles (link.exe /MAP ou lld-link /map) d'un module, par nom de fichier.
  Les autres DLL sont résolues par leur table d'exports (fichier sur disque) : « dll!export ».
  --fil auto (défaut) : le fil le plus échantillonné (le fil CPU émulé) ; « tous » : tous les fils.
"""
import bisect
import collections
import json
import os
import re
import struct
import subprocess
import sys

REC = struct.Struct("<IIQQ8Q")
UNDNAME = r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\undname.exe"


def lire_carte(path):
    """Renvoie (rvas triées, noms) d'une carte link.exe/lld-link (sections « Publics by Value » et
    « Static symbols ») : lignes « 0001:000d5860  nom  00000001400d6860 f  lib:obj »."""
    base = None
    syms = {}
    rx = re.compile(r"^\s*([0-9a-fA-F]{4}):([0-9a-fA-F]{8})\s+(\S+)\s+([0-9a-fA-F]{16})\s")
    for line in open(path, encoding="utf-8", errors="replace"):
        if base is None and "Preferred load address is" in line:
            base = int(line.split()[-1], 16)
            continue
        m = rx.match(line)
        if m and base is not None:
            va = int(m.group(4), 16)
            if va >= base:
                syms.setdefault(va - base, m.group(3))
    rvas = sorted(syms)
    return rvas, [syms[r] for r in rvas]


def lire_exports(path):
    """Table d'exports d'un PE sur disque : (rvas triées, noms)."""
    try:
        d = open(path, "rb").read()
    except OSError:
        return [], []
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    magic = struct.unpack_from("<H", d, pe + 24)[0]
    dd = pe + 24 + (112 if magic == 0x20B else 96)
    exp_rva, exp_size = struct.unpack_from("<II", d, dd)
    nsec = struct.unpack_from("<H", d, pe + 6)[0]
    opt = struct.unpack_from("<H", d, pe + 20)[0]
    secs = []
    off = pe + 24 + opt
    for i in range(nsec):
        vsize, va, rsize, rptr = struct.unpack_from("<IIII", d, off + 8)
        secs.append((va, max(vsize, rsize), rptr))
        off += 40

    def r2o(rva):
        for va, sz, rp in secs:
            if va <= rva < va + sz:
                return rp + rva - va
        return None

    if not exp_rva or r2o(exp_rva) is None:
        return [], []
    e = r2o(exp_rva)
    nfun, nnames, afun, aname, aord = struct.unpack_from("<IIIII", d, e + 20)
    funs = [struct.unpack_from("<I", d, r2o(afun) + 4 * i)[0] for i in range(nfun)]
    syms = {}
    for i in range(nnames):
        nrva = struct.unpack_from("<I", d, r2o(aname) + 4 * i)[0]
        o = struct.unpack_from("<H", d, r2o(aord) + 2 * i)[0]
        no = r2o(nrva)
        name = d[no:d.index(b"\0", no)].decode(errors="replace")
        f = funs[o]
        if exp_rva <= f < exp_rva + exp_size:
            continue   # renvoi vers une autre DLL
        syms.setdefault(f, name)
    rvas = sorted(syms)
    return rvas, [syms[r] for r in rvas]


def demangle(names):
    names = [n for n in names if n.startswith("?")]
    out = {}
    if not names or not os.path.exists(UNDNAME):
        return out
    for i in range(0, len(names), 50):
        part = names[i:i + 50]
        try:
            r = subprocess.run([UNDNAME, "0x2"] + part, capture_output=True, text=True, timeout=60)
        except Exception:
            return out
        cur = None
        for line in r.stdout.splitlines():
            if line.startswith("Undecoration of :- "):
                cur = line.split('"')[1] if '"' in line else None
            elif line.startswith("is :- ") and cur:
                out[cur] = line.split('"')[1] if '"' in line else line[6:]
    return out


def main():
    args = sys.argv[1:]
    prefix = args.pop(0)
    cartes = {}
    fil = "auto"
    top = 40
    while args:
        a = args.pop(0)
        if a == "--carte":
            k, v = args.pop(0).split("=", 1)
            cartes[k.lower()] = v
        elif a == "--fil":
            fil = args.pop(0)
        elif a == "--top":
            top = int(args.pop(0))
    meta = json.load(open(prefix + ".json", encoding="utf-8"))
    data = open(prefix + ".bin", "rb").read()
    recs = [REC.unpack_from(data, o) for o in range(0, len(data) - REC.size + 1, REC.size)]
    mods = sorted(meta["modules"], key=lambda m: m["base"])
    bases = [m["base"] for m in mods]
    tables = {}

    def module_de(addr):
        i = bisect.bisect_right(bases, addr) - 1
        if i >= 0 and addr < mods[i]["base"] + mods[i]["size"]:
            return mods[i]
        return None

    def table(m):
        nom = os.path.basename(m["path"]).lower()
        if nom not in tables:
            tables[nom] = lire_carte(cartes[nom]) if nom in cartes else lire_exports(m["path"])
        return tables[nom]

    def resoudre(addr):
        m = module_de(addr)
        if m is None:
            return "(hors module)", "(hors module)"
        nom = os.path.basename(m["path"])
        rvas, names = table(m)
        rva = addr - m["base"]
        i = bisect.bisect_right(rvas, rva) - 1
        sym = names[i] if i >= 0 else f"+0x{rva:x}"
        return nom, sym

    print(f"relevés : {len(recs)} en {meta['duree_s']:.1f} s ({len(recs) / meta['duree_s']:.0f}/s) ; "
          f"échecs de suspension : {meta['echec_suspend']} ; arrêt : {meta['raison']}")
    print("\n== Temps CPU des fils pendant la fenêtre (GetThreadTimes, sans échantillonnage)")
    for f in meta["fils"][:10]:
        print(f"  {f['tid']:6d} {f['nom'][:34]:34s} {f['cpu_s']:7.2f} s ({100 * f['cpu_s'] / meta['duree_s']:5.1f} % d'un cœur, "
              f"noyau {f['noyau_s']:.2f} s)")
    par_fil = collections.Counter(r[0] for r in recs)
    noms = {f["tid"]: f["nom"] for f in meta["fils"]}
    print("\n== Relevés par fil")
    for tid, c in par_fil.most_common(10):
        print(f"  {tid:6d} {noms.get(tid, '')[:34]:34s} {c:7d}")
    if fil == "auto":
        tids = {par_fil.most_common(1)[0][0]}
    elif fil == "tous":
        tids = set(par_fil)
    else:
        tids = {int(fil)}
    sel = [r for r in recs if r[0] in tids]
    print(f"\n== Fil(s) analysé(s) : {', '.join(f'{t} {noms.get(t, "")}' for t in tids)} ; {len(sel)} relevés")
    par_mod = collections.Counter()
    par_sym = collections.Counter()
    appelants = collections.defaultdict(collections.Counter)
    code_mods = {k for k in cartes}
    for r in sel:
        mod, sym = resoudre(r[2])
        par_mod[mod] += 1
        par_sym[(mod, sym)] += 1
        if mod.lower() not in code_mods:
            # indice d'appelant : le premier mot de la pile qui tombe dans un module à carte
            for q in r[4:]:
                mq = module_de(q)
                if mq and os.path.basename(mq["path"]).lower() in code_mods:
                    appelants[(mod, sym)][resoudre(q)] += 1
                    break
    tot = len(sel)
    print("\n-- Par module")
    for mod, c in par_mod.most_common(20):
        print(f"  {100 * c / tot:6.2f} %  {c:7d}  {mod}")
    dem = demangle([s for (_, s) in par_sym])
    print(f"\n-- Par symbole (top {top})")
    for (mod, sym), c in par_sym.most_common(top):
        print(f"  {100 * c / tot:6.2f} %  {c:6d}  {mod}!{dem.get(sym, sym)[:110]}")
    # Regroupement des fonctions PowerPC (module) : func_X et func_X_budget ensemble
    ppc = collections.Counter()
    for (mod, sym), c in par_sym.items():
        m = re.match(r"func_([0-9A-Fa-f]{8})", sym)
        if m and mod.lower() in code_mods:
            ppc[m.group(1).upper()] += c
    if ppc:
        tot_ppc = sum(ppc.values())
        print(f"\n-- Fonctions PowerPC (module), {tot_ppc} relevés = {100 * tot_ppc / tot:.1f} % du fil ; "
              f"{len(ppc)} fonctions vues ; top {top}")
        cum = 0
        for a, c in ppc.most_common(top):
            cum += c
            print(f"  {100 * c / tot:6.2f} %  (cumul {100 * cum / tot:5.1f} %)  0x{a}")
        for k in (10, 50, 100, 500):
            print(f"  les {k} premières : {100 * sum(c for _, c in ppc.most_common(k)) / tot:.1f} % du fil")
    print("\n-- Appelants probables des symboles hors carte (premier mot de pile dans un module à carte)")
    for key, c in par_sym.most_common(top):
        if key in appelants and c >= tot * 0.005:
            mod, sym = key
            print(f"  {mod}!{dem.get(sym, sym)[:80]} ({100 * c / tot:.2f} %) :")
            for (m2, s2), c2 in appelants[key].most_common(4):
                print(f"      {c2:6d}  {m2}!{dem.get(s2, s2)[:90]}")


if __name__ == "__main__":
    main()
