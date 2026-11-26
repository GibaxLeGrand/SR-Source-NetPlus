"""absolus.py <rel_disasm.txt> <adresse> [<adresse> ...] : les instructions du REL qui adressent une adresse
absolue (ou une plage « debut-fin ») par lis puis addi/lbz/lwz/stb/... sur le même registre, ou par
addis/ori. Suivi simple : la dernière valeur lis de chaque registre, oubliée à chaque prologue (stwu r1),
blr ou réécriture du registre. Sortie : adresse de l'instruction, instruction, adresse visée."""
import sys
import re

cibles = []
for c in sys.argv[2:]:
    if "-" in c:
        a, b = c.split("-")
        cibles.append((int(a, 16), int(b, 16)))
    else:
        cibles.append((int(c, 16), int(c, 16) + 1))

def vise(x):
    return any(a <= x < b for a, b in cibles)

lis = {}
for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
    m = re.match(r"^([0-9A-F]{8}): (\S+)\s*(.*)$", l.strip())
    if not m:
        continue
    a, op, args = int(m.group(1), 16), m.group(2), m.group(3)
    if op == "stwu" and args.endswith("(r1)") or op in ("blr", "bctr"):
        lis = {}
        continue
    p = [x.strip() for x in args.split(",")]
    if op == "lis" and len(p) == 2:
        lis[p[0]] = (int(p[1]) & 0xFFFF) << 16
        continue
    if op in ("addi", "addic") and len(p) == 3 and p[1] in lis:
        x = (lis[p[1]] + int(p[2])) & 0xFFFFFFFF
        if vise(x):
            print(f"{a:08X}  {op} {args}  -> {x:08X}")
        if p[0] != p[1]:
            lis.pop(p[0], None)
        else:
            lis.pop(p[0], None)
        continue
    mm = re.match(r"^(\w+), (-?\d+)\((r\d+)\)$", args)
    if mm and mm.group(3) in lis:
        x = (lis[mm.group(3)] + int(mm.group(2))) & 0xFFFFFFFF
        if vise(x):
            print(f"{a:08X}  {op} {args}  -> {x:08X}")
        if op.startswith("l") and not op.startswith("lf") and mm.group(1) != mm.group(3):
            lis.pop(mm.group(1), None)
        continue
    if p and p[0] in lis and not op.startswith("st") and not op.startswith("cmp"):
        lis.pop(p[0], None)
