#!/usr/bin/env bash
# Démo à 8 joueurs : tout ce que fait SR-Source Net Plus aujourd'hui, en photos des vraies fenêtres.
#   - avant tout : aucun processus Sonic Riders Source ne doit tourner (ils sont arrêtés) ;
#   - 8 runners natifs sur ce poste, un siège chacun, lancés à ECART s d'écart : l'écran d'attente se
#     remplit (photos du runner 0 et de tous) ;
#   - GO, course complète depuis « Are you ready? » (8 racers en CPU au montage, conduits par l'IA) :
#     chaque runner sa caméra, son HUD, sa mini-carte, son spotter, les étiquettes 5P-8P du mod ;
#   - photos des 8 fenêtres aux frames du jeu CAPT1, CAPT2, CAPT3 (pause à la même frame partout :
#     SRNP_PAUSE_JEU=1) ; sommes de contrôle du relais ; SRNP_IA_JOUEUR=1 : racers « nP » conduits par l IA ;
#   - planches (une par moment) dans le dossier du run.
#   demo_8.sh [CAPT1] [CAPT2] [CAPT3]
set -uo pipefail
C1="${1:-1900}"; C2="${2:-3850}"; C3="${3:-5650}"   # frames du jeu (SRNP_PAUSE_JEU)
N=8
W=/d/_SonicRidersSource/work
CHASSIS="${CHASSIS:-$W/chassis_p2}"
PY="/c/Program Files/Python313/python.exe"
RELAIS=/d/_SonicRidersSource/SR-Source-NetPlus/tools/srnp/relais.py
STATE="$W/states/gxee8p_pret1p_100pc_metal_1tour_jit.sav"
PERSOS="${SRNP_PERSOS:-0/0,10/0,1/0,3/0,7/0,14/0,13/0,6/0}"
RUN="$W/runs/$(date +%Y%m%d-%H%M%S)-demo-8"
mkdir -p "$RUN"
w() { cygpath -w "$1"; }
ps_lignes() { powershell -NoProfile -Command "$1" | tr -d '\r'; }
# 1. Plus aucun processus Sonic Riders Source (ni relais d'un essai) : ils voleraient des perfs.
ps_lignes "Get-CimInstance Win32_Process | Where-Object { \$_.Name -match 'moderngekko' -or (\$_.Name -eq 'python.exe' -and \$_.CommandLine -like '*relais.py*') } | ForEach-Object { taskkill /F /T /PID \$_.ProcessId | Out-Null; 'arrêté ' + \$_.ProcessId + ' ' + \$_.Name }"
sleep 2
"$PY" -I "$RELAIS" --sieges $N --port 7845 --journal "$(w "$RUN/relais.log")" > "$RUN/relais.out" 2>&1 &
sleep 1
lance() {  # lance <siège>
  local r=$1 D="$RUN/runner$1"
  mkdir -p "$D/auto/commands" "$D/ck"
  cp -a "$W/userdir_modele" "$D/userdir"
  sed -i "s/^\[Core\]\$/[Core]\nEmulationSpeed = 1.0/" "$D/userdir/Config/Dolphin.ini"
  sed -i 's/^\[Interface\]$/[Interface]\nUsePanicHandlers = False/' "$D/userdir/Config/Dolphin.ini"
  mkdir -p "$D/userdir/Mods/srnp_etiquettes"
  printf 'name=srnp_etiquettes\ngame=GXEE8P\n' > "$D/userdir/Mods/srnp_etiquettes/mod.ini"
  powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(w "$D/userdir/Mods/srnp_etiquettes/files")' -Target '$(w "$W/etiquettes/mods/srnp_etiquettes/files")' | Out-Null"
  printf 'mod=srnp_etiquettes\n' >> "$D/userdir/config.ini"
  local SON=--mute; [[ "$r" == "${SON_RUNNER:-0}" ]] && SON=
  (cd "$CHASSIS" && SRNP_RELAY=127.0.0.1:7845 SRNP_SEAT=$r SRNP_SEATS=$N SRNP_RACERS=1 SRNP_TOUS_CPU=1 \
     SRNP_PERSOS="$PERSOS" SRNP_INPUT=ia SRNP_CHECK=60 SRNP_PAUSE_JEU=1 SRNP_CKDUMP="$(w "$D/ck")" \
     MODERNGEKKO_STATICRECOMP=1 ./moderngekko-run.exe --game "$(w "$W/games/GXEE8P")" --user-dir "$(w "$D/userdir")" \
     --automation-dir "$(w "$D/auto")" $SON --load-state "$(w "$STATE")" \
     --module "$(w "$CHASSIS/gGXEE8P_recomp.dll")" > "$D/runner.log" 2>&1) &
  echo "$(date +%T) joueur $((r + 1)) arrive (siège $r)"
}
fenetre() {  # fenetre <siège> <nom> : photo de la vraie fenêtre (interface comprise)
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(w "$W/phase2/capture_fenetre.ps1")" \
    -Motif "$(basename "$RUN")\\runner$1\\" -Png "$(w "$RUN/$2_j$(($1 + 1)).png")" > /dev/null
}
commande() {  # commande <runner> <nom> <texte> : écrite à côté puis déplacée (jamais lue à moitié)
  printf "$3" > "$RUN/runner$1/auto/$2.tmp" && mv "$RUN/runner$1/auto/$2.tmp" "$RUN/runner$1/auto/commands/$2.txt"
}
pause_a() {  # pause_a <frame> : tous en pause à cette frame du jeu (la même partout en lockstep)
  local texte="command=pad_frames\nport=3\nframes=1\npause_at=$1\n"
  for r in $(seq 0 $((N - 1))); do commande $r "p$1" "$texte"; done
  for r in $(seq 0 $((N - 1))); do
    for i in $(seq 1 900); do
      [[ -f "$RUN/runner$r/auto/processed/p$1.txt" ]] && break
      # Refusée (le cœur n'était pas encore reparti, par exemple) : renvoyée.
      if [[ -f "$RUN/runner$r/auto/failed/p$1.txt" ]]; then
        rm -f "$RUN/runner$r/auto/failed/p$1.txt"; echo "$(date +%T) runner $r : pause $1 refusée, renvoyée"
        sleep 0.5; commande $r "p$1" "$texte"
      fi
      sleep 0.5
    done
  done
  sleep 1
}
reprise() {  # reprise <frame> : tous repartent ; attend que chacun tourne de nouveau
  for r in $(seq 0 $((N - 1))); do commande $r "r$1" 'command=resume\n'; done
  for r in $(seq 0 $((N - 1))); do
    for i in $(seq 1 60); do
      [[ -f "$RUN/runner$r/auto/processed/r$1.txt" ]] && grep -q '^state=running' "$RUN/runner$r/auto/status.txt" && break
      sleep 0.5
    done
  done
  sleep 1
}

