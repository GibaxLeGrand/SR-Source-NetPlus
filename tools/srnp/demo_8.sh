#!/usr/bin/env bash
# Démo à 8 joueurs : tout ce que fait SR-Source Net Plus aujourd'hui, en photos des vraies fenêtres.
#   - avant tout : aucun processus Sonic Riders Source ne doit tourner (restes d'une démo arrêtés,
#     runners des autres sessions attendus) ;
#   - 8 runners natifs sur ce poste, un siège chacun, lancés à ECART s d'écart : l'écran d'attente se
#     remplit (photos du runner 0 et de tous) ;
#   - GO, course complète depuis « Are you ready? » (les 8 racers conduits par l'IA, SRNP_TOUS_CPU=1) :
#     chaque runner sa caméra, son HUD, sa mini-carte, son spotter, les étiquettes 5P-8P du mod ;
#   - photos des 8 fenêtres aux frames du jeu CAPT1, CAPT2, CAPT3 (pause à la même frame partout :
#     SRNP_PAUSE_JEU=1) ; sommes de contrôle du relais ; SRNP_IA_JOUEUR=1 : racers « nP » conduits par l IA ;
#   - planches (une par moment) dans le dossier du run.
#   demo_8.sh [CAPT...]   (frames du jeu, défaut 1900 3125 5650 ; au moins ~400 frames d'écart : sinon la
#   pause arrive après la frame visée et chaque runner s'arrête où il en est)
set -uo pipefail
CAPTS=("${@:-}"); [[ -z "${CAPTS[0]:-}" ]] && CAPTS=(1900 3125 5650)   # frames du jeu (SRNP_PAUSE_JEU)
N="${N:-8}"
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
# 1. Aucun autre processus Sonic Riders Source : ils voleraient des perfs. Les restes d'une démo
#    précédente sont arrêtés ; ceux des autres sessions (tests des étiquettes...) ne sont pas tués :
#    on attend qu'ils finissent (ATTENDRE=0 : ne pas attendre, pour un test de charge voulu).
ps_lignes "Get-CimInstance Win32_Process | Where-Object { (\$_.Name -match 'moderngekko' -or \$_.Name -eq 'python.exe') -and \$_.CommandLine -like '*-demo-8*' } | ForEach-Object { taskkill /F /T /PID \$_.ProcessId | Out-Null; 'arrêté ' + \$_.ProcessId + ' ' + \$_.Name }"
if [[ "${ATTENDRE:-1}" != 0 ]]; then
  for i in $(seq 1 180); do
    autres=$(tasklist.exe | grep -ci moderngekko)
    [[ "$autres" == 0 ]] && break
    [[ $i == 1 ]] && echo "$(date +%T) $autres runner(s) d'une autre session : j'attends qu'ils finissent"
    sleep 5
  done
