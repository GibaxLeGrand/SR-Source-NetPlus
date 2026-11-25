"""Planches d'une rafale : <run>/rafale/planche_<k>.png, 10 instants par planche, deux instants par
ligne, les écrans des joueurs côte à côte (j1 | j2 ...), le numéro de capture en haut à gauche.

usage : rafale_planche.py <run> <runners>   (sans -I : PIL est dans le site-packages de l'utilisateur)
"""
import glob
import os
import re
import sys

from PIL import Image, ImageDraw

run, n = sys.argv[1], int(sys.argv[2])
dossier = os.path.join(run, "rafale")
numeros = sorted({re.search(r"_(\d+)\.png$", p).group(1) for p in glob.glob(os.path.join(dossier, "j1_*.png"))})
if not numeros:
    sys.exit("rafale vide")
l, h = Image.open(os.path.join(dossier, f"j1_{numeros[0]}.png")).size
l, h = l * 2 // 3, h * 2 // 3
par_ligne, par_planche, marge = 2, 10, 6
for k in range(0, len(numeros), par_planche):
    lot = numeros[k:k + par_planche]
    lignes = (len(lot) + par_ligne - 1) // par_ligne
    planche = Image.new("RGB", (par_ligne * (n * l + marge), lignes * h), (40, 40, 40))
    d = ImageDraw.Draw(planche)
    for j, num in enumerate(lot):
        x0, y0 = (j % par_ligne) * (n * l + marge), (j // par_ligne) * h
        for r in range(n):
            p = os.path.join(dossier, f"j{r + 1}_{num}.png")
            if os.path.exists(p):
                planche.paste(Image.open(p).convert("RGB").resize((l, h)), (x0 + r * l, y0))
            if r:
                d.line([(x0 + r * l, y0), (x0 + r * l, y0 + h)], fill=(255, 230, 0), width=2)
        d.text((x0 + 4, y0 + 2), num, fill=(255, 230, 0))
    planche.save(os.path.join(dossier, f"planche_{k // par_planche}.png"))
print(f"planches : {(len(numeros) + par_planche - 1) // par_planche} ({len(numeros)} instants)")
