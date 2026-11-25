"""empile.py <sortie.png> <planche>... : les planches les unes sous les autres, chacune titrée de son nom."""
import sys
from PIL import Image, ImageDraw

sortie, chemins = sys.argv[1], sys.argv[2:]
ims = [Image.open(p).convert("RGB") for p in chemins]
w = max(im.size[0] for im in ims)
c = Image.new("RGB", (w, sum(im.size[1] for im in ims)))
y = 0
for im, p in zip(ims, chemins):
    c.paste(im, (0, y))
    ImageDraw.Draw(c).text((w - 260, y + 6), p.replace("\\", "/").rsplit("/", 1)[-1], fill=(255, 255, 0))
    y += im.size[1]
c.save(sortie)
