#!/usr/bin/env bash
# SR-Source Net Plus : le lobby Online/LAN du launcher, deux launchers sur ce PC.
#   - launcher A (hôte, tag HOTE) : ouvre la salle (relais intégré, port $PORT) ;
#   - launcher B (tag AMI) : s'y connecte, se dit prêt ; l'hôte lance la course DEPART s après ;
#   - chaque launcher lance son runner (work\chassis_p2) en lobby par les menus du jeu (SRNP_LOBBY=2) :
#     appuis simulés dans Player Entry (A : RAAS = Tails, B : RRAAS = Knuckles), course à l'IA
#     (SRNP_INPUT=ia) ; photos des launchers (lobby) et des jeux ;
#   - fin : runners arrêtés après DUREE s de course, puis les launchers ; bilan du relais (relay.log).
#   test_online.sh   (RULES=<course>/<laps>/<racers>/<delay>, défaut 1/1/8/2 ; DUREE=90 ; DEPART=6)
#   PING=<ms>[~<gigue>] ou <siège>=<ms>[~<gigue>],... : ping simulé par le relais (SRNP_RELAY_PING) ;
#   INPUT_B=course : entrées de test variées pour l'ami (au lieu de l'IA).
#   FIN_A, FIN_B=restart|menu|replay : le choix de chaque jeu dans le menu des résultats (SRNP_FIN_CHOIX : manches).
#   JEU=GXSRTE : la salle joue Tournament Edition (choisi dans la salle, SRNP_ONLINE_GAME) : le jeu de
#     work\te\lad, le runner de la session phase 2 (work\te\runner, le mod porté sur TE), le module natif de TE
#     (STATICRECOMP_MODULE) et son state d'Entrée des joueurs (CPUs ON, 1 tour).
set -uo pipefail
W=/d/_SonicRidersSource/work
L=$W/launcher_online
EXE="$L/SR-Source.exe"
JEU="${JEU:-GXEE8P}"
if [[ "$JEU" == GXSRTE ]]; then
  RUNNER="${RUNNER:-$W/te/runner/moderngekko-run.exe}"
  STATE="${ETAT:-$W/states/gxsrte_entree_joueurs_metal_1tour_jit.sav}"
  export STATICRECOMP_MODULE="$(cygpath -w "${MODULE_TE:-$W/te/module/gGXSRTE_recomp_te.dll}")"
else
  RUNNER="$W/chassis_p2/moderngekko-run.exe"
  STATE="${ETAT:-$W/states/gxee8p_pret1p_100pc_metal_1tour_jit.sav}"
