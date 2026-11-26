"""L'encodeur LZSS d'origine de Sonic Riders, retrouvé le 26/11 (session de la phase 2) : glouton, la copie
la plus longue (2..255 octets, distance 1..255, chevauchement permis), à égalité la plus proche ; sinon
un octet brut. Il redonne le GTSE de Tournament Edition octet pour octet (TE refuse le flux de
compresse_opt.py, que le jeu US accepte)."""
import struct, sys
import numpy as np
sys.path.insert(0, r'D:\_SonicRidersSource\work\etiquettes')
from compresse_opt import plus_longues  # la plus longue copie à chaque position, la plus proche à égalité

def compresse(data):
    lmax, dist = plus_longues(data)
    out = bytearray(b'\x80\x00\x00\x01' + struct.pack('>I', len(data)) + bytes(0x18))
    cur = nb = 0
    def put(v, w):
        nonlocal cur, nb
        for b in range(w - 1, -1, -1):
            cur = (cur << 1) | ((v >> b) & 1); nb += 1
            if nb == 8:
                out.append(cur); cur = nb = 0
    i, n = 0, len(data)
    while i < n:
        l = int(lmax[i])
        if l >= 2:
            put(1, 1); put(int(dist[i]), 8); put(l, 8); i += l
        else:
            put(0, 1); put(data[i], 8); i += 1
    if nb:
        out.append(cur << (8 - nb))
    return bytes(out)

if __name__ == '__main__':
    from lzss_riders import decompresse
    orig = open(sys.argv[1], 'rb').read()
    data = decompresse(orig)
    c = compresse(data)
    print('taille', len(c), 'original', len(orig), 'identique' if c == orig[:len(c)] and len(c) == len(orig) else 'DIFFÉRENT')
    if c != orig:
        k = next((i for i, (a, b) in enumerate(zip(c, orig)) if a != b), min(len(c), len(orig)))
        print('premier octet différent', hex(k))
