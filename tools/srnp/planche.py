"""planche.py <sortie.png> <image>... : les images côte à côte (560 px de large chacune), 3 par ligne."""
import sys
from PIL import Image, ImageDraw

sortie, chemins = sys.argv[1], sys.argv[2:]
w = 560
tuiles = []
for p in chemins:
    im = Image.open(p).convert("RGB")
    tuiles.append(im.resize((w, int(w * im.size[1] / im.size[0]))))
h = max(t.size[1] for t in tuiles)
cols = min(3, len(tuiles))
c = Image.new("RGB", (w * cols, h * ((len(tuiles) + cols - 1) // cols)))
for i, (t, p) in enumerate(zip(tuiles, chemins)):
    x, y = (i % cols) * w, (i // cols) * h
    c.paste(t, (x, y))
    ImageDraw.Draw(c).text((x + 6, y + 22), p.replace("\\", "/").rsplit("/", 1)[-1], fill=(255, 255, 0))
c.save(sortie)
