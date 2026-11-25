"""racer0_direct.py <rel_disasm.txt> <début> <fin> : dans le code du REL entre <début> et <fin> (hex), chaque
« addi rX, rY, -27584 » (l'adresse du racer 0, 0x80609440) dont rX sert ensuite directement de base à des
lectures (lwz/lbz/lhz/lfs champ(rX)) sans être indexé (add/mulli) dans les 12 instructions qui suivent :
la liste des champs lus. Ce sont les lectures du « joueur » (racer 0) codées en dur."""
import sys
import re

lignes = []
for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
    m = re.match(r"^([0-9A-F]{8}): (\S+)\s*(.*)$", l.strip())
    if m:
        lignes.append((int(m.group(1), 16), m.group(2), m.group(3)))
debut, fin = int(sys.argv[2], 16), int(sys.argv[3], 16)
for i, (a, op, args) in enumerate(lignes):
    if not (debut <= a < fin) or op != "addi" or not args.endswith(", -27584"):
        continue
    rx = args.split(",")[0].strip()
    champs, indexe = [], False
    for a2, op2, args2 in lignes[i + 1:i + 13]:
        if re.search(rf"\b{rx}\b", args2) and op2 in ("add", "mulli", "mullw", "addi") and not args2.startswith(rx):
            indexe = True
        m = re.match(rf"(\w+), (-?\d+)\({rx}\)$", args2)
        if m and op2 in ("lwz", "lbz", "lhz", "lha", "lfs", "lwzu"):
            champs.append(f"{op2} +0x{int(m.group(2)):X}")
        if args2.startswith(rx + ",") and op2 not in ("lwz", "lbz", "lfs", "stw", "stb", "stfs"):
            break  # rX récrit
    if champs and not indexe:
        print(f"{a:08X}  {rx:4}  {' '.join(champs[:8])}")
