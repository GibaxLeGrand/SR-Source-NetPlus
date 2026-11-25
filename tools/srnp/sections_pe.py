"""Compare les sections de deux PE (.exe/.dll) : taille, SHA-256 des octets bruts, nombre d'octets différents.
usage: python -I sections_pe.py <a> <b>"""
import hashlib, struct, sys

def sections(path):
    d = open(path, "rb").read()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    nsec = struct.unpack_from("<H", d, pe + 6)[0]
    opt = struct.unpack_from("<H", d, pe + 20)[0]
    off = pe + 24 + opt
    out = {}
    for i in range(nsec):
        name = d[off:off + 8].rstrip(b"\0").decode()
        vsize, va, rsize, rptr = struct.unpack_from("<IIII", d, off + 8)
        out[name] = (va, vsize, d[rptr:rptr + min(vsize, rsize)])
        off += 40
    return out

a, b = sections(sys.argv[1]), sections(sys.argv[2])
for name in dict.fromkeys(list(a) + list(b)):
    if name not in a or name not in b:
        print(f"{name:8s} seulement dans {'a' if name in a else 'b'}")
        continue
    (va1, s1, x), (va2, s2, y) = a[name], b[name]
    diff = sum(1 for i in range(min(len(x), len(y))) if x[i] != y[i]) if len(x) < 50_000_000 else -1
    same = "IDENTIQUE" if x == y and va1 == va2 else f"{diff} octets différents"
    print(f"{name:8s} va {va1:#x}/{va2:#x} taille {s1}/{s2}  {hashlib.sha256(x).hexdigest()[:16]} {hashlib.sha256(y).hexdigest()[:16]}  {same}")
