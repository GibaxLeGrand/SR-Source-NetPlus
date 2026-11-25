"""Rafale de captures : <nombre> commandes screenshot à chaque runner, toutes les <intervalle> s.

usage : rafale.py <run> <runners> <nombre> <intervalle>
Chaque commande est écrite à côté puis déplacée dans auto/commands (jamais lue à moitié), comme
commande() de demo_8.sh ; un seul processus, donc l'intervalle est tenu (la boucle bash coûtait
~0,3 s par capture). Les images : <run>/rafale/j<k>_<n>.png ; le chrono du jeu sur chaque image
donne l'instant exact.
"""
import os
import sys
import time

run, n, nombre, intervalle = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4])
dossier = os.path.join(run, "rafale")
os.makedirs(dossier, exist_ok=True)
largeur = len(str(nombre))
t0 = time.perf_counter()
for i in range(1, nombre + 1):
    for r in range(n):
        auto = os.path.join(run, f"runner{r}", "auto")
        nom = f"s{i:0{largeur}d}"
        image = os.path.join(dossier, f"j{r + 1}_{i:0{largeur}d}.png")
        tmp = os.path.join(auto, nom + ".tmp")
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write(f"command=screenshot\npath={image}\n")
        os.replace(tmp, os.path.join(auto, "commands", nom + ".txt"))
    attente = t0 + i * intervalle - time.perf_counter()
    if attente > 0:
        time.sleep(attente)
print(f"rafale : {nombre} x {n} commandes en {time.perf_counter() - t0:.2f} s")
