#!/usr/bin/env bash
# Phase 1, prototype : N runners sur ce poste, en lockstep par le relais (tools/srnp/relais.py).
#   lockstep.sh <sièges> natif|jit [pause_at]
# Tous chargent le même state (course de démo), envoient des entrées aléatoires reproductibles
# (SRNP_INPUT=random:<siège+1>) ; le relais ferme chaque frame et compare des sommes de contrôle
# (BSS de _Main.rel) toutes les 60 frames. Pause exacte à la même frame (pad_frames sur le port 3,
# qu'aucun siège ne pilote), MEM1 lue, et comparaison de chaque runner au siège 0.
# Env : DELAI_MS (relais, 100), CADENCE (horloge du relais en frames/s, 0 = sans), VITESSE (EmulationSpeed
#       de tous, 0.0 = libre), LENT=<siège>:<vitesse> (ce runner-là à cette vitesse), RUNNER (exe).
set -uo pipefail
N="${1:?sièges}"; MODE="${2:?natif ou jit}"; PAUSE="${3:-9700}"
W=/d/_SonicRidersSource/work
CHASSIS=/d/_SonicRidersSource/SR-Source-NetPlus/build/chassis
PY="/c/Program Files/Python313/python.exe"
RELAIS=/d/_SonicRidersSource/SR-Source-NetPlus/tools/srnp/relais.py
STATE="$W/states/gxee8p_demo_f8850_jit.sav"
RUN="$W/runs/$(date +%Y%m%d-%H%M%S)-lockstep-$N-$MODE${ETIQUETTE:+-$ETIQUETTE}"
mkdir -p "$RUN"
w() { cygpath -w "$1"; }
bash "$W/scripts/run/attendre_poste.sh" "${ATTENTE_MAX:-1800}" > "$RUN/poste.txt" || { echo "!! poste occupé"; exit 3; }
bash "$W/scripts/run/poser.sh" runner "${RUNNER:-$W/phase1/moderngekko-run_p1_relais.exe}" || exit 1

"$PY" -I "$RELAIS" --sieges "$N" --delai-ms "${DELAI_MS:-100}" --cadence "${CADENCE:-0}" --journal "$(w "$RUN/relais.log")" > "$RUN/relais.out" 2>&1 &
RPID=$!
sleep 1
PIDS=()
cd "$CHASSIS" || exit 2
for s in $(seq 0 $((N - 1))); do
  D="$RUN/siege$s"; A="$D/auto"
  mkdir -p "$A/commands"
  cp -a "$W/userdir_modele" "$D/userdir"
  V="${VITESSE:-0.0}"
  [[ "${LENT:-}" == "$s:"* ]] && V="${LENT#*:}"
  sed -i "s/^\[Core\]\$/[Core]\nEmulationSpeed = $V/" "$D/userdir/Config/Dolphin.ini"
  # Une manette standard (SIDevice = 6) sur chaque port d'un siège, pour que le jeu lise ses entrées.
  for p in $(seq 1 $((N < 4 ? N - 1 : 3))); do
    sed -i "s/^\[Core\]\$/[Core]\nSIDevice$p = 6/" "$D/userdir/Config/Dolphin.ini"
  done
  printf 'command=pad_frames\nport=3\nframes=1\npause_at=%s\n' "$PAUSE" > "$A/commands/00_pause.txt"
  ARGS=(--game "$(w "$W/games/GXEE8P")" --user-dir "$(w "$D/userdir")" --automation-dir "$(w "$A")"
        --no-mods --mute --load-state "$(w "$STATE")")
  if [[ "$MODE" == "natif" ]]; then
    ARGS+=(--module "$(w "$CHASSIS/gGXEE8P_recomp.dll")"); export MODERNGEKKO_STATICRECOMP=1
  else export MODERNGEKKO_STATICRECOMP=0; fi
  SRNP_RELAY=127.0.0.1:7845 SRNP_SEAT=$s SRNP_SEATS=$N SRNP_INPUT="random:$((s + 1))" SRNP_CHECK=60 \
    ./moderngekko-run.exe "${ARGS[@]}" > "$D/runner.log" 2>&1 &
  PIDS+=($!)
done
T0=$SECONDS
for s in $(seq 0 $((N - 1))); do
  A="$RUN/siege$s/auto"
  while [[ ! -f "$A/processed/00_pause.txt" && ! -f "$A/failed/00_pause.txt" ]]; do
    kill -0 "${PIDS[$s]}" 2>/dev/null || { echo "!! siège $s : runner sorti"; break; }
    (( SECONDS - T0 > 1200 )) && { echo "!! siège $s : pas de pause en 1200 s"; break; }
    sleep 0.2
  done
  echo "siège $s en pause après $((SECONDS - T0)) s"
  printf 'command=read_memory\naddress=0x80000000\nsize=16777216\npath=%s\n' "$(w "$RUN/siege$s/mem1_lo.bin")" > "$A/commands/01_lo.txt"
  printf 'command=read_memory\naddress=0x81000000\nsize=8388608\npath=%s\n' "$(w "$RUN/siege$s/mem1_hi.bin")" > "$A/commands/02_hi.txt"
done
echo "pauses en $((SECONDS - T0)) s"
for s in $(seq 0 $((N - 1))); do
  A="$RUN/siege$s/auto"
  for i in $(seq 1 120); do [[ -f "$A/processed/02_hi.txt" || -f "$A/failed/02_hi.txt" ]] && break; sleep 0.5; done
  printf 'command=stop\n' > "$A/commands/99_stop.txt"
done
for p in "${PIDS[@]}"; do
  for i in $(seq 1 30); do kill -0 "$p" 2>/dev/null || break; sleep 1; done
  kill -0 "$p" 2>/dev/null && taskkill //F //T //PID "$p" > /dev/null 2>&1
done
taskkill //F //T //PID "$RPID" > /dev/null 2>&1; kill "$RPID" 2>/dev/null
for s in $(seq 0 $((N - 1))); do
  echo "siège $s : $(grep -h "srnp relay\|paused at" "$RUN/siege$s/runner.log" | tr '\n' ' ' | cut -c1-300)"
done
tail -4 "$RUN/relais.out"
for s in $(seq 1 $((N - 1))); do
  echo "siège $s / siège 0 : $("$PY" -I "$W/scripts/run/compare_ram.py" "$RUN/siege0" "$RUN/siege$s" | tail -1)"
done
echo "RUN=$RUN"
