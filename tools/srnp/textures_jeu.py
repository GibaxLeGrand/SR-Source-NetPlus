"""Les textures des fichiers de Sonic Riders (GameCube) : liste, et décodage en PNG pour les regarder.

python textures_jeu.py <fichier du jeu> <dossier de sortie>

Les fichiers sont souvent compressés (LZSS du jeu : en-tête 0x80000001 + taille, puis un flux de bits,
bit de poids fort d'abord ; 0 = octet brut, 1 = distance sur 8 bits puis longueur sur 8 bits). Dedans,
des listes de textures : u16 nombre, u16 drapeaux, u32 décalages (depuis la liste), puis les noms (C,
terminés par 0), puis chaque texture au format GVR de Sega : « GCIX » (16 o), « GVRT » (taille, puis
drapeaux de palette, format, largeur, hauteur), la palette éventuelle, puis les texels en tuiles.
Un fichier peut contenir plusieurs listes : on les cherche toutes (chaque « GCIX » trouvé).

Les PNG sont des données du jeu : à écrire hors des dépôts.
"""
import pathlib
import struct
import sys


def decompresse(src):
    sig, taille = struct.unpack_from(">II", src, 0)
    if sig != 0x80000001:
        return src
    out = bytearray()
    # Le flux en une chaîne de « 0 »/« 1 » : une lecture de bits n'est plus qu'une tranche.
    bits = "".join(format(b, "08b") for b in src[0x20:])
    pos = 0

    def lit(k):
        nonlocal pos
        pos += k
        return int(bits[pos - k:pos], 2)

    while len(out) < taille:
        if lit(1):
            d = lit(8)
            m = lit(8)
            b = len(out) - d
            for i in range(m):
                out.append(out[b + i])
        else:
            out.append(lit(8))
    return bytes(out)


