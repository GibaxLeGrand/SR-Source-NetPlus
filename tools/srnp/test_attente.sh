#!/usr/bin/env bash
# L'écran d'attente, en images : 4 sièges, un runner par siège. Le runner 0 arrive seul (capture), puis le
# 1 (capture) ; le 1 part (capture : X) ; le 2 et le 3 arrivent : GO, le siège 1 passe à l'IA avec un perso
# tiré au hasard par le relais ; la course part, capture, puis arrêt et comparaison des sommes.
#   test_attente.sh [frame de capture en course]
set -uo pipefail
CAPT="${1:-8400}"
W=/d/_SonicRidersSource/work
CHASSIS="${CHASSIS:-$W/chassis_p2}"
PY="/c/Program Files/Python313/python.exe"
RELAIS=/d/_SonicRidersSource/SR-Source-NetPlus/tools/srnp/relais.py
STATE="${ETAT:-$W/states/gxee8p_pret1p_100pc_metal_1tour_jit.sav}"
RUN="$W/runs/$(date +%Y%m%d-%H%M%S)-attente"
mkdir -p "$RUN"
w() { cygpath -w "$1"; }
"$PY" -I "$RELAIS" --sieges 4 --port 7847 --journal "$(w "$RUN/relais.log")" > "$RUN/relais.out" 2>&1 &
RPID=$!
sleep 1
declare -A PIDS
lance() {  # lance <siège>
  local r=$1 D="$RUN/runner$1"
  mkdir -p "$D/auto/commands" "$D/ck"
  cp -a "$W/userdir_modele" "$D/userdir"
  sed -i "s/^\[Core\]\$/[Core]\nEmulationSpeed = 0.0/" "$D/userdir/Config/Dolphin.ini"
  sed -i 's/^\[Interface\]$/[Interface]\nUsePanicHandlers = False/' "$D/userdir/Config/Dolphin.ini"
  (cd "$CHASSIS" && SRNP_RELAY=127.0.0.1:7847 SRNP_SEAT=$r SRNP_SEATS=4 SRNP_RACERS=1 SRNP_TOUS_CPU=1 \
     SRNP_PERSOS="${SRNP_PERSOS:-0/0,10/0,9/0,8/0}" SRNP_INPUT=course:1 SRNP_CHECK=60 SRNP_CKDUMP="$(w "$D/ck")" \
     MODERNGEKKO_STATICRECOMP=1 ./moderngekko-run.exe --game "$(w "$W/games/GXEE8P")" --user-dir "$(w "$D/userdir")" \
     --automation-dir "$(w "$D/auto")" --mute --no-mods --load-state "$(w "$STATE")" \
     --module "$(w "$CHASSIS/gGXEE8P_recomp.dll")" > "$D/runner.log" 2>&1) &
  PIDS[$r]=$!
  echo "$(date +%T) runner $r lancé"
}
tue() {  # tue <motif de ligne de commande> : arrête ce processus par son numéro Windows
  local pid
  for pid in $(powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like '*$1*' -and \$_.Name -ne 'powershell.exe' -and \$_.Name -ne 'bash.exe' } | ForEach-Object { \$_.ProcessId }" | tr -d ''); do
    taskkill //F //T //PID "$pid" > /dev/null 2>&1 && echo "$(date +%T) arrêté $pid ($1)"
  done
}
fenetre() {  # fenetre <siège> <nom> : photo de la vraie fenêtre (interface comprise)
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(w "$W/phase2/capture_fenetre.ps1")" -Motif "$(basename "$RUN")\runner$1\\" -Png "$(w "$RUN/$2_fenetre.png")"
}
cliche() {  # cliche <siège> <nom> : capture (le runner peut être figé dans l'attente)
  local A="$RUN/runner$1/auto"
  printf 'command=screenshot\npath=%s\n' "$(w "$RUN/$2.png")" > "$A/commands/$2.txt"
  for i in $(seq 1 40); do [[ -f "$A/processed/$2.txt" || -f "$A/failed/$2.txt" ]] && break; sleep 0.25; done
  sleep 1
  echo "$(date +%T) capture $2 : $([[ -f "$RUN/$2.png" ]] && echo oui || echo non)"
}
lance 0; sleep 12; fenetre 0 attente_1
lance 1; sleep 12; fenetre 0 attente_2
tue "$(basename "$RUN")\runner1\\"; sleep 5; fenetre 0 attente_3
lance 2; lance 3
for r in 0 2 3; do printf 'command=pad_frames\nport=3\nframes=1\npause_at=%s\n' "$CAPT" > "$RUN/runner$r/auto/commands/p1.txt"; done
for r in 0 2 3; do
  for i in $(seq 1 600); do [[ -f "$RUN/runner$r/auto/processed/p1.txt" ]] && break; kill -0 "${PIDS[$r]}" 2>/dev/null || break; sleep 0.5; done
done
for r in 0 2 3; do
  printf 'command=screenshot\npath=%s\n' "$(w "$RUN/course_$r.png")" > "$RUN/runner$r/auto/commands/s1.txt"
  printf 'command=resume\n' > "$RUN/runner$r/auto/commands/s2.txt"
  printf 'command=pad_frames\nport=3\nframes=1\npause_at=%s\n' "$((CAPT + 5))" > "$RUN/runner$r/auto/commands/s3.txt"
done
sleep 6
for r in 0 2 3; do printf 'command=stop\n' > "$RUN/runner$r/auto/commands/z.txt"; done
for r in 0 2 3; do for i in $(seq 1 30); do kill -0 "${PIDS[$r]}" 2>/dev/null || break; sleep 1; done
  done; for r in 0 1 2 3; do tue "$(basename "$RUN")\runner$r\\"; done
tue "relais.py --sieges 4 --port 7847"
grep -h "connecté\|GO\|parti\|DIVERGENCE" "$RUN/relais.log" | head -12; tail -1 "$RUN/relais.log"
for r in 0 2 3; do echo "runner $r : $(grep -h 'waiting for\|every seat\|set by the relay\|seat 1' "$RUN/runner$r/runner.log" | tr '\n' ' ' | cut -c1-400)"; done
ls "$RUN"/*.png
echo "RUN=$RUN"
