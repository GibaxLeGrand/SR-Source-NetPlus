"""Phase 2.5 : la carte des adresses de Sonic Riders US (GXEE8P, DOL + _Main.rel relogé) vers Tournament
Edition (GXSRTE, tout dans main.dol). Lecture seule des fichiers du jeu (hors dépôt).

python -I carte.py <DOL US combiné> <DOL TE> <dossier srnp_*.cpp> <sortie>

1. Le code : la « forme » de chaque instruction (opcode et registres, sans immédiats ni déplacements) ; des
   ancres (fenêtres de N formes présentes une seule fois de chaque côté), étendues en avant et en arrière
   tant que les formes sont égales : des « suites » US -> TE. Une adresse de code se traduit par sa suite.
2. Les données : dans les suites, les paires lis/addi (ou lis + charge/rangement) et les accès relatifs à
   r13 et r2 donnent des paires d'adresses US -> TE ; une adresse de données se traduit par la base la plus
   proche en dessous (même écart), si elle est assez près.
3. Nos adresses (srnp_*.cpp) : leur traduction, la méthode, et le mot d'origine des deux côtés pour le code.
"""
import bisect
import collections
import os
import re
import struct
import sys


def sections(d):
    offs = struct.unpack(">18I", d[0:72])
    adrs = struct.unpack(">18I", d[72:144])
    tailles = struct.unpack(">18I", d[144:216])
    return [(i < 7, o, a, t) for i, (o, a, t) in enumerate(zip(offs, adrs, tailles)) if t]


class Image:
    def __init__(self, chemin):
        self.d = open(chemin, "rb").read()
        self.secs = sections(self.d)
        self.code = []  # (adresse, mots)
        for texte, o, a, t in self.secs:
            if texte:
                self.code.append((a, list(struct.unpack(f">{t // 4}I", self.d[o:o + t - t % 4]))))

    def mot(self, adresse):
        for _, o, a, t in self.secs:
            if a <= adresse < a + t:
                return struct.unpack(">I", self.d[o + adresse - a:o + adresse - a + 4])[0]
        return None

    def est_code(self, adresse):
        return any(a <= adresse < a + 4 * len(m) for a, m in self.code)


def forme(w):
    op = w >> 26
    if op == 18:  # b, bl
        return w & 0xFC000003
    if op == 16:  # bc
        return w & 0xFFFF0003
    if 7 <= op <= 15 or 24 <= op <= 29 or 32 <= op <= 55:  # immédiat ou déplacement de 16 bits
        return w & 0xFFFF0000
    return w


def r_base(img):
    """r13 et r2 posés par __init_registers : lis rX, hi puis ori/addi rX, rX, lo."""
    out = {}
    for a, mots in img.code:
        for k in range(len(mots) - 1):
            w, x = mots[k], mots[k + 1]
            for r in (13, 2):
                if w >> 16 == (15 << 10 | r << 5) and x >> 16 in ((24 << 10) | (r << 5) | r, (14 << 10) | (r << 5) | r):
                    lo = x & 0xFFFF
                    if x >> 26 == 14 and lo & 0x8000:
                        lo -= 0x10000
                    out.setdefault(r, ((w & 0xFFFF) << 16) + lo & 0xFFFFFFFF)
    return out


