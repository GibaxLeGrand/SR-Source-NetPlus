"""Compare les écarts du vérificateur lockstep (STATICRECOMP_LOCKSTEP=1) de deux runs.
usage: python -I compare_lockstep.py <run_a> <run_b>
Un écart = (entrée, fin, contenu) sans son numéro d'ordre. Affiche les résumés ; les écarts identiques ;
les points d'entrée en écart des deux côtés ou d'un seul ; la nature des écarts (champs touchés) de
chaque côté. Les valeurs lues dans le temps (base de temps, nombre d'écritures MMIO) changent dès que la
chronologie change : le texte exact ne se compare qu'entre deux runs de même chronologie."""
import collections
import re
import sys
from pathlib import Path

RX = re.compile(r"\[lockstep\] DIVERGE #\d+ entry=(0x[0-9A-F]+) end=(0x[0-9A-F]+): (.*)$")
CHAMP = re.compile(r"(\w+(?:\[\d+\])?#?):N=")


def lire(run):
    ecarts, resume, alerte = {}, "", False
    for line in (Path(run) / "runner.log").read_text(errors="replace").splitlines():
        m = RX.search(line)
        if m:
            ecarts.setdefault(m.group(1), []).append((m.group(2), m.group(3).strip()))
        elif "[lockstep] summary" in line:
            resume = line.strip()
        elif line.startswith("alert:"):
            alerte = True
    return ecarts, resume, alerte


def nature(contenu):
    champs = set()
    for c in CHAMP.findall(contenu):
        if c.startswith("ps1_"):
            champs.add("ps1")
        elif re.fullmatch(r"f\d+", c):
            champs.add("fpr")
        elif re.fullmatch(r"r\d+", c):
            champs.add("gpr")
        elif c.startswith("mmio"):
            champs.add("mmio")
        else:
            champs.add(c)
    return "+".join(sorted(champs)) or "?"


a, ra, aa = lire(sys.argv[1])
b, rb, ab = lire(sys.argv[2])
print("a :", ra or "(pas de résumé : run interrompu)", "(alerte)" if aa else "")
print("b :", rb or "(pas de résumé : run interrompu)", "(alerte)" if ab else "")
ta = {(e, f, c) for e, l in a.items() for f, c in l}
tb = {(e, f, c) for e, l in b.items() for f, c in l}
print(f"écarts : a {len(ta)}, b {len(tb)}, identiques au texte près {len(ta & tb)}")
ea, eb = set(a), set(b)
print(f"points d'entrée en écart : a {len(ea)}, b {len(eb)}, communs {len(ea & eb)}, "
      f"seulement a {len(ea - eb)}, seulement b {len(eb - ea)}")
for nom, d in (("a", a), ("b", b)):
    n = collections.Counter(nature(c) for l in d.values() for _, c in l)
    print(f"nature des écarts, {nom} : " + ", ".join(f"{k} {v}" for k, v in n.most_common(12)))
for nom, seul, d in (("a", ea - eb, a), ("b", eb - ea, b)):
    if seul:
        n = collections.Counter(nature(c) for e in seul for _, c in d[e])
        print(f"seulement dans {nom} ({len(seul)} entrées) : " + ", ".join(f"{k} {v}" for k, v in n.most_common(10)))
        for e in sorted(seul)[:15]:
            for f, c in d[e][:1]:
                print(f"    {e} -> {f}: {c[:150]}")
