"""Écrit le fichier de réponse d'une règle de lien de build.ninja (CMake), comme ninja le ferait.
usage: python -I rsp_lien.py <build.ninja> <sortie cible, ex. moderngekko-run.exe> <sortie.rsp> [newline]
  newline : $in séparés par des retours à la ligne ($in_newline, règle des .exe MSVC) ; sinon espaces."""
import sys

def unesc(s):
    return s.replace("$:", ":").replace("$ ", " ").replace("$$", "$")

text = open(sys.argv[1], encoding="utf-8").read()
lines = text.split("\n")
target = sys.argv[2]
for i, l in enumerate(lines):
    if l.startswith("build " + target + " ") or l.startswith("build " + target + ":"):
        break
else:
    sys.exit("règle de lien introuvable pour " + target)
rest = l.split(":", 1)[1] if not l.startswith("build " + target + " ") else l
# la liste des entrées suit le nom de la règle, jusqu'à « | » (dépendances implicites)
after_rule = l.split("_LINKER__", 1)[1].split(" ", 1)[1]
ins = [unesc(x) for x in after_rule.split(" | ", 1)[0].split(" || ", 1)[0].split()]
var = {}
for l2 in lines[i + 1:]:
    if not l2.startswith("  "):
        break
    k, _, v = l2.strip().partition(" = ")
    var[k] = v
sep = "\n" if len(sys.argv) > 4 and sys.argv[4] == "newline" else " "
out = sep.join(ins) + " " + var.get("LINK_PATH", "") + " " + var.get("LINK_LIBRARIES", "")
open(sys.argv[3], "w", encoding="utf-8").write(out)
print(f"{len(ins)} entrées ; LINK_FLAGS = {var.get('LINK_FLAGS', '')} ; COMPILE = {var.get('LANGUAGE_COMPILE_FLAGS', '')}")
