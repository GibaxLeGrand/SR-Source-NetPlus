#!/usr/bin/env bash
# Phase 2 : save state d'une Free Race où les 8 racers sont des CPU au montage (Metal City, 1 tour).
# Part de l'écran « Are you ready? » (states/gxee8p_pret1p_metal_1tour_jit.sav), appuie sur Start, puis
# frame après frame (pause exacte) : dès que le menu a écrit les CPU (racer 1 +0xBA != 0xFF), remet le
# racer 0 en CPU (+0xBC = +0xBD = 1), jusqu'à ce que les racers soient sur la ligne de départ
# (racer 0 : z = -202,4, vitesse nulle) ; là, save state, racers lus, capture.
set -uo pipefail
cd "$(dirname "$0")"
W=/d/_SonicRidersSource/work
bash pilote.sh start depart8cpu jit "$W/states/gxee8p_pret1p_metal_1tour_jit.sav" > /dev/null || exit 1
sleep 8
source pilote.etat
P() { timeout 60 bash pilote.sh "$@" | tail -1; }
P pause > /dev/null
F0=$(grep frame_count "$AUTO/status.txt" | cut -d= -f2)
P reprendre > /dev/null
F=$((F0 + 30))
P tenir "$F" start=1 > /dev/null
ecrits=0
for i in $(seq 1 400); do
  F=$((F + 2))
  P reprendre > /dev/null
  r=$(P jusqua "$F")
  bash pilote.sh lire 80609440 8448 r01 > /dev/null
  set -- $(python -c "
import sys, struct
b = open(sys.argv[1] + '/r01.bin', 'rb').read()
print(b[0x1080 + 0xBA], b[0xBC], b[0x1034], round(struct.unpack_from('>f', b, 0x1E4 + 8)[0], 1),
      round(struct.unpack_from('>f', b, 0xAAC)[0] * 216, 1))" "$(cygpath -w "$RUN")")
  if [[ $1 != 255 && $2 != 1 ]]; then
    bash pilote.sh ecrire 806094FC 0101 > /dev/null
    ecrits=$((ecrits + 1))
  fi
  if (( ecrits > 0 )) && [[ $4 == "-202.4" && $5 == "0.0" ]]; then
    echo "sur la ligne : F=$F ($r) BC0=$2 état=$3 ; racer 0 remis en CPU $ecrits fois"
    break
  fi
done
bash pilote.sh lire 80609440 33792 depart > /dev/null
bash pilote.sh sauver course_8cpu_depart
P reprendre > /dev/null
P capture depart > /dev/null
P attendre 2 > /dev/null
P pause > /dev/null
python racers.py "$(cygpath -w "$RUN")" depart | grep -E "racer|depart" | cut -c1-110
