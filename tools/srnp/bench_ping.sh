#!/usr/bin/env bash
# SR-Source Net Plus : le « delay based » sous un ping simulé (SRNP_RELAY_PING), deux launchers sur ce PC.
# Chaque essai : test_online.sh (hôte HOTE, ami AMI avec des entrées de test variées, course à 8 sur Metal City),
# le ping sur le siège de l'ami ; bilan : images/s au relais (frames 601 -> 1801), entrées en retard par siège,
# sommes de contrôle, attente moyenne des jeux. Muet (game_volume=0, musique 0).
#   bench_ping.sh "<ping>/<délai>" ...   (défaut : 0/2 60/2 120/2 200/2 120/8)
set -uo pipefail
L=/d/_SonicRidersSource/work/launcher_online
ESSAIS=("${@:-}"); [[ -z "${ESSAIS[0]:-}" ]] && ESSAIS=(0/2 60/2 120/2 200/2 120/8)
BILAN="$L/bench_ping_$(date +%Y%m%d-%H%M%S).txt"
for e in "${ESSAIS[@]}"; do
  ping=${e%/*}; delai=${e#*/}
  for i in $(seq 1 360); do
    n=$(tasklist.exe | grep -ciE "moderngekko|SR-Source")
    if [[ "$n" == 0 ]]; then sleep 3; n=$(tasklist.exe | grep -ciE "moderngekko|SR-Source"); [[ "$n" == 0 ]] && break; fi
    sleep 5
  done
  p=""; [[ "$ping" != 0 ]] && p="1=$ping~$(( ping / 10 ))"
  PING="$p" RULES="1/1/8/$delai" INPUT_B=course DUREE=95 bash "$L/test_online.sh" > "$L/bench_ping_dernier.out" 2>&1
  run=$(grep -o 'RUN=.*' "$L/bench_ping_dernier.out" | tail -1 | cut -d= -f2)
  log="$run/pcA/sr-source/Logs/relay.log"
  "/c/Program Files/Python313/python.exe" -I - "$(cygpath -w "$log")" "$ping" "$delai" "$(cygpath -w "$run")" >> "$BILAN" <<'PY'
import re, sys, glob, os
log, ping, delai, run = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
t = {}
late = ck = div = None
for l in open(log, encoding="utf-8", errors="replace"):
    m = re.match(r"\s*([\d.]+) frame (\d+) closed; (\d+) frames, (\d+) late inputs replaced; checksums: (\d+) identical, (\d+) divergences", l)
    if m:
        t[int(m.group(2))] = float(m.group(1)); late, ck, div = int(m.group(4)), int(m.group(5)), int(m.group(6))
    m = re.search(r"late inputs \(by seat: ([\d,]+)\), checksums: (\d+) identical, (\d+) divergences", l)
    if m:
        par_siege = m.group(1); ck, div = int(m.group(2)), int(m.group(3))
fps = (1800 - 600) / (t[1801] - t[601]) if 601 in t and 1801 in t else float("nan")
attentes = []
for f in sorted(glob.glob(os.path.join(run, "pc?", "sr-source", "Logs", "ModernGekko.log"))):
    w = re.findall(r"waited ([\d.]+) ms a frame on average, ([\d.]+) at most", open(f, encoding="utf-8", errors="replace").read())
    attentes.append(w[-1] if w else ("?", "?"))
print(f"ping {ping:>3} ms, délai {delai} frames : {fps:5.1f} images/s au relais ; entrées en retard : {late} "
      f"(par siège {locals().get('par_siege', '?')}) ; sommes : {ck} identiques, {div} divergences ; attente moyenne/max "
      f"des jeux (ms) : {attentes} ; {os.path.basename(run)}")
PY
  tail -1 "$BILAN"
done
echo "BILAN=$BILAN"
