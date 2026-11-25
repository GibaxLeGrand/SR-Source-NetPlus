#!/usr/bin/env bash
# Pilote un runner qui reste ouvert, commande par commande (phase 2 : traverser les menus).
#   pilote.sh start <étiquette> [jit|natif] [save state]  : lance le runner (dossier utilisateur neuf)
#   pilote.sh appui <frames> <champs…>                    : pad_frames sur le port 0 (ex. a=1, main_x=-1)
#   pilote.sh port <port> <frames> <champs…>               : pad_frames sur un autre port
#   pilote.sh attendre <frames>                            : laisse tourner sans entrée
#   pilote.sh pause | reprendre
#   pilote.sh capture <nom>                                : capture dans le dossier du run
#   pilote.sh lire <adresse hex> <taille> <nom>            : read_memory dans le dossier du run
#   pilote.sh ecrire <adresse hex> <octets hex>            : write_memory
#   pilote.sh sauver <nom>                                 : save_state dans le dossier du run
#   pilote.sh stop
# L'état (RUN, PID) est dans phase2/pilote.etat.
set -uo pipefail
WORK=/d/_SonicRidersSource/work
CHASSIS=/d/_SonicRidersSource/SR-Source-NetPlus/build/chassis
ETAT="$WORK/phase2/pilote.etat"
w() { cygpath -w "$1"; }

envoie() {  # envoie <nom> <contenu> : dépose la commande et attend qu'elle soit traitée (120 s)
  local nom="$(date +%H%M%S%N)_$1"
  printf '%s\n' "$2" > "$AUTO/$nom.tmp" && mv "$AUTO/$nom.tmp" "$AUTO/commands/$nom.txt"
  local t0=$SECONDS
  while :; do
    [[ -f "$AUTO/processed/$nom.txt" ]] && return 0
    [[ -f "$AUTO/failed/$nom.txt" ]] && { echo "!! commande échouée : $nom"; cat "$AUTO/failed/$nom.txt"; return 1; }
    kill -0 "$PID" 2>/dev/null || { echo "!! runner sorti"; return 1; }
    (( SECONDS - t0 > 120 )) && { echo "!! commande pas traitée en 120 s : $nom"; return 1; }
    sleep 0.2
  done
}
frame() { grep -E "^frame_count=" "$AUTO/status.txt" 2>/dev/null | cut -d= -f2-; }

c="${1:?commande}"; shift
if [[ "$c" == start ]]; then
  ET="${1:?étiquette}"; MODE="${2:-jit}"; SAV="${3:-}"
  if tasklist 2>/dev/null | grep -qi "moderngekko-run"; then echo "!! un runner tourne déjà"; exit 1; fi
  RUN="$WORK/runs/$(date +%Y%m%d-%H%M%S)-$MODE-$ET"; AUTO="$RUN/auto"
  mkdir -p "$AUTO/commands"
  cp -a "$WORK/userdir_modele" "$RUN/userdir" || exit 2
  sed -i 's/^\[Interface\]$/[Interface]\nUsePanicHandlers = False/' "$RUN/userdir/Config/Dolphin.ini"
  ARGS=(--game "$(w "$WORK/games/GXEE8P")" --user-dir "$(w "$RUN/userdir")"
        --automation-dir "$(w "$AUTO")" --no-mods --mute)
  [[ -n "$SAV" ]] && ARGS+=(--load-state "$(w "$SAV")")
  case "$MODE" in
    jit)   export MODERNGEKKO_STATICRECOMP=0 ;;
    natif) export MODERNGEKKO_STATICRECOMP=1; ARGS+=(--module "$(w "$CHASSIS/gGXEE8P_recomp.dll")") ;;
    *) echo "mode inconnu"; exit 2 ;;
  esac
  cd "$CHASSIS" || exit 2
  ./moderngekko-run.exe "${ARGS[@]}" > "$RUN/runner.log" 2>&1 &
  PID=$!
  printf 'RUN=%q\nAUTO=%q\nPID=%q\n' "$RUN" "$AUTO" "$PID" > "$ETAT"
  echo "runner $PID -> $RUN"
  exit 0
fi

source "$ETAT"
case "$c" in
  appui)    F="$1"; shift; envoie appui "command=pad_frames
port=0
frames=$F
$(printf '%s\n' "$@")" ;;
  port)     P="$1"; F="$2"; shift 2; envoie port "command=pad_frames
port=$P
frames=$F
$(printf '%s\n' "$@")" ;;
  attendre) envoie attendre "command=pad_frames
port=0
frames=$1" ;;
  jusqua)   # jusqua <frame> : reprend et met en pause exactement à cette frame du présentateur
            envoie jusqua "command=pad_frames
port=0
frames=1
pause_at=$1" ;;
  tenir)    # tenir <frame> <champs…> : tient ces entrées sur le port 0 jusqu'à la pause exacte à cette frame
            F="$1"; shift; envoie tenir "command=pad_frames
port=0
frames=1
pause_at=$F
$(printf '%s\n' "$@")" ;;
  charger)  envoie charger "command=load_state
path=$(w "$1")" ;;
  pause)     envoie pause "command=pause" ;;
  reprendre) envoie reprendre "command=resume" ;;
  capture)  envoie capture "command=screenshot
path=$(w "$RUN/$1.png")" && echo "$RUN/$1.png" ;;
  lire)     envoie lire "command=read_memory
address=0x$1
size=$2
path=$(w "$RUN/$3.bin")" && echo "$RUN/$3.bin" ;;
  ecrire)   envoie ecrire "command=write_memory
address=0x$1
data=$2" ;;
  sauver)   envoie sauver "command=save_state
path=$(w "$RUN/$1.sav")" && echo "$RUN/$1.sav" ;;
  pas)      # pas <nom> <attente> <champs…> : reprendre, appui de 5 frames, attente, capture, pause
            NOM="$1"; ATT="$2"; shift 2
            envoie reprendre "command=resume" && envoie appui "command=pad_frames
port=0
frames=5
$(printf '%s\n' "$@")" && envoie attendre "command=pad_frames
port=0
frames=$ATT" && envoie capture "command=screenshot
path=$(w "$RUN/$NOM.png")" && envoie attendre "command=pad_frames
port=0
frames=3" && envoie pause "command=pause" && echo "$RUN/$NOM.png" ;;
  stop)     envoie stop "command=stop"; sleep 3; kill -0 "$PID" 2>/dev/null && echo "!! runner encore là" ;;
  *) echo "commande inconnue : $c"; exit 2 ;;
esac
echo "frame=$(frame)"