fi
PORT="${PORT:-7850}"
RUN="$L/runs/$(date +%Y%m%d-%H%M%S)"
w() { cygpath -w "$1"; }
autres=$(tasklist.exe | grep -ciE "moderngekko|SR-Source")
if [[ "$autres" != 0 ]]; then echo "$autres processus SR-Source déjà ouverts : rien lancé"; exit 1; fi
mkdir -p "$RUN"
prepare() {  # prepare <pc> <tag>
  local U="$RUN/$1/sr-source"
  mkdir -p "$U/Logs"
  cp -a "$W/userdir_modele/Config" "$U/Config"
  sed -e 's/^music_volume=.*/music_volume=0/' -e 's/^game_volume=.*/game_volume=0/' -e 's/^check_for_updates=.*/check_for_updates=false/' \
      -e 's/^cpu_core=.*/cpu_core=staticrecomp/' "$W/userdir_modele/config.ini" > "$U/config.ini"
  w "$W/games/GXEE8P" > "$U/default-game.txt"
  # Les jeux extraits du joueur : Sonic Riders et Tournament Edition (le launcher les cherche dans games\).
  mkdir -p "$U/games"
  powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(w "$U/games/GXEE8P")' -Target '$(w "$W/games/GXEE8P")' | Out-Null; New-Item -ItemType Junction -Path '$(w "$U/games/GXSRTE")' -Target '$(w "$W/te/lad/sr-source/games/GXSRTE")' | Out-Null"
  # Les réglages StaticRecomp de TE (attente de l'OS) : le launcher les copie dans le dossier de la partie.
  mkdir -p "$U/GameSettings"
  cp /d/_SonicRidersSource/SR-Source-NetPlus/docs/game-settings/GXSRTE.ini "$U/GameSettings/GXSRTE.ini"
  if [[ "$JEU" == GXSRTE ]]; then
    printf 'tag=%s\naddress=127.0.0.1:%s\nport=%s\ngame=GXSRTE\nstart_state_GXSRTE=%s\n' "$2" "$PORT" "$PORT" "$(w "$STATE")" > "$U/online.ini"
  else
    printf 'tag=%s\naddress=127.0.0.1:%s\nport=%s\nstart_state=%s\n' "$2" "$PORT" "$PORT" "$(w "$STATE")" > "$U/online.ini"
  fi
  # La manette de Gibax (INPUT_A=manette) : un profil avec ses boutons, comme la page Controls l'écrit
  # (le modèle ne nomme que l'appareil, sans bouton : la manette n'envoyait rien, essai de 23 h 37).
  if [[ "$1" == pcA && "${INPUT_A:-ia}" == manette ]]; then
    cat > "$U/Config/GCPadNew.ini" <<PROFIL
[GCPad1]
Device = ${MANETTE:-SDL/0/Xbox One Controller}
Buttons/A = \`Button A\`
Buttons/B = \`Button B\`
Buttons/X = \`Button X\`
Buttons/Y = \`Button Y\`
Buttons/Z = \`Shoulder R\`
Buttons/Start = Start
Main Stick/Up = \`Left Y+\`
Main Stick/Down = \`Left Y-\`
Main Stick/Left = \`Left X-\`
Main Stick/Right = \`Left X+\`
C-Stick/Up = \`Right Y+\`
C-Stick/Down = \`Right Y-\`
C-Stick/Left = \`Right X-\`
C-Stick/Right = \`Right X+\`
Triggers/L = \`Trigger L\`
Triggers/R = \`Trigger R\`
Triggers/L-Analog = \`Trigger L\`
Triggers/R-Analog = \`Trigger R\`
D-Pad/Up = \`Pad N\`
D-Pad/Down = \`Pad S\`
D-Pad/Left = \`Pad W\`
D-Pad/Right = \`Pad E\`
PROFIL
  fi
  # Le mod des étiquettes 5P-8P installé chez le joueur (le dossier Mods de son dossier utilisateur), pas
  # activé dans son config.ini : le launcher l'active pour la partie en ligne.
  mkdir -p "$U/Mods/srnp_etiquettes"
  printf 'name=srnp_etiquettes\ngame=GXEE8P\n' > "$U/Mods/srnp_etiquettes/mod.ini"
  powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(w "$U/Mods/srnp_etiquettes/files")' -Target '$(w "$W/etiquettes/mods/srnp_etiquettes/files")' | Out-Null"
}
prepare pcA HOTE
prepare pcB AMI
photo() {  # photo <pid windows> <fichier>
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(w "$L/photo_pid.ps1")" -ProcessId "$1" -Png "$(w "$2")"
}
pid_de() {  # pid_de <nom d'exe> <motif de la ligne de commande ou de l'environnement : le dossier du pc>
  powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"name='$1'\" | Where-Object { \$_.CommandLine -like '*$2*' } | Select-Object -First 1).ProcessId" | tr -d '\r'
}
# Les launchers : chacun son LOCALAPPDATA (son dossier utilisateur), un argument --x11 inutile sous
# Windows sert de marque dans la ligne de commande pour les retrouver.
lance() {  # lance <pc> <auto> <touches> [variables...]
  local pc=$1 auto=$2 keys=$3; shift 3
  # VIDAGE=1 : les 8 racers à chaque somme de contrôle (SRNP_CKDUMP), dans runner<siège>/ck comme
  # lockstepn.sh, pour work\phase2\compare_ck.py.
  local ck=""
  if [[ "${VIDAGE:-0}" == 1 ]]; then
    local k=0; [[ "$pc" == pcB ]] && k=1
    mkdir -p "$RUN/runner$k/ck"; ck="$(w "$RUN/runner$k/ck")"
  fi
  (cd "$L" && env LOCALAPPDATA="$(w "$RUN/$pc")" SRNP_RUNNER="$(w "$RUNNER")" SRNP_ONLINE_AUTO="$auto" \
     SRNP_LOBBY_KEYS="$keys" SRNP_CKDUMP="$ck" "$@" "$EXE" --x11 "$pc-$(basename "$RUN")" > "$RUN/$pc/launcher.out" 2>&1) &
  echo "$(date +%T) launcher $pc lancé ($auto)"
}
lance pcA host "${TOUCHES_A-RAAS}" SRNP_ONLINE_RULES="${RULES:-1/1/8/2}" SRNP_ONLINE_START="2:${DEPART:-6}" SRNP_ONLINE_BACKGROUND="${FOND_A:-}" SRNP_INPUT="${INPUT_A:-ia}" SRNP_RELAY_PING="${PING:-}" SRNP_FIN_CHOIX="${FIN_A:-}"
sleep 7
LA=$(pid_de SR-Source.exe "pcA-$(basename "$RUN")")
photo "$LA" "$RUN/1_hote_seul.png"
lance pcB connect RRAAS SRNP_ONLINE_READY=1 SRNP_ONLINE_BACKGROUND="${FOND_B:-}" SRNP_INPUT="${INPUT_B:-ia}" SRNP_FIN_CHOIX="${FIN_B:-}"
sleep 4
LB=$(pid_de SR-Source.exe "pcB-$(basename "$RUN")")
photo "$LA" "$RUN/2_lobby_hote.png"
photo "$LB" "$RUN/2_lobby_ami.png"
echo "$(date +%T) photos du lobby (launchers $LA, $LB)"
# Les jeux : Player Entry, l'attente, la course.
RA=""; RB=""
for i in $(seq 1 60); do
  RA=$(pid_de moderngekko-run.exe "pcA\\sr-source\\Online"); RB=$(pid_de moderngekko-run.exe "pcB\\sr-source\\Online")
  [[ -n "$RA" && -n "$RB" ]] && break
  sleep 1
done
echo "$(date +%T) runners : $RA, $RB"
for t in 12 22 40 70; do
  sleep $(( t - ${prev:-0} )); prev=$t
  [[ -n "$RA" ]] && photo "$RA" "$RUN/3_jeu_${t}s_hote.png"
  [[ -n "$RB" ]] && photo "$RB" "$RUN/3_jeu_${t}s_ami.png"
  echo "$(date +%T) photos des jeux à ${t} s"
done
sleep $(( ${DUREE:-90} - 70 ))
# Fin : les runners d'abord (les launchers reviennent au lobby), puis les launchers.
for p in $RA $RB; do taskkill.exe //F //PID "$p" > /dev/null 2>&1; done
sleep 6
photo "$LA" "$RUN/4_apres_hote.png"
for p in $LA $LB; do taskkill.exe //F //PID "$p" > /dev/null 2>&1; done
echo "--- relais"
grep -E "joined|match|GO|DIVERGENCE|connected|identical|rules|left aside" "$RUN/pcA/sr-source/Logs/relay.log" | tail -25
echo "--- runners"
grep -h "srnp relay\] \(seat\|chosen\|the host\|start state back\|every seat\)" "$RUN"/pc?/sr-source/Logs/*.log 2>/dev/null | head -12
"/c/Program Files/Python313/python.exe" - "$(w "$RUN")" <<'PY'
import sys, glob, os
from PIL import Image
run = sys.argv[1]
for motif, nom in (("2_lobby_*.png", "planche_lobby.png"), ("3_jeu_*.png", "planche_jeux.png")):
    ps = sorted(glob.glob(os.path.join(run, motif)))
    if not ps:
        continue
    ims = [Image.open(p).convert("RGB") for p in ps]
    w = 640
    tiles = [im.resize((w, int(w * im.size[1] / im.size[0]))) for im in ims]
    h = max(t.size[1] for t in tiles)
    cols = 2
    c = Image.new("RGB", (w * cols, h * ((len(tiles) + cols - 1) // cols)))
    for i, t in enumerate(tiles):
        c.paste(t, ((i % cols) * w, (i // cols) * h))
    c.save(os.path.join(run, nom))
    print(nom, len(ps))
PY
echo "RUN=$RUN"
