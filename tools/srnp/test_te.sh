#!/usr/bin/env bash
# SR-Source Net Plus, phase 2.5 : Tournament Edition (GXSRTE) comme troisième jeu du launcher, hors ligne.
#   1. SR-Source.exe --extract <ISO TE> dans un dossier utilisateur de test (games\GXSRTE) ;
#   2. photo du launcher (page PLAY : les trois jeux) ;
#   3. le runner qui connaît GXSRTE (runner_te) lance TE en muet (JIT64 : pas de module natif de TE) ;
#      photos à 25 et 50 s, puis fermé.
set -uo pipefail
W=/d/_SonicRidersSource/work
L=$W/launcher_online
ISO_TE="/d/_SonicRidersTE/RidersDolphin3WindowsV1.0.2/RidersDolphin3Windows/x64/Games/Place Vanilla Riders ISO here/Sonic Riders TE.iso"
RUN="$L/runs/$(date +%Y%m%d-%H%M%S)-te"
w() { cygpath -w "$1"; }
autres=$(tasklist.exe | grep -ciE "moderngekko|SR-Source")
if [[ "$autres" != 0 ]]; then echo "$autres processus SR-Source ouverts : rien lancé"; exit 1; fi
U="$RUN/lad/sr-source"
mkdir -p "$U/Logs"
cp -a "$W/userdir_modele/Config" "$U/Config"
sed -e 's/^music_volume=.*/music_volume=0/' -e 's/^game_volume=.*/game_volume=0/' \
    -e 's/^check_for_updates=.*/check_for_updates=false/' "$W/userdir_modele/config.ini" > "$U/config.ini"
w "$W/games/GXEE8P" > "$U/default-game.txt"
t0=$(date +%s)
(cd "$L" && env LOCALAPPDATA="$(w "$RUN/lad")" ./SR-Source.exe --extract "$(w "$ISO_TE")" > "$RUN/extraction.out" 2>&1)
echo "extraction : code $? en $(( $(date +%s) - t0 )) s : $(tr -d '\r' < "$RUN/extraction.out" | tail -2)"
ls "$U/games" 2>/dev/null
photo() { powershell -NoProfile -ExecutionPolicy Bypass -File "$(w "$L/photo_pid.ps1")" -ProcessId "$1" -Png "$(w "$2")"; }
pid_de() {
  powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"name='$1'\" | Where-Object { \$_.CommandLine -like '*$2*' } | Select-Object -First 1).ProcessId" | tr -d '\r'
}
# 2. Le launcher, page PLAY.
(cd "$L" && env LOCALAPPDATA="$(w "$RUN/lad")" MODERNGEKKO_LAUNCHER_PAGE=0 ./SR-Source.exe --x11 "te-$(basename "$RUN")" > "$RUN/launcher.out" 2>&1) &
sleep 9
LA=$(pid_de SR-Source.exe "te-$(basename "$RUN")")
photo "$LA" "$RUN/launcher_play.png"
taskkill.exe //F //PID "$LA" > /dev/null 2>&1
# 3. TE hors ligne, muet.
(cd "$L/runner_te" && ./moderngekko-run.exe --game "$(w "$U/games/GXSRTE")" --user-dir "$(w "$U")" --mute > "$RUN/runner.log" 2>&1) &
sleep 5
RA=$(pid_de moderngekko-run.exe "$(basename "$RUN")")
for t in 25 50; do
  sleep $(( t - ${prev:-5} )); prev=$t
  photo "$RA" "$RUN/te_${t}s.png"
done
taskkill.exe //F //PID "$RA" > /dev/null 2>&1
sleep 1
grep -aE "cpu core|disc|invalid|unsupported|error|GXSRTE|mods:" "$RUN/runner.log" | head -12
echo "RUN=$RUN"
