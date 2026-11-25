#!/usr/bin/env bash
# Un runner, un siège (l'IA conduit), SRNP_HUMAINS=<masque> : MEM1 vidée aux frames du jeu données.
#   ram_masque.sh <masque> <frame>...   (MEM1 dans <run>/f<frame>/mem1_lo.bin, mem1_hi.bin)
set -uo pipefail
M=$1; shift
W=/d/_SonicRidersSource/work
CHASSIS="${CHASSIS:-$W/chassis_p2}"
PY="/c/Program Files/Python313/python.exe"
RELAIS=/d/_SonicRidersSource/SR-Source-NetPlus/tools/srnp/relais.py
STATE="$W/states/gxee8p_pret1p_100pc_metal_1tour_jit.sav"
RUN="$W/runs/$(date +%Y%m%d-%H%M%S)-ram-$M"
D="$RUN/runner0"; A="$D/auto"
mkdir -p "$A/commands" "$D/ck"
w() { cygpath -w "$1"; }
[[ "$(tasklist.exe | grep -ci moderngekko)" != 0 ]] && { echo "des runners tournent déjà"; exit 1; }
"$PY" -I "$RELAIS" --sieges 1 --port 7847 --journal "$(w "$RUN/relais.log")" > "$RUN/relais.out" 2>&1 &
sleep 1
cp -a "$W/userdir_modele" "$D/userdir"
sed -i "s/^\[Core\]\$/[Core]\nEmulationSpeed = 1.0/" "$D/userdir/Config/Dolphin.ini"
sed -i 's/^\[Interface\]$/[Interface]\nUsePanicHandlers = False/' "$D/userdir/Config/Dolphin.ini"
(cd "$CHASSIS" && SRNP_RELAY=127.0.0.1:7847 SRNP_SEAT=0 SRNP_SEATS=1 SRNP_RACERS=1 SRNP_TOUS_CPU=1 SRNP_IA_JOUEUR=1 \
   SRNP_HUMAINS=$M SRNP_INPUT=ia SRNP_CHECK=60 SRNP_CKDUMP="$(w "$D/ck")" SRNP_PAUSE_JEU=1 \
   MODERNGEKKO_STATICRECOMP=1 ./moderngekko-run.exe --game "$(w "$W/games/GXEE8P")" --user-dir "$(w "$D/userdir")" \
   --automation-dir "$(w "$A")" --mute --load-state "$(w "$STATE")" \
   --module "$(w "$CHASSIS/gGXEE8P_recomp.dll")" > "$D/runner.log" 2>&1) &
cmd() { printf "$2" > "$A/$1.tmp" && mv "$A/$1.tmp" "$A/commands/$1.txt"; }
attend() { for i in $(seq 1 600); do [[ -f "$A/processed/$1.txt" ]] && return 0; [[ -f "$A/failed/$1.txt" ]] && { rm -f "$A/failed/$1.txt"; sleep 0.5; cmd "$1" "$2"; }; sleep 0.5; done; return 1; }
sleep 2
for f in "$@"; do
  mkdir -p "$RUN/f$f"
  t="command=pad_frames\nport=3\nframes=1\npause_at=$f\n"; cmd "p$f" "$t"; attend "p$f" "$t" || echo "pause $f manquée"
  t="command=read_memory\naddress=0x80000000\nsize=16777216\npath=$(w "$RUN/f$f/mem1_lo.bin" | sed 's/\\/\\\\/g')\n"; cmd "lo$f" "$t"; attend "lo$f" "$t"
  t="command=read_memory\naddress=0x81000000\nsize=8388608\npath=$(w "$RUN/f$f/mem1_hi.bin" | sed 's/\\/\\\\/g')\n"; cmd "hi$f" "$t"; attend "hi$f" "$t"
  t='command=resume\n'; cmd "r$f" "$t"; attend "r$f" "$t"
  for i in $(seq 1 40); do grep -q '^state=running' "$A/status.txt" && break; sleep 0.25; done
  echo "$(date +%T) frame $f vidée"
done
printf 'command=stop\n' > "$A/commands/z.txt"; sleep 5
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { (\$_.Name -match 'moderngekko' -or \$_.Name -eq 'python.exe') -and \$_.CommandLine -like '*$(basename "$RUN")*' } | ForEach-Object { taskkill /F /T /PID \$_.ProcessId | Out-Null }"
echo "RUN=$RUN"
