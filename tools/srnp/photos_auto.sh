#!/usr/bin/env bash
# Photos des fenêtres d'un run toutes les N secondes, tant que ses runners tournent.
#   photos_auto.sh <dossier du run> [secondes, défaut 2] [runners, défaut 2]
#   (photos dans <run>/photos/<numéro>_j<k>.png ; s'arrête quand plus aucun runner du run ne tourne)
set -uo pipefail
RUN=$1; P="${2:-2}"; N="${3:-2}"
W=/d/_SonicRidersSource/work
w() { cygpath -w "$1"; }
mkdir -p "$RUN/photos"
i=0
while powershell -NoProfile -Command "@(Get-CimInstance Win32_Process | Where-Object { \$_.Name -match 'moderngekko' -and \$_.CommandLine -like '*$(basename "$RUN")*' }).Count" | tr -d '\r' | grep -qv '^0$'; do
  i=$((i + 1))
  n=$(printf '%03d' $i)
  for k in $(seq 0 $((N - 1))); do
    powershell -NoProfile -ExecutionPolicy Bypass -File "$(w "$W/phase2/capture_fenetre.ps1")" \
      -Motif "$(basename "$RUN")\\runner$k\\" -Png "$(w "$RUN/photos/${n}_j$((k + 1)).png")" > /dev/null 2>&1
  done
  sleep "$P"
done
echo "$i photos par fenêtre dans $RUN/photos"
