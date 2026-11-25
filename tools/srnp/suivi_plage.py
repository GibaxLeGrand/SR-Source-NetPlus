"""suivi_plage.py <dossier> <base hex> <adresse hex>... : pour chaque adresse (mot de 4 octets), ses valeurs
successives dans les relevés <dossier>/s<NNN>.bin (lus à <base>), avec le numéro du relevé où elle change."""
import sys
import os
import glob

dossier, base = sys.argv[1], int(sys.argv[2], 16)
adresses = [int(a, 16) for a in sys.argv[3:]]
releves = sorted(glob.glob(os.path.join(dossier, "s[0-9][0-9][0-9].bin")))
donnees = [open(p, "rb").read() for p in releves]
for a in adresses:
    o = a - base
    suite = []
    for i, d in enumerate(donnees):
        v = int.from_bytes(d[o:o + 4], "big")
        if not suite or suite[-1][1] != v:
            suite.append((i, v))
    print(f"{a:08X} : " + ", ".join(f"#{i} {v:#x}" for i, v in suite))
