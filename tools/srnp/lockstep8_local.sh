#!/usr/bin/env bash
# Phase 2, prototype : 8 sièges pilotent les 8 racers d'une vraie course, sur N runners de ce poste
# (N = 8 : un siège chacun ; N = 4 : deux sièges chacun), en lockstep par le relais.
#   lockstep2.sh <runners> natif|jit [frame de capture] [frame de fin]
# Tous chargent le state du départ (Metal City, 1 tour, 1P + 7 CPU) ; SRNP_RACERS=1 : le siège k
# conduit le racer k par une structure manette remplie comme le jeu le fait ; entrées de test
# SRNP_INPUT=course:1 (tout droit, direction au hasard, puis l'IA reprend le racer, à un moment
# différent pour chaque siège) ; la caméra de chaque runner suit son premier siège. Le relais compare
# une somme des 8 racers (sans les champs qui suivent la caméra) toutes les 60 frames.
# Pause exacte de tous à la frame de capture (capture d'écran de chacun), puis à la frame de fin :
# MEM1 lue et comparée au runner 0 (racers et BSS de _Main.rel).
# Env : DELAI_MS (relais, 100), VITESSE (EmulationSpeed, 0.0 = libre), RUNNER (exe), ETIQUETTE.
set -uo pipefail
N="${1:?runners}"; MODE="${2:?natif ou jit}"; CAPT="${3:-10800}"; FIN="${4:-14400}"
SIEGES="${SIEGES:-8}"; K=$((SIEGES / N))
# REPARTITION="0,1 2 3 4 5 6 7" : les sièges de chaque runner (N = nombre de groupes).
GROUPES=(${REPARTITION:-}); (( ${#GROUPES[@]} )) && N=${#GROUPES[@]}
W=/d/_SonicRidersSource/work
CHASSIS=/d/_SonicRidersSource/SR-Source-NetPlus/build/chassis
PY="/c/Program Files/Python313/python.exe"
RELAIS=/d/_SonicRidersSource/SR-Source-NetPlus/tools/srnp/relais.py
STATE="${ETAT:-$W/states/gxee8p_course8cpu_metal_1tour_jit.sav}"
RUN="$W/runs/$(date +%Y%m%d-%H%M%S)-lockstepn-$N-$MODE${ETIQUETTE:+-$ETIQUETTE}"
mkdir -p "$RUN"
w() { cygpath -w "$1"; }
bash "$W/scripts/run/attendre_poste.sh" "${ATTENTE_MAX:-1800}" > "$RUN/poste.txt" || { echo "!! poste occupé"; exit 3; }
bash "$W/scripts/run/poser.sh" runner "${RUNNER:-$W/phase2/moderngekko-run_p2.exe}" || exit 1

"$PY" -I "$RELAIS" --sieges "$SIEGES" --delai-ms "${DELAI_MS:-100}" --journal "$(w "$RUN/relais.log")" > "$RUN/relais.out" 2>&1 &
RPID=$!
sleep 1
PIDS=()
cd "$CHASSIS" || exit 2
for r in $(seq 0 $((N - 1))); do
  D="$RUN/runner$r"; A="$D/auto"
  mkdir -p "$A/commands"
  cp -a "$W/userdir_modele" "$D/userdir"
  sed -i "s/^\[Core\]\$/[Core]\nEmulationSpeed = ${VITESSE:-0.0}/" "$D/userdir/Config/Dolphin.ini"
  # Pas de fenêtre d'alerte (elle bloquerait le runner) : le message reste dans runner.log.
  sed -i 's/^\[Interface\]$/[Interface]\nUsePanicHandlers = False/' "$D/userdir/Config/Dolphin.ini"
  # PORTS=<n> : des manettes standard sur les ports 1 à n-1 aussi (une course 2P en a besoin).
  for p in $(seq 1 $(( ${PORTS:-1} - 1 ))); do
    sed -i "s/^\[Core\]\$/[Core]\nSIDevice$p = 6/" "$D/userdir/Config/Dolphin.ini"
  done
  mkdir -p "$D/ck"
  SEATS=${GROUPES[$r]:-$(seq -s, $((r * K)) $((r * K + K - 1)))}
  printf 'command=pad_frames\nport=3\nframes=1\npause_at=%s\n' "$CAPT" > "$A/commands/00_capt.txt"
  ARGS=(--game "$(w "$W/games/GXEE8P")" --user-dir "$(w "$D/userdir")" --automation-dir "$(w "$A")"
        --mute --load-state "$(w "$STATE")")
  # HD="0 1 2 3" (ou all) : ces runners-là chargent le pack de textures HD (work\textures\pack_hd), en
  # deux mods (Gigapixel AI, puis Waifu Caffe qui gagne sur les doublons), par des jonctions.
  if [[ " ${HD:-} " == *" $r "* || "${HD:-}" == all ]]; then
    # RES=1920x1080 (ou 1280x720, 2560x1440…) : la résolution interne de ces runners-là.
    [[ -n "${RES:-}" ]] && sed -i "s/^resolution=.*/resolution=$RES/" "$D/userdir/config.ini"
    P="$W/textures/pack_hd/Vanilla(ECT_Optimized)"
    for m in "hd_gigapixel:Gigapixel AI" "hd_waifu:Waifu Caffe (Denoise & Magnify)"; do
      id="${m%%:*}"; src="${m#*:}"
      mkdir -p "$D/userdir/Mods/$id"
      printf 'name=%s\ngame=GXEE8P\n' "$id" > "$D/userdir/Mods/$id/mod.ini"
      # (cmd mklink /J : Git Bash change /J en chemin ; PowerShell s'en sort, & et () compris.)
      powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(w "$D/userdir/Mods/$id/textures")' -Target '$(w "$P/$src")' | Out-Null"
      printf 'mod=%s\n' "$id" >> "$D/userdir/config.ini"
    done
  else
    ARGS+=(--no-mods)
  fi
  if [[ "$MODE" == "natif" ]]; then
    ARGS+=(--module "$(w "$CHASSIS/gGXEE8P_recomp.dll")"); export MODERNGEKKO_STATICRECOMP=1
  else export MODERNGEKKO_STATICRECOMP=0; fi
  SRNP_RELAY=127.0.0.1:7845 SRNP_SEAT=$SEATS SRNP_SEATS=$SIEGES SRNP_RACERS=1 SRNP_INPUT="${ENTREES:-course:1}" SRNP_CHECK=${CHECK:-60} SRNP_CKDUMP="$(w "$D/ck")" \
    ./moderngekko-run.exe "${ARGS[@]}" > "$D/runner.log" 2>&1 &
  PIDS+=($!)
  echo "runner $r : sièges $SEATS"
done
attend() {  # attend <commande> <limite s>
  local T0=$SECONDS
  for r in $(seq 0 $((N - 1))); do
    A="$RUN/runner$r/auto"
    while [[ ! -f "$A/processed/$1.txt" && ! -f "$A/failed/$1.txt" ]]; do
      kill -0 "${PIDS[$r]}" 2>/dev/null || { echo "!! runner $r sorti"; break; }
      (( SECONDS - T0 > $2 )) && { echo "!! runner $r : $1 pas fait en $2 s"; break; }
      sleep 0.2
    done
  done
  echo "$1 : fait par tous en $((SECONDS - T0)) s"
}
attend 00_capt 1200
for r in $(seq 0 $((N - 1))); do
  A="$RUN/runner$r/auto"
  printf 'command=screenshot\npath=%s\n' "$(w "$RUN/runner$r/vue.png")" > "$A/commands/01_vue.txt"
  printf 'command=resume\n' > "$A/commands/02_reprise.txt"
  printf 'command=pad_frames\nport=3\nframes=1\npause_at=%s\n' "$FIN" > "$A/commands/03_fin.txt"
done
attend 03_fin 1200
for r in $(seq 0 $((N - 1))); do
  A="$RUN/runner$r/auto"
  printf 'command=read_memory\naddress=0x80000000\nsize=16777216\npath=%s\n' "$(w "$RUN/runner$r/mem1_lo.bin")" > "$A/commands/04_lo.txt"
  printf 'command=read_memory\naddress=0x81000000\nsize=8388608\npath=%s\n' "$(w "$RUN/runner$r/mem1_hi.bin")" > "$A/commands/05_hi.txt"
done
attend 05_hi 120
# Une capture de chacun à la fin (prise à la reprise), quelques frames plus loin.
for r in $(seq 0 $((N - 1))); do
  A="$RUN/runner$r/auto"
  printf 'command=screenshot\npath=%s\n' "$(w "$RUN/runner$r/fin.png")" > "$A/commands/06_capt.txt"
  printf 'command=resume\n' > "$A/commands/07_reprise.txt"
  printf 'command=pad_frames\nport=3\nframes=1\npause_at=%s\n' "$((FIN + 5))" > "$A/commands/08_fin2.txt"
done
attend 08_fin2 120
for r in $(seq 0 $((N - 1))); do printf 'command=stop\n' > "$RUN/runner$r/auto/commands/99_stop.txt"; done
for p in "${PIDS[@]}"; do
  for i in $(seq 1 30); do kill -0 "$p" 2>/dev/null || break; sleep 1; done
  kill -0 "$p" 2>/dev/null && taskkill //F //T //PID "$p" > /dev/null 2>&1
done
taskkill //F //T //PID "$RPID" > /dev/null 2>&1; kill "$RPID" 2>/dev/null
for r in $(seq 0 $((N - 1))); do
  echo "runner $r : $(grep -h "srnp relay\] seat\|srnp racers\|paused at\|waited" "$RUN/runner$r/runner.log" | tr '\n' ' ' | cut -c1-600)"
done
tail -3 "$RUN/relais.out"
"$PY" -I "$W/phase2/compare_racers.py" "$RUN" "$N"; "$PY" -I "$W/phase2/compare_ck.py" "$RUN" "$N" | tail -3
echo "RUN=$RUN"
