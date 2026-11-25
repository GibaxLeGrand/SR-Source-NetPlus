"""taches_rel.py <dossier des chunks> <sortie.txt> : chaque appel de 0x800E2724 (création de tâche) dans le code
généré du REL, avec la fonction passée dans r3 (lis r3 / addi r3 juste avant), d'après la désassemblée en
commentaire. Sortie : « <site> <fonction> »."""
import sys
import os
import re
import glob

dossier, sortie = sys.argv[1], sys.argv[2]
ligne = re.compile(r"^\s*// ([0-9A-F]{8}): (\S+)\s+(.*)$")
instr = {}
for p in glob.glob(os.path.join(dossier, "*.c")):
    for l in open(p, encoding="utf-8", errors="replace"):
        m = ligne.match(l)
        if m:
            instr[int(m.group(1), 16)] = (m.group(2), m.group(3).strip())
res = []
for a in sorted(instr):
    op, args = instr[a]
    if op != "bl" or args != "0x800E2724":
        continue
    hi = lo = None
    for k in range(1, 12):
        p = instr.get(a - 4 * k)
        if not p:
            break
        o, x = p
        if o == "addi" and x.startswith("r3, r3,") and lo is None:
            lo = int(x.split(",")[2])
        if o == "lis" and x.startswith("r3,") and hi is None:
            hi = int(x.split(",")[1])
            break
    if hi is not None:
        f = ((hi << 16) + (lo or 0)) & 0xFFFFFFFF
        res.append((a, f))
with open(sortie, "w") as o:
    for a, f in res:
        o.write(f"{a:08X} {f:08X}\n")
print(len(res), "créations de tâches,", len(set(f for _, f in res)), "fonctions")