def rgb5a3(v):
    if v & 0x8000:
        return ((v >> 10) & 31) * 255 // 31, ((v >> 5) & 31) * 255 // 31, (v & 31) * 255 // 31, 255
    return ((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17, (v & 15) * 17, ((v >> 12) & 7) * 255 // 7


def rgb565(v):
    return ((v >> 11) & 31) * 255 // 31, ((v >> 5) & 63) * 255 // 63, (v & 31) * 255 // 31, 255


def tuiles(w, h, tw, th):
    for ty in range(0, h, th):
        for tx in range(0, w, tw):
            for y in range(th):
                for x in range(tw):
                    yield tx + x, ty + y


def decode(fmt, w, h, data, palette):
    px = [(0, 0, 0, 0)] * (w * h)
    put = lambda x, y, c: (x < w and y < h) and px.__setitem__(y * w + x, c)
    i = 0
    if fmt == 0x0:  # I4
        for k, (x, y) in enumerate(tuiles(w, h, 8, 8)):
            v = (data[k // 2] >> (4 if k % 2 == 0 else 0)) & 15
            put(x, y, (v * 17,) * 3 + (255,))
    elif fmt == 0x1:  # I8
        for k, (x, y) in enumerate(tuiles(w, h, 8, 4)):
            put(x, y, (data[k],) * 3 + (255,))
    elif fmt == 0x2:  # IA4
        for k, (x, y) in enumerate(tuiles(w, h, 8, 4)):
            v = data[k]
            put(x, y, ((v & 15) * 17,) * 3 + ((v >> 4) * 17,))
    elif fmt == 0x3:  # IA8
        for k, (x, y) in enumerate(tuiles(w, h, 4, 4)):
            a, l = data[2 * k], data[2 * k + 1]
            put(x, y, (l, l, l, a))
    elif fmt == 0x4:  # RGB565
        for k, (x, y) in enumerate(tuiles(w, h, 4, 4)):
            put(x, y, rgb565(struct.unpack_from(">H", data, 2 * k)[0]))
    elif fmt == 0x5:  # RGB5A3
        for k, (x, y) in enumerate(tuiles(w, h, 4, 4)):
            put(x, y, rgb5a3(struct.unpack_from(">H", data, 2 * k)[0]))
    elif fmt == 0x6:  # RGBA8 : AR puis GB, par tuiles de 4x4
        for t, (tx, ty) in enumerate((tx, ty) for ty in range(0, h, 4) for tx in range(0, w, 4)):
            b = t * 64
            for k in range(16):
                a, r = data[b + 2 * k], data[b + 2 * k + 1]
                g, bl = data[b + 32 + 2 * k], data[b + 33 + 2 * k]
                put(tx + k % 4, ty + k // 4, (r, g, bl, a))
    elif fmt in (0x8, 0x9):  # CI4, CI8
        if fmt == 0x9:
            for k, (x, y) in enumerate(tuiles(w, h, 8, 4)):
                put(x, y, palette[data[k]] if data[k] < len(palette) else (255, 0, 255, 255))
        else:
            for k, (x, y) in enumerate(tuiles(w, h, 8, 8)):
                v = (data[k // 2] >> (4 if k % 2 == 0 else 0)) & 15
                put(x, y, palette[v] if v < len(palette) else (255, 0, 255, 255))
    elif fmt == 0xE:  # CMPR
        bloc = 0
        for ty in range(0, h, 8):
            for tx in range(0, w, 8):
                for sy in (0, 4):
                    for sx in (0, 4):
                        c0, c1 = struct.unpack_from(">HH", data, bloc)
                        idx = struct.unpack_from(">I", data, bloc + 4)[0]
                        bloc += 8
                        p0, p1 = rgb565(c0), rgb565(c1)
                        if c0 > c1:
                            p2 = tuple((2 * a + b) // 3 for a, b in zip(p0[:3], p1[:3])) + (255,)
                            p3 = tuple((a + 2 * b) // 3 for a, b in zip(p0[:3], p1[:3])) + (255,)
                        else:
                            p2 = tuple((a + b) // 2 for a, b in zip(p0[:3], p1[:3])) + (255,)
                            p3 = (0, 0, 0, 0)
                        pal = (p0, p1, p2, p3)
                        for k in range(16):
                            put(tx + sx + k % 4, ty + sy + k // 4, pal[(idx >> (30 - 2 * k)) & 3])
    else:
        return None
    return px


def taille_texels(fmt, w, h):
    bpp = {0x0: 4, 0x1: 8, 0x2: 8, 0x3: 16, 0x4: 16, 0x5: 16, 0x6: 32, 0x8: 4, 0x9: 8, 0xE: 4}.get(fmt)
    if bpp is None:
        return None
    tw, th = {4: (8, 8), 8: (8, 4), 16: (4, 4), 32: (4, 4)}[bpp]
    return ((w + tw - 1) // tw * tw) * ((h + th - 1) // th * th) * bpp // 8


def textures(d):
    """Chaque texture GVR du fichier : (décalage, format, largeur, hauteur, palette, texels)."""
    i = d.find(b"GCIX")
    while i >= 0:
        g = i + 0x10
        if d[g:g + 4] == b"GVRT":
            pflags, fmt = d[g + 0xA], d[g + 0xB]
            w, h = struct.unpack_from(">HH", d, g + 0xC)
            p = g + 0x10
            palette = []
            if pflags & 0x08:  # palette dans la texture
                n = struct.unpack_from(">H", d, p + 0xE)[0] if d[p:p + 4] == b"GVPL" else 0
            # Palette des CI8 du jeu : 256 entrées RGB5A3 juste avant les texels (forme vue dans GTSE).
            if fmt in (0x8, 0x9):
                n = 16 if fmt == 0x8 else 256
                kind = pflags >> 4
                for k in range(n):
                    v = struct.unpack_from(">H", d, p + 2 * k)[0]
                    palette.append(rgb5a3(v) if kind in (0, 2) else rgb565(v) if kind == 1 else (v >> 8, v >> 8, v >> 8, v & 255))
                p += 2 * n
            t = taille_texels(fmt, w, h)
            yield i, fmt, w, h, palette, d[p:p + t] if t else b""
        i = d.find(b"GCIX", i + 4)


def noms(d):
    import re
    return [n.decode() for n in re.findall(rb"[A-Za-z][A-Za-z0-9_]{3,31}\x00", d[:0x200])]


def main():
    from PIL import Image
    src = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    d = decompresse(src.read_bytes())
    print(f"{src.name} : {len(d)} octets ; noms en tête : {noms(d)}")
    for k, (off, fmt, w, h, pal, data) in enumerate(textures(d)):
        px = decode(fmt, w, h, data, pal) if 0 < w <= 2048 and 0 < h <= 2048 else None
        nom = f"{src.name}_{k:03d}_{off:x}_{w}x{h}_f{fmt:x}.png"
        print(f"  {k:3d} @{off:#x} {w}x{h} format {fmt:#x}" + ("" if px else " (pas décodé)"))
        if px:
            im = Image.new("RGBA", (w, h))
            im.putdata(px)
            im.save(out / nom)


if __name__ == "__main__":
    main()
