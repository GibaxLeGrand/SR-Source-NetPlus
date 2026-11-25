"""compte_taches.py <taches_rel.txt> <dump>... : pour chaque fonction de tâche du REL, le nombre de mots égaux à
son adresse dans chaque dump de MEM1 (lo), hors du code du REL (0x803FBD00-0x805A0000) ; seules les
fonctions dont le compte change d'un dump à l'autre sont listées."""
import sys
import collections

taches = collections.defaultdict(list)
for l in open(sys.argv[1]):
    site, f = l.split()
    taches[int(f, 16)].append(int(site, 16))
dumps = [open(p, "rb").read() for p in sys.argv[2:]]
comptes = {}
for f in taches:
    motif = f.to_bytes(4, "big")
    c = []
    for d in dumps:
        n, o = 0, d.find(motif)
        while o != -1:
            if o % 4 == 0 and not (0x003FBD00 <= o < 0x005A0000):
                n += 1
            o = d.find(motif, o + 1)
        c.append(n)
    comptes[f] = c
for f, c in sorted(comptes.items()):
    if len(set(c)) > 1:
        print(f"{f:08X}  {' '.join(f'{n:3d}' for n in c)}   créée en {' '.join(f'{s:08X}' for s in taches[f][:4])}")