# 2. Les joueurs arrivent : l'écran d'attente se remplit.
ECART="${ECART:-3}"
for r in $(seq 0 $((N - 1))); do
  lance $r
  sleep "$ECART"
  [[ $r == 0 ]] && sleep 10   # le premier charge le jeu
  case $r in 1|3|5) fenetre 0 "attente_$((r + 1))sur8";; 6) for k in $(seq 0 6); do fenetre $k attente_7sur8; done;; esac
done
# 3. La course : trois moments, les 8 fenêtres.
for c in "$C1" "$C2" "$C3"; do
  pause_a "$c"
  for r in $(seq 0 $((N - 1))); do fenetre $r "course_f$c"; done
  echo "$(date +%T) photos à la frame $c"
  reprise "$c"
done
sleep 3
for r in $(seq 0 $((N - 1))); do printf 'command=stop\n' > "$RUN/runner$r/auto/commands/z.txt"; done
sleep 12
ps_lignes "Get-CimInstance Win32_Process | Where-Object { \$_.Name -match 'moderngekko' -or (\$_.Name -eq 'python.exe' -and \$_.CommandLine -like '*relais.py*') } | ForEach-Object { taskkill /F /T /PID \$_.ProcessId | Out-Null }"
grep -h "GO\|DIVERGENCE" "$RUN/relais.log" | head -5; grep -h "parti" "$RUN/relais.log" | tail -1
# 4. Les planches.
"$PY" - "$(w "$RUN")" <<'PY'
import sys, glob, os, collections
from PIL import Image, ImageDraw
run = sys.argv[1]
groupes = collections.defaultdict(list)
for p in sorted(glob.glob(os.path.join(run, "*_j*.png"))):
    groupes[os.path.basename(p).rsplit("_j", 1)[0]].append(p)
for nom, ps in groupes.items():
    ims = [Image.open(p).convert("RGB") for p in ps]
    w = 640; tiles = [im.resize((w, int(w * im.size[1] / im.size[0]))) for im in ims]
    h = max(t.size[1] for t in tiles); cols = 4 if len(tiles) > 2 else len(tiles)
    c = Image.new("RGB", (w * cols, h * ((len(tiles) + cols - 1) // cols)), (0, 0, 0))
    for i, (t, p) in enumerate(zip(tiles, ps)):
        c.paste(t, ((i % cols) * w, (i // cols) * h))
        ImageDraw.Draw(c).text(((i % cols) * w + 8, (i // cols) * h + 30), "Joueur " + p.rsplit("_j", 1)[1][:-4], fill=(255, 255, 0))
    c.save(os.path.join(run, f"planche_{nom}.png"))
    print("planche", nom, len(ps))
PY
echo "RUN=$RUN"
