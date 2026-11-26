#!/usr/bin/env bash
# (Copie de work/te/module/pilote_te.sh, session de la phase 2 : mon runner, RUN_TE obligatoire.)
# Phase 2.5 : piloter TE en JIT64 (muet) par le dossier d'automatisation, commande par commande, pour aller
# jusqu'à une course et y faire la sauvegarde d'état de l'entraînement PGO (comme gxee8p_demo_f8850_jit.sav).
#   pilote_te.sh lancer                 : démarre le runner (premier plan : à lancer en arrière-plan)
#   pilote_te.sh presse <champs> [n]    : ex. "a=1" 4 : tient ces commandes n images (6), puis relâche 20 images
#   pilote_te.sh attend <n>             : n images sans rien
#   pilote_te.sh photo <nom>            : capture dans le dossier du run
#   pilote_te.sh sauve <fichier .sav>   : pause, sauvegarde d'état, reprise
#   pilote_te.sh stop
set -uo pipefail
W=/d/_SonicRidersSource/work
RUN="${RUN_TE:?RUN_TE=<dossier du run>}"
AUTO="$RUN/auto"
w() { cygpath -w "$1"; }
n=$(ls "$AUTO/commands" "$AUTO/processed" "$AUTO/failed" 2>/dev/null | grep -c '\.txt$')
nom() { printf '%03d_%s' "$n" "$1"; n=$((n + 1)); }
cmd() {  # cmd <nom> <contenu> : écrit la commande, attend qu'elle soit traitée (limite 120 s)
  local c; c=$(nom "$1")
  printf '%s\n' "$2" > "$AUTO/$c.tmp" && mv "$AUTO/$c.tmp" "$AUTO/commands/$c.txt"
  for i in $(seq 1 1200); do
    [[ -f "$AUTO/processed/$c.txt" ]] && return 0
    [[ -f "$AUTO/failed/$c.txt" ]] && { echo "!! $c a échoué"; cat "$AUTO/failed/$c.txt"; return 1; }
    sleep 0.1
  done
  echo "!! $c pas traitée en 120 s"; return 1
}
case "${1:?commande}" in
  lancer)
    [[ -e "$RUN" ]] && { echo "!! $RUN existe déjà"; exit 2; }
    autres=$(tasklist.exe | grep -ciE "moderngekko|SR-Source")
    [[ "$autres" != 0 ]] && { echo "$autres processus SR-Source ouverts : rien lancé"; exit 1; }
    mkdir -p "$AUTO/commands"
    cp -a "$W/userdir_modele" "$RUN/userdir"
    sed -i -e 's/^game_volume=.*/game_volume=0/' -e 's/^music_volume=.*/music_volume=0/' "$RUN/userdir/config.ini"
    cd "$W/te/runner" || exit 2
    MODERNGEKKO_STATICRECOMP=0 exec ./moderngekko-run.exe --game "$(w "$W/te/lad/sr-source/games/GXSRTE")" \
      --user-dir "$(w "$RUN/userdir")" --mute --automation-dir "$(w "$AUTO")" > "$RUN/runner.log" 2>&1
    ;;
  presse)
    champs="${2:?champs}"; f="${3:-6}"
    cmd presse "command=pad_frames
port=0
frames=$f
${champs// /$'\n'}" && cmd relache "command=pad_frames
port=0
frames=20"
    ;;
  attend) cmd attend "command=pad_frames
port=0
frames=${2:?n}" ;;
  photo) cmd photo "command=screenshot
path=$(w "$RUN/${2:?nom}.png")"
    for i in $(seq 1 50); do [[ -s "$RUN/$2.png" ]] && break; sleep 0.1; done; echo "$RUN/$2.png" ;;
  sauve)
    S="${2:?fichier}"; [[ -e "$S" ]] && { echo "!! $S existe déjà"; exit 2; }
    cmd pause "command=pause" && cmd sauve "command=save_state
path=$(w "$S")" || exit 1
    last=-1
    for i in $(seq 1 60); do s=$(stat -c %s "$S" 2>/dev/null || echo 0); (( s > 0 && s == last )) && break; last=$s; sleep 1; done
    ls -la "$S"; cmd reprise "command=resume" ;;
  stop) cmd stop "command=stop" ;;
  *) echo "commande inconnue"; exit 2 ;;
esac