fi
sleep 2
"$PY" -I "$RELAIS" --sieges $N --port 7845 --journal "$(w "$RUN/relais.log")" > "$RUN/relais.out" 2>&1 &
sleep 1
# TAGS_RELAIS="T0,T1,..." : chaque runner n'a que son tag (SRNP_TAG) ; ceux des autres viennent du relais.
tag_de() { [[ -n "${TAGS_RELAIS:-}" ]] && echo "$TAGS_RELAIS" | cut -d, -f$(($1 + 1)) || true; }
# LOBBY=1 : le lobby à l'essai (choix du perso sur l'écran d'attente) ; LOBBY_AUTO="c/g/s[/b];..." : le
# choix automatique de chaque runner (perso/planche/secondes avant d'être prêt ; b : B b secondes plus
# tard, retour au choix, puis prêt de nouveau b secondes après).
auto_de() { [[ -n "${LOBBY_AUTO:-}" ]] && echo "$LOBBY_AUTO" | cut -d';' -f$(($1 + 1)) || true; }
# LOBBY_KEYS="RRUA;LDDA;..." : les touches simulées de chaque runner (L R U D A B, une toutes les 0,5 s
# après 3 s ; à la place de la manette, par le même chemin).
# ENTREES="course;neutre;..." : l entrée de chaque runner (défaut ia : l IA conduit) ; avec des humains,
# TOUS_CPU=0.
entree_de() { local e=""; [[ -n "${ENTREES:-}" ]] && e=$(echo "$ENTREES" | cut -d";" -f$(($1 + 1))); echo "${e:-ia}"; }
touches_de() { [[ -n "${LOBBY_KEYS:-}" ]] && echo "$LOBBY_KEYS" | cut -d';' -f$(($1 + 1)) || true; }
lance() {  # lance <siège>
  local r=$1 D="$RUN/runner$1"
  mkdir -p "$D/auto/commands" "$D/ck"
  cp -a "$W/userdir_modele" "$D/userdir"
  sed -i "s/^\[Core\]\$/[Core]\nEmulationSpeed = 1.0/" "$D/userdir/Config/Dolphin.ini"
  sed -i 's/^\[Interface\]$/[Interface]\nUsePanicHandlers = False/' "$D/userdir/Config/Dolphin.ini"
  if [[ "${ETIQ:-1}" != 0 ]]; then  # ETIQ=0 : sans le mod des étiquettes 5P-8P
    mkdir -p "$D/userdir/Mods/srnp_etiquettes"
    printf 'name=srnp_etiquettes\ngame=GXEE8P\n' > "$D/userdir/Mods/srnp_etiquettes/mod.ini"
    powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(w "$D/userdir/Mods/srnp_etiquettes/files")' -Target '$(w "$W/etiquettes/mods/srnp_etiquettes/files")' | Out-Null"
    printf 'mod=srnp_etiquettes\n' >> "$D/userdir/config.ini"
  fi
  local SON=--mute; [[ -n "${SON_RUNNER:-}" && "$r" == "$SON_RUNNER" ]] && SON=   # muet par défaut (Gibax dort, 26/11)
  (cd "$CHASSIS" && SRNP_RELAY=127.0.0.1:7845 SRNP_SEAT=$r SRNP_SEATS=$N SRNP_RACERS=1 SRNP_TOUS_CPU="${TOUS_CPU:-1}" \
     SRNP_PERSOS="$PERSOS" SRNP_INPUT="$(entree_de "$r")" SRNP_CHECK=60 SRNP_PAUSE_JEU=1 SRNP_TAG="$(tag_de "$r")" SRNP_LOBBY="${LOBBY:-0}" SRNP_LOBBY_AUTO="$(auto_de "$r")" SRNP_LOBBY_KEYS="$(touches_de "$r")" SRNP_CKDUMP="$(w "$D/ck")" \
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
# PHOTOS_ATTENTE="5 15 24" : photos de toutes les fenêtres pendant l'attente (le lobby), à ces secondes
# après le dernier lancement.
t0=$(date +%s)
for s in ${PHOTOS_ATTENTE:-}; do
  while (( $(date +%s) - t0 < s )); do sleep 0.5; done
  for k in $(seq 0 $((N - 1))); do fenetre $k "lobby_${s}s"; done
  echo "$(date +%T) photos de l'attente à ${s} s"
done
# RAFALE_GO="<secondes>:<nombre>" : <nombre> captures de chaque runner (toutes les RAFALE_PAS s, 0,1 par
# défaut), <secondes> après le GO du relais, sans pause : l'intro du niveau (une pause avant la course
# tomberait dans le lobby, où les frames comptent déjà).
if [[ -n "${RAFALE_GO:-}" ]]; then
  for i in $(seq 1 1200); do grep -q ": GO" "$RUN/relais.log" 2>/dev/null && break; sleep 0.5; done
  echo "$(date +%T) GO du relais"
  sleep "${RAFALE_GO%%:*}"
  "$PY" -I "$(w "$W/phase2/rafale.py")" "$(w "$RUN")" "$N" "${RAFALE_GO##*:}" "${RAFALE_PAS:-0.1}"
  for i in $(seq 1 60); do [[ -z "$(ls "$RUN"/runner*/auto/commands/s*.txt 2>/dev/null)" ]] && break; sleep 0.5; done
  sleep 1
  "$PY" "$(w "$W/phase2/rafale_planche.py")" "$(w "$RUN")" "$N"
fi
# 3. La course : les moments demandés, les N fenêtres. VIDAGE=1 : MEM1 (bas, 16 Mo) du runner VIDAGE_RUNNER (0) à chaque
#    moment, dans <run>/f<frame>_lo.bin (hors dépôt : c'est la mémoire du jeu).
vide_ram() {  # vide_ram <frame>
  local f="$RUN/f$1_lo.bin" nom="v$1"
  commande "${VIDAGE_RUNNER:-0}" "$nom" "command=read_memory\naddress=0x80000000\nsize=16777216\npath=$(w "$f" | sed 's/\\/\\\\/g')\n"
  for i in $(seq 1 120); do [[ -f "$RUN/runner${VIDAGE_RUNNER:-0}/auto/processed/$nom.txt" ]] && break; sleep 0.5; done
}
# ECRIT="<frame>=<adresse>:<hex>,..." : à la pause de cette frame, ces octets écrits sur TOUS les runners
#    (la même frame partout : la course reste la même pour tous ; pour tester une situation donnée).
ecrit() {  # ecrit <frame>
  local e
  for e in ${ECRIT//,/ }; do
    [[ "${e%%=*}" == "$1" ]] || continue
    local a="${e#*=}"; a="${a%%:*}" h="${e##*:}"
    for r in $(seq 0 $((N - 1))); do commande $r "e$1$r" "command=write_memory\naddress=$a\ndata=$h\n"; done
    for r in $(seq 0 $((N - 1))); do
      for i in $(seq 1 60); do [[ -f "$RUN/runner$r/auto/processed/e$1$r.txt" ]] && break; sleep 0.25; done
    done
    echo "$(date +%T) frame $1 : $h écrit en $a sur les $N runners"
  done
}
for c in "${CAPTS[@]}"; do
  pause_a "$c"
  for r in $(seq 0 $((N - 1))); do fenetre $r "course_f$c"; done
  [[ "${VIDAGE:-0}" == 1 ]] && vide_ram "$c"
  [[ -n "${ECRIT:-}" ]] && ecrit "$c"
  echo "$(date +%T) photos à la frame $c"
  reprise "$c"
  # RAFALE="<frame>:<nombre>" : juste après la reprise de cette frame, <nombre> captures de chaque runner
  # (commande screenshot du runner, sans pause) toutes les 0,1 s, dans <run>/rafale/j<k>_<n>.png.
  # Elles partent ~1,5 s de jeu après la reprise : viser la pause plus tôt ; le chrono à l'image fait foi.
  if [[ -n "${RAFALE:-}" && "${RAFALE%%:*}" == "$c" ]]; then
    "$PY" -I "$(w "$W/phase2/rafale.py")" "$(w "$RUN")" "$N" "${RAFALE##*:}" "${RAFALE_PAS:-0.1}"
    for i in $(seq 1 60); do [[ -z "$(ls "$RUN"/runner*/auto/commands/s*.txt 2>/dev/null)" ]] && break; sleep 0.5; done
    sleep 1   # la dernière image s'écrit après le traitement de sa commande
    "$PY" "$(w "$W/phase2/rafale_planche.py")" "$(w "$RUN")" "$N"
    echo "$(date +%T) rafale : $(ls "$RUN/rafale" | wc -l) captures"
  fi
done
sleep 3
for r in $(seq 0 $((N - 1))); do printf 'command=stop\n' > "$RUN/runner$r/auto/commands/z.txt"; done
sleep 12
# Seulement les processus de ce run (runners et relais), jamais ceux des autres sessions.
ps_lignes "Get-CimInstance Win32_Process | Where-Object { (\$_.Name -match 'moderngekko' -or \$_.Name -eq 'python.exe') -and \$_.CommandLine -like '*$(basename "$RUN")*' } | ForEach-Object { taskkill /F /T /PID \$_.ProcessId | Out-Null }"
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
