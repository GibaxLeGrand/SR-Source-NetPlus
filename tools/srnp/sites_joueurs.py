"""sites_joueurs.py <dossier des chunks> : les lectures du nombre de joueurs (0x8021B8C8 : -18232 sous lis
0x8022) proches (8 instructions) d'une lecture de l'indice du racer (lbz ..., 4137(...)), et pour chacune
la première création de tâche (bl 0x800E2724) dans les 80 instructions qui suivent, et l'appel suivant."""
import sys
import os
import re
import glob

ligne = re.compile(r"^\s*// ([0-9A-F]{8}): (\S+)\s*(.*)$")
instr = {}
for p in glob.glob(os.path.join(sys.argv[1], "*.c")):
    for l in open(p, encoding="utf-8", errors="replace"):
        m = ligne.match(l)
        if m:
            instr[int(m.group(1), 16)] = (m.group(2), m.group(3).strip())
for a in sorted(instr):
    op, args = instr[a]
    if "-18232" not in args:
        continue
    pres = [instr.get(a + 4 * k) for k in range(-8, 9)]
    if not any(p and p[0] == "lbz" and "4137(" in p[1] for p in pres):
        continue
    tache = appel = None
    for k in range(1, 81):
        p = instr.get(a + 4 * k)
        if not p:
            break
        if p[0] == "bl" and p[1] == "0x800E2724" and tache is None:
            tache = a + 4 * k
        if p[0] == "bl" and appel is None:
            appel = (a + 4 * k, p[1])
    print(f"{a:08X}  tâche {tache and f'{tache:08X}' or '-':>8}  premier appel {appel and f'{appel[0]:08X} -> {appel[1]}' or '-'}")