def main():
    us_p, te_p, sources, sortie = sys.argv[1:5]
    os.makedirs(sortie, exist_ok=True)
    us, te = Image(us_p), Image(te_p)
    # Les deux codes en une suite de formes (adresse de chaque mot).
    def aplatir(img):
        adrs, formes, mots = [], [], []
        for a, m in img.code:
            for k, w in enumerate(m):
                adrs.append(a + 4 * k)
                formes.append(forme(w))
                mots.append(w)
        return adrs, formes, mots
    ua, uf, um = aplatir(us)
    ta, tf, tm = aplatir(te)
    N = 12
    def index(f):
        ix = collections.defaultdict(list)
        for k in range(len(f) - N):
            ix[tuple(f[k:k + N])].append(k)
        return ix
    iu, it = index(uf), index(tf)
    # Ancres : une fenêtre unique des deux côtés.
    carte = [-1] * len(uf)  # index US -> index TE
    longueur = [0] * len(uf)
    ancres = sorted((ku[0], kt[0]) for cle, ku in iu.items() if len(ku) == 1 for kt in [it.get(cle, [])] if len(kt) == 1)
    print(f"ancres (fenêtre de {N}) : {len(ancres)}")
    suites = []
    vu = bytearray(len(uf))
    for ku, kt in ancres:
        if vu[ku]:
            continue
        a, b = ku, kt
        while a > 0 and b > 0 and uf[a - 1] == tf[b - 1] and ua[a - 1] + 4 == ua[a] and ta[b - 1] + 4 == ta[b]:
            a -= 1
            b -= 1
        n = 0
        while a + n < len(uf) and b + n < len(tf) and uf[a + n] == tf[b + n] and \
                (n == 0 or (ua[a + n] == ua[a + n - 1] + 4 and ta[b + n] == ta[b + n - 1] + 4)):
            n += 1
        suites.append((a, b, n))
        for k in range(n):
            vu[a + k] = 1
            if n > longueur[a + k]:
                carte[a + k], longueur[a + k] = b + k, n
    couverts = sum(1 for x in carte if x >= 0)
    print(f"suites : {len(suites)} ; code US couvert : {couverts}/{len(uf)} mots ({100 * couverts / len(uf):.1f} %)")
    # Les données : paires d'adresses calculées aux mêmes instructions.
    bu, bt = r_base(us), r_base(te)
    print("r13/r2 US :", {k: f"{v:08X}" for k, v in bu.items()}, " TE :", {k: f"{v:08X}" for k, v in bt.items()})
    paires = collections.Counter()
    def simm(w):
        v = w & 0xFFFF
        return v - 0x10000 if v & 0x8000 else v
    for i, j in enumerate(carte):
        if j < 0:
            continue
        w, x = um[i], tm[j]
        op = w >> 26
        ra = (w >> 16) & 31
        # Accès relatifs à r13/r2 (addi, charges, rangements).
        if (op == 14 or 32 <= op <= 55) and ra in (13, 2) and ra in bu and ra in bt:
            paires[(bu[ra] + simm(w) & 0xFFFFFFFF, bt[ra] + simm(x) & 0xFFFFFFFF)] += 1
        # lis rD, hi suivi (dans les 8 mots) d'un addi/charge/rangement sur rD.
        if op == 15 and ra == 0:
            rd = (w >> 21) & 31
            for k in range(1, 9):
                if i + k >= len(um) or carte[i + k] != j + k:
                    break
                w2, x2 = um[i + k], tm[j + k]
                op2 = w2 >> 26
                if (op2 == 14 or 32 <= op2 <= 55 or op2 == 24) and (w2 >> 16) & 31 == rd:
                    lo_u = (w2 & 0xFFFF) if op2 == 24 else simm(w2)
                    lo_t = (x2 & 0xFFFF) if op2 == 24 else simm(x2)
                    paires[(((w & 0xFFFF) << 16) + lo_u & 0xFFFFFFFF, ((x & 0xFFFF) << 16) + lo_t & 0xFFFFFFFF)] += 1
                    break
                if (w2 >> 21) & 31 == rd and op2 not in (36, 37, 38, 44, 45, 52, 53, 54, 55):
                    break  # rD réécrit
    # Une adresse US -> la traduction la plus vue.
    donnees = {}
    for (a, b), n in paires.most_common():
        if a not in donnees:
            donnees[a] = (b, n)
    cles = sorted(donnees)
    print(f"adresses de données appariées : {len(cles)}")
    pos_u = {a: i for i, a in enumerate(ua)}
    def traduire(v):
        if us.est_code(v):
            i = pos_u.get(v)
            if i is not None and carte[i] >= 0:
                j = carte[i]
                return ta[j], f"code, suite de {longueur[i]}", um[i], tm[j]
            return None, "code, pas de suite", us.mot(v), None
        if v in donnees:
            b, n = donnees[v]
            return b, f"donnée exacte ({n} réf.)", None, None
        k = bisect.bisect_right(cles, v) - 1
        if k >= 0 and v - cles[k] <= 0x400:
            b, n = donnees[cles[k]]
            return b + (v - cles[k]), f"donnée : base {cles[k]:08X}+{v - cles[k]:X} ({n} réf.)", None, None
        return None, "donnée sans base proche", None, None
    adresses = collections.OrderedDict()
    for nom in sorted(os.listdir(sources)):
        if not (nom.startswith("srnp_") and nom.endswith((".cpp", ".hpp"))):
            continue
        for num, ligne in enumerate(open(os.path.join(sources, nom), encoding="utf-8", errors="replace"), 1):
            for m in re.finditer(r"0x(8[0-1][0-9A-Fa-f]{6})", ligne):
                adresses.setdefault(int(m.group(1), 16), f"{nom}:{num}")
    compte = collections.Counter()
    lignes = []
    for v, ou in adresses.items():
        b, methode, wu, wt = traduire(v)
        genre = methode.split(",")[0].split(" ")[0]
        compte[(genre, b is not None)] += 1
        mots = ""
        if wu is not None:
            mots = f" US {wu:08X}" + (f" TE {wt:08X}{'' if wu == wt else ' (diffère)'}" if wt is not None else "")
        lignes.append(f"{v:08X} -> {b:08X}  {methode}{mots}  {ou}" if b is not None else f"{v:08X} -> ????????  {methode}{mots}  {ou}")
    out = [f"{len(adresses)} adresses"] + [f"  {n:4d} {g} {'traduites' if ok else 'NON'}" for (g, ok), n in sorted(compte.items())]
    print("\n".join(out))
    open(os.path.join(sortie, "carte.txt"), "w", encoding="utf-8").write("\n".join(out + lignes) + "\n")
    with open(os.path.join(sortie, "suites.txt"), "w") as f:
        for a, b, n in sorted(suites):
            f.write(f"{ua[a]:08X} {ta[b]:08X} {n}\n")
    # La carte finale mot à mot, en plages (US consécutifs -> TE consécutifs).
    with open(os.path.join(sortie, "plages_code.txt"), "w") as f:
        i = 0
        while i < len(carte):
            if carte[i] < 0:
                i += 1
                continue
            j = i + 1
            while j < len(carte) and carte[j] == carte[j - 1] + 1 and ua[j] == ua[j - 1] + 4 and \
                    ta[carte[j]] == ta[carte[j - 1]] + 4:
                j += 1
            f.write(f"{ua[i]:08X} {ta[carte[i]]:08X} {j - i}\n")
            i = j
    with open(os.path.join(sortie, "donnees.txt"), "w") as f:
        for a in cles:
            f.write(f"{a:08X} {donnees[a][0]:08X} {donnees[a][1]}\n")


main()
