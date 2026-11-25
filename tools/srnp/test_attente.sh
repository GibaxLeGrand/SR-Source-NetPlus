#!/usr/bin/env bash
# L'écran d'attente, en images : N sièges (SIEGES, 4 par défaut), un runner par siège. Le runner 0 arrive
# seul (photo), puis le 1 (photo) ; le 1 part (photo : X) ; les autres arrivent (photo avant le dernier) ;
# GO, le siège 1 passe à l'IA avec un perso tiré au hasard par le relais ; la course part, capture, puis
# arrêt. Les photos sont celles de la vraie fenêtre (capture_fenetre.ps1 : les captures du runner
# laissent de côté son interface). ETIQ=1 (défaut) monte le mod des étiquettes 5P-8P s'il est là.
#   test_attente.sh [frame de capture en course]
set -uo pipefail
CAPT="${1:-8400}"
N="${SIEGES:-4}"
W=/d/_SonicRidersSource/work
CHASSIS="${CHASSIS:-$W/chassis_p2}"
PY="/c/Program Files/Python313/python.exe"
RELAIS=/d/_SonicRidersSource/SR-Source-NetPlus/tools/srnp/relais.py
STATE="${ETAT:-$W/states/gxee8p_pret1p_100pc_metal_1tour_jit.sav}"
PERSOS="${SRNP_PERSOS:-0/0,10/0,9/0,8/0,14/0,13/0,7/0,6/0}"
RUN="$W/runs/$(date +%Y%m%d-%H%M%S)-attente"
mkdir -p "$RUN"
w() { cygpath -w "$1"; }
"$PY" -I "$RELAIS" --sieges "$N" --port 7847 --journal "$(w "$RUN/relais.log")" > "$RUN/relais.out" 2>&1 &
sleep 1
lance() {  # lance <siège>
  local r=$1 D="$RUN/runner$1" MODS=--no-mods
  mkdir -p "$D/auto/commands" "$D/ck"
  cp -a "$W/userdir_modele" "$D/userdir"
  sed -i "s/^\[Core\]\$/[Core]\nEmulationSpeed = 0.0/" "$D/userdir/Config/Dolphin.ini"
  sed -i 's/^\[Interface\]$/[Interface]\nUsePanicHandlers = False/' "$D/userdir/Config/Dolphin.ini"
  if [[ -d "$W/etiquettes/mods/srnp_etiquettes/files" && "${ETIQ:-1}" == 1 ]]; then
    mkdir -p "$D/userdir/Mods/srnp_etiquettes"
    printf 'name=srnp_etiquettes\ngame=GXEE8P\n' > "$D/userdir/Mods/srnp_etiquettes/mod.ini"
    powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(w "$D/userdir/Mods/srnp_etiquettes/files")' -Target '$(w "$W/etiquettes/mods/srnp_etiquettes/files")' | Out-Null"
    printf 'mod=srnp_etiquettes\n' >> "$D/userdir/config.ini"
    MODS=
  fi
  (cd "$CHASSIS" && SRNP_RELAY=127.0.0.1:7847 SRNP_SEAT=$r SRNP_SEATS=$N SRNP_RACERS=1 SRNP_TOUS_CPU=1 \
     SRNP_PERSOS="$PERSOS" SRNP_INPUT=course:1 SRNP_CHECK=60 SRNP_CKDUMP="$(w "$D/ck")" \
     MODERNGEKKO_STATICRECOMP=1 ./moderngekko-run.exe --game "$(w "$W/games/GXEE8P")" --user-dir "$(w "$D/userdir")" \
     --automation-dir "$(w "$D/auto")" --mute $MODS --load-state "$(w "$STATE")" \
     --module "$(w "$CHASSIS/gGXEE8P_recomp.dll")" > "$D/runner.log" 2>&1) &
  echo "$(date +%T) runner $r lancé"
}
tue() {  # tue <motif de ligne de commande> : arrête ces processus par leur numéro Windows
  local pid
  for pid in $(powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like '*$1*' -and \$_.Name -ne 'powershell.exe' -and \$_.Name -ne 'bash.exe' } | ForEach-Object { \$_.ProcessId }" | tr -d '\r'); do
    taskkill //F //T //PID "$pid" > /dev/null 2>&1 && echo "$(date +%T) arrêté $pid ($1)"
  done
}
vivant() {  # vivant <siège> : le runner tourne encore
  powershell -NoProfile -Command "@(Get-CimInstance Win32_Process -Filter \"name='moderngekko-run.exe'\" | Where-Object { \$_.CommandLine -like '*$(basename "$RUN")\\runner$1\\*' }).Count" | tr -d '\r' | grep -qv '^0$'
}
fenetre() {  # fenetre <siège> <nom> : photo de la vraie fenêtre (interface comprise)
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(w "$W/phase2/capture_fenetre.ps1")" -Motif "$(basename "$RUN")\\runner$1\\" -Png "$(w "$RUN/$2_fenetre.png")"
}
lance 0; sleep 14; fenetre 0 attente_1
lance 1; sleep 14; fenetre 0 attente_2
tue "$(basename "$RUN")\\runner1\\"; sleep 5; fenetre 0 attente_3
for r in $(seq 2 $((N - 2))); do lance $r; done
sleep 16; fenetre 0 attente_4
lance $((N - 1))
RESTE="0 $(seq -s ' ' 2 $((N - 1)))"
for r in $RESTE; do printf 'command=pad_frames\nport=3\nframes=1\npause_at=%s\n' "$CAPT" > "$RUN/runner$r/auto/commands/p1.txt"; done
for r in $RESTE; do
  for i in $(seq 1 400); do [[ -f "$RUN/runner$r/auto/processed/p1.txt" ]] && break; sleep 0.5; done
done
for r in $RESTE; do
  printf 'command=screenshot\npath=%s\n' "$(w "$RUN/course_$r.png")" > "$RUN/runner$r/auto/commands/s1.txt"
  printf 'command=resume\n' > "$RUN/runner$r/auto/commands/s2.txt"
  printf 'command=pad_frames\nport=3\nframes=1\npause_at=%s\n' "$((CAPT + 5))" > "$RUN/runner$r/auto/commands/s3.txt"
done
sleep 6
for r in $RESTE; do printf 'command=stop\n' > "$RUN/runner$r/auto/commands/z.txt"; done
sleep 10
for r in $(seq 0 $((N - 1))); do tue "$(basename "$RUN")\\runner$r\\"; done
tue "relais.py --sieges $N --port 7847"
grep -h "connecté\|GO\|parti\|DIVERGENCE" "$RUN/relais.log" | head -14; tail -1 "$RUN/relais.log"
for r in $RESTE; do echo "runner $r : $(grep -h 'waiting for\|every seat\|set by the relay\|labels\|screens\]' "$RUN/runner$r/runner.log" | tr '\n' ' ' | cut -c1-500)"; done
ls "$RUN"/*.png
echo "RUN=$RUN"
