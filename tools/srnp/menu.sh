#!/usr/bin/env bash
# Explorer les menus du jeu avec un runner hors ligne (sans relais), piloté par l'automatisation.
#   menu.sh start                 lance le runner sur le save state (Player Entry), dossier dans work/runs
#   menu.sh press <bouton> [n]    appuie n frames (défaut 6) sur la manette 1 (a b x y start dpad_left...)
#   menu.sh wait <n>              laisse passer n frames
#   menu.sh shot <nom>            photo de la fenêtre (<run>/<nom>.png)
#   menu.sh dump <nom>            MEM1 dans <run>/<nom>_lo.bin et _hi.bin
#   menu.sh poke <adresse> <hex>  écrit des octets
#   menu.sh save <nom>            save state <run>/<nom>.sav
#   menu.sh stop                  arrête ce runner (et lui seul)
set -uo pipefail
W=/d/_SonicRidersSource/work
CHASSIS="${CHASSIS:-$W/chassis_p2}"
STATE="${STATE:-$W/states/gxee8p_pret1p_100pc_metal_1tour_jit.sav}"
COURANT="$W/phase2/menu_courant.txt"
w() { cygpath -w "$1"; }
win() { w "$1" | sed 's/\\/\\\\/g'; }
run() { cat "$COURANT"; }
n=0
cmd() {  # cmd <texte> : écrit, attend le traitement
  local A="$(run)/runner0/auto" id="c$(date +%s%N)"
  printf "$1" > "$A/$id.tmp" && mv "$A/$id.tmp" "$A/commands/$id.txt"
  for i in $(seq 1 240); do
    [[ -f "$A/processed/$id.txt" ]] && return 0
    [[ -f "$A/failed/$id.txt" ]] && { echo "refusée : $1"; cat "$A/failed/$id.txt" 2>/dev/null | head -3; return 1; }
    sleep 0.25
  done
  echo "sans réponse : $1"; return 1
}
case "$1" in
  start)
    [[ "$(tasklist.exe | grep -ci moderngekko)" != 0 ]] && { echo "des runners tournent déjà"; exit 1; }
    RUN="$W/runs/$(date +%Y%m%d-%H%M%S)-menu"; D="$RUN/runner0"
    mkdir -p "$D/auto/commands"; echo "$RUN" > "$COURANT"
    cp -a "$W/userdir_modele" "$D/userdir"
    sed -i "s/^\[Core\]\$/[Core]\nEmulationSpeed = 1.0/" "$D/userdir/Config/Dolphin.ini"
    sed -i 's/^\[Interface\]$/[Interface]\nUsePanicHandlers = False/' "$D/userdir/Config/Dolphin.ini"
    (cd "$CHASSIS" && MODERNGEKKO_STATICRECOMP=1 ./moderngekko-run.exe --game "$(w "$W/games/GXEE8P")" \
       --user-dir "$(w "$D/userdir")" --automation-dir "$(w "$D/auto")" --mute --load-state "$(w "$STATE")" \
       --module "$(w "$CHASSIS/gGXEE8P_recomp.dll")" > "$D/runner.log" 2>&1) &
    for i in $(seq 1 120); do grep -q '^state=running' "$D/auto/status.txt" 2>/dev/null && break; sleep 0.5; done
    sleep 3; echo "RUN=$RUN" ;;
  press) cmd "command=pad_frames\nport=0\nframes=${3:-6}\n$2=1\n" && cmd "command=pad_frames\nport=0\nframes=10\n" ;;
  wait) cmd "command=pad_frames\nport=0\nframes=$2\n" ;;
  shot)
    powershell -NoProfile -ExecutionPolicy Bypass -File "$(w "$W/phase2/capture_fenetre.ps1")" \
      -Motif "$(basename "$(run)")\\runner0\\" -Png "$(w "$(run)/$2.png")" > /dev/null; echo "$(run)/$2.png" ;;
  dump)
    cmd "command=pause\n"
    cmd "command=read_memory\naddress=0x80000000\nsize=16777216\npath=$(win "$(run)/$2_lo.bin")\n"
    cmd "command=read_memory\naddress=0x81000000\nsize=8388608\npath=$(win "$(run)/$2_hi.bin")\n"
    cmd "command=resume\n" ;;
  poke) cmd "command=write_memory\naddress=$2\ndata=$3\n" ;;
  save) cmd "command=save_state\npath=$(win "$(run)/$2.sav")\n" ;;
  stop)
    printf 'command=stop\n' > "$(run)/runner0/auto/commands/z.txt"; sleep 5
    powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.Name -match 'moderngekko' -and \$_.CommandLine -like '*$(basename "$(run)")*' } | ForEach-Object { taskkill /F /T /PID \$_.ProcessId | Out-Null }" ;;
esac
