#!/usr/bin/env bash
# Phase 2.5 : le lobby par les menus du jeu (SRNP_LOBBY=2) sur TE, N runners muets, sans pause automatique
# (le compteur des frames du jeu ne part qu'au lockstep) : chaque runner choisit par des touches simulées
# (TOUCHES="RAAS;AAS;..." : une suite par runner), puis GO, le state rechargé partout, la course.
# Captures de toutes les fenêtres (commande screenshot) aux secondes PHOTOS ; garde-fou (Gibax, 26/11 :
# « au bout de 5 minutes y'a pas de retour […] des chargements infinis ») : si le compteur de frames d'un
# runner n'avance plus pendant BLOCAGE s (300), le run s'arrête et le dit.
#   lobby_te.sh <runners> [durée max en s]
set -uo pipefail
N="${1:?runners}"; DUREE="${2:-240}"
W=/d/_SonicRidersSource/work
PY="/c/Program Files/Python313/python.exe"
RELAIS=/d/_SonicRidersSource/SR-Source-NetPlus/tools/srnp/relais.py
CHASSIS="${CHASSIS:-$W/te/runner}"
MODULE_TE="${MODULE_TE:-$W/te/module/gGXSRTE_recomp_te.dll}"
ETAT="${ETAT:-$W/states/gxsrte_pret1p_metal_1tour_jit.sav}"
JEU_DIR="${JEU_DIR:-$W/te/lad/sr-source/games/GXSRTE}"
RUN="$W/runs/$(date +%Y%m%d-%H%M%S)-te-lobby-$N${ETIQUETTE:+-$ETIQUETTE}"
mkdir -p "$RUN"
w() { cygpath -w "$1"; }
autres=$(tasklist.exe | grep -ci moderngekko)
[[ "$autres" != 0 ]] && { echo "!! $autres runner(s) déjà ouverts : rien lancé"; exit 3; }
"$PY" -I "$RELAIS" --sieges "$N" --journal "$(w "$RUN/relais.log")" > "$RUN/relais.out" 2>&1 &
RPID=$!
sleep 1
PIDS=()
for r in $(seq 0 $((N - 1))); do
  D="$RUN/runner$r"; mkdir -p "$D/auto/commands" "$D/ck"
  cp -a "$W/userdir_modele" "$D/userdir"
  mkdir -p "$D/userdir/GameSettings"
  cp /d/_SonicRidersSource/SR-Source-NetPlus/docs/game-settings/GXSRTE.ini "$D/userdir/GameSettings/GXSRTE.ini"
  sed -i 's/^\[Interface\]$/[Interface]\nUsePanicHandlers = False/' "$D/userdir/Config/Dolphin.ini"
  touches=$(echo "${TOUCHES:-}" | cut -d';' -f$((r + 1)))
  (cd "$CHASSIS" && LLVM_PROFILE_FILE="$(w "$D/module-%p.profraw")" SRNP_RELAY=127.0.0.1:7845 SRNP_SEAT=$r SRNP_SEATS=$N \
     SRNP_RACERS=1 SRNP_LOBBY=2 SRNP_LOBBY_KEYS="$touches" SRNP_CKDUMP="$(w "$D/ck")" SRNP_INPUT="${ENTREE:-ia}" SRNP_CHECK=60 \
     MODERNGEKKO_STATICRECOMP=1 ./moderngekko-run.exe --game "$(w "$JEU_DIR")" --user-dir "$(w "$D/userdir")" \
     --automation-dir "$(w "$D/auto")" --mute --no-mods --load-state "$(w "$ETAT")" --module "$(w "$MODULE_TE")" \
     > "$D/runner.log" 2>&1) &
  PIDS+=($!)
  echo "$(date +%T) runner $r (touches ${touches:-aucune})"
  sleep "${ECART:-2}"
done
photo() {  # photo <nom> : capture de chaque runner (commande screenshot)
  for r in $(seq 0 $((N - 1))); do
    printf 'command=screenshot\npath=%s\n' "$(w "$RUN/runner$r/$1.png")" > "$RUN/runner$r/auto/$1.tmp"
    mv "$RUN/runner$r/auto/$1.tmp" "$RUN/runner$r/auto/commands/$1.txt"
  done
}
T0=$SECONDS
declare -A dernier depuis
for r in $(seq 0 $((N - 1))); do dernier[$r]=-1; depuis[$r]=$SECONDS; done
PHOTOS=" ${PHOTOS:-15 30 60 120} "
while (( SECONDS - T0 < DUREE )); do
  sleep 1
  t=$((SECONDS - T0))
  [[ "$PHOTOS" == *" $t "* ]] && photo "t${t}s" && echo "$(date +%T) photos à $t s"
  for r in $(seq 0 $((N - 1))); do
    f=$(grep -m1 '^frame_count=' "$RUN/runner$r/auto/status.txt" 2>/dev/null | cut -d= -f2)
    if [[ "${f:-}" != "${dernier[$r]}" ]]; then dernier[$r]=${f:-}; depuis[$r]=$SECONDS; fi
    if (( SECONDS - depuis[$r] >= ${BLOCAGE:-300} )); then
      echo "!! runner $r : plus aucune frame depuis ${BLOCAGE:-300} s (frame ${f:-?}) : plantage ou chargement infini"
      photo "bloque"; sleep 3; DUREE=0
    fi
  done
done
for r in $(seq 0 $((N - 1))); do printf 'command=stop\n' > "$RUN/runner$r/auto/commands/zz.txt"; done
sleep 8
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { (\$_.Name -match 'moderngekko' -or \$_.Name -eq 'python.exe') -and \$_.CommandLine -like '*$(basename "$RUN")*' } | ForEach-Object { taskkill /F /T /PID \$_.ProcessId | Out-Null }"
taskkill //F //T //PID "$RPID" > /dev/null 2>&1
for r in $(seq 0 $((N - 1))); do
  echo "runner $r : $(grep -h 'chosen in the game\|start state back\|race of\|waiting screen off\|unknown guest' "$RUN/runner$r/runner.log" | tr '\n' ' ' | cut -c1-400)"
done
grep -h "parti\|DIVERGENCE" "$RUN/relais.log" | tail -3
echo "RUN=$RUN"
