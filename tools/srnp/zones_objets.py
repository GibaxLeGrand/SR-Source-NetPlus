"""zones_objets.py <rel_disasm.txt> [-v] : les dessins d'objets qui suivent la zone et les drapeaux du racer 0.

Constat (2026-11-26, course Sonic à l'IA / Knuckles immobile au départ) : chez Knuckles, le portique du départ
n'apparaît que quand Sonic s'en approche. Les fonctions de dessin des objets comparent la zone de l'objet
(un octet) aux 3 zones visibles d'un racer (table 0x80612BD8, 4 octets par racer) et lisent ses drapeaux
(+0xBA8, bit 0x10000000) ; elles le font pour le racer 0 seul, ou dans une boucle sur les vues (de 0 au
nombre de joueurs, 0x8021B8C8 : 1 en course 1P) avec la caméra de la vue.

Dans chaque fonction (de prologue à prologue), un « addi rZ, rY, 0x2BD8 » (rY = lis 0x8061) est retenu si
rZ ne sert qu'à des « lbz rN, k(rZ) » (k = 0..3), plus au plus un « addi rZ, rZ, 4 » (le pas d'une boucle)
quand la fonction charge le nombre de joueurs ; un « addi rR, rY, -0x6BC0 » (racer 0) est retenu si rR ne
sert qu'à « lwz rN, 0xBA8(rR) », plus au plus « addi rR, rR, 0x1080 » (même condition), et seulement dans
une fonction qui a aussi un site de zone retenu. Sortie : « Z|R adresse mot_d_origine registre boucle »."""
import sys
import re

lignes = []
for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
    m = re.match(r"^([0-9A-F]{8}): (\S+)\s*(.*)$", l.strip())
    if m:
        lignes.append((int(m.group(1), 16), m.group(2), m.group(3)))
verbeux = "-v" in sys.argv

# Fonctions : de chaque « stwu r1, -n(r1) » au suivant.
debuts = [i for i, (a, op, args) in enumerate(lignes) if op == "stwu" and args.startswith("r1,")]
debuts.append(len(lignes))

def usages(f, i, reg, fin):
    out = []
    for a, op, args in lignes[i + 1:fin]:
        p = [x.strip() for x in args.split(",")]
        lit = any(re.search(rf"\b{reg}\b", x) for x in p[1:]) or re.search(rf"\({reg}\)", args)
        if op.startswith("st") and p and p[0] == reg:
            lit = True
        if lit:
            out.append((a, op, args))
        if p and p[0] == reg and not op.startswith("st") and not op.startswith("cmp") and op[0] != "b":
            if not (op == "addi" and len(p) == 3 and p[1] == reg):
                break  # réécrit (pas un pas de boucle)
    return out

idx = {a: i for i, (a, op, args) in enumerate(lignes)}

def borne_joueurs(a_pas, d):
    """La boucle dont le pas est en a_pas compare son compteur au nombre de joueurs (0x8021B8C8) ?"""
    i = idx[a_pas]
    for a, op, args in lignes[i - 10:i + 10]:
        if op in ("cmplw", "cmpw"):
            rb = args.split(",")[-1].strip()
            # le dernier chargement de rb avant la boucle, dans la fonction
            for j in range(i, d, -1):
                a2, op2, args2 = lignes[j]
                q = [x.strip() for x in args2.split(",")]
                if q and q[0] == rb and not op2.startswith("st") and not op2.startswith("cmp"):
                    if op2 == "lwz" and args2.endswith("-18232(" + args2.split("(")[-1]):
                        return True
                    m = re.match(r"^\w+, 0\((r\d+)\)$", args2)
                    if op2 == "lwz" and m:
                        ra = m.group(1)
                        for k in range(j - 1, max(d, j - 30), -1):
                            a3, op3, args3 = lignes[k]
                            if args3.startswith(ra + ",") and op3 == "addi" and args3.endswith("-18232"):
                                return True
                            if args3.startswith(ra + ","):
                                break
                    if op2 in ("subi", "addi", "subf", "or") or True:
                        if op2 != "lwz":
                            continue
                    return False
    return False

def mot_addi(args):
    rd, ra, simm = [x.strip() for x in args.split(",")]
    return 0x38000000 | (int(rd[1:]) << 21) | (int(ra[1:]) << 16) | (int(simm) & 0xFFFF)

sorties = []
ecartes = []
for k in range(len(debuts) - 1):
    d, fin = debuts[k], debuts[k + 1]
    nb_joueurs = any(re.search(r"(^|, )-18232(\(|$)", args) for a, op, args in lignes[d:fin]
                     if op in ("lwz", "addi"))
    lis = {}
    zones, racers = [], []
    for i in range(d, fin):
        a, op, args = lignes[i]
        p = [x.strip() for x in args.split(",")]
        if op == "lis" and len(p) == 2:
            lis[p[0]] = p[1] == "-32671"
            continue
        if op == "addi" and len(p) == 3 and lis.get(p[1]) and p[2] in ("11224", "-27584"):
            reg = p[0]
            u = usages(None, i, reg, fin)
            pas = [x for x in u if x[1] == "addi" and x[2].startswith(f"{reg}, {reg},")]
            autres = [x for x in u if x not in pas]
            boucle = len(pas) == 1
            if p[2] == "11224":
                ok = autres and all(x[1] == "lbz" and re.match(rf"^\w+, [0-3]\({reg}\)$", x[2]) for x in autres)
                ok = ok and (not pas or (boucle and pas[0][2].endswith(", 4") and borne_joueurs(pas[0][0], d)))
                (zones if ok else ecartes).append((a, "Z", reg, boucle, u[:4], mot_addi(args)))
            else:
                ok = autres and all(x[1] == "lwz" and x[2].endswith(f"2984({reg})") for x in autres)
                ok = ok and (not pas or (boucle and pas[0][2].endswith(", 4224") and borne_joueurs(pas[0][0], d)))
                if ok:
                    racers.append((a, "R", reg, boucle, u[:4], mot_addi(args)))
        if p and p[0] in lis and op != "lis" and not op.startswith("st") and not op.startswith("cmp"):
            if not (op == "addi" and p[2:] and p[2] in ("11224", "-27584") and p[0] == p[1]):
                lis.pop(p[0], None)
    if zones:
        sorties += zones + racers
mots = {a: None for a, *_ in sorties}
for s in sorties:
    print(f"{s[1]} {s[0]:08X} {s[5]:08X} {s[2]} {'boucle' if s[3] else '-'}")
if verbeux:
    for e in ecartes:
        print("# écarté", f"{e[0]:08X}", e[2], [f"{x[0]:08X} {x[1]} {x[2]}" for x in e[4]])
print(f"# {sum(1 for s in sorties if s[1] == 'Z')} zones, {sum(1 for s in sorties if s[1] == 'R')} racers, "
      f"{len(ecartes)} zones écartées", file=sys.stderr)
