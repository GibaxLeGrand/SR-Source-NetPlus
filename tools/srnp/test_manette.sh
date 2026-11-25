#!/usr/bin/env bash
# Test de Gibax à la manette : 2 runners sur ce poste, en lockstep par le relais.
#   - runner 0 (siège 0, racer 0) : la vraie manette (SRNP_INPUT=manette), lue sur le port 4 que le jeu
#     ne voit pas (SIDevice3 = aucun) ; elle n'atteint le jeu que par le relais, sur les deux runners ;
#   - runner 1 (siège 1, racer 1) : neutre, ou une 2e manette (MANETTE2=<nom>) ; sa caméra sur son
#     racer (CAM1=1 ; CAM1=0 pour suivre le racer de Gibax) ;
#   - aucun port du jeu ne prend une manette directement : chaque manette est nommée sur un port que le
#     jeu ne voit pas (4 : celle du runner, lue ; 3 : celle de l'autre, réservée), et le port 1 garde le
#     clavier sans touche : Dolphin y mettrait sinon la première manette libre (EffectivePadDevices), et
#     sans appareil le Start du relais n'atteint plus le menu. Un Start local ne met donc pas un seul
#     runner en pause ;
#   - départ depuis « Are you ready? » : Gibax appuie sur Start ; sommes de contrôle du relais à la fin.
#   test_manette.sh            (fermer les fenêtres pour finir)
# MANETTE=SDL/0/Xbox One Controller par défaut (XInput/0/Gamepad ne donnait rien le 25/11), MANETTE2,
# ETAT=<state> (course1p : la course tourne déjà), CAM1, DELAI, ENTREE0=ia (vérifier le Start du menu
# sans manette : le siège 0 appuie seul sur Start).
set -uo pipefail
W=/d/_SonicRidersSource/work
CHASSIS="${CHASSIS:-$W/chassis_p2}"
PY="/c/Program Files/Python313/python.exe"
RELAIS=/d/_SonicRidersSource/SR-Source-NetPlus/tools/srnp/relais.py
STATE="${ETAT:-$W/states/gxee8p_pret1p_100pc_metal_1tour_jit.sav}"
MANETTE="${MANETTE:-SDL/0/Xbox One Controller}"
MANETTE2="${MANETTE2:-}"
RUN="$W/runs/$(date +%Y%m%d-%H%M%S)-manette"
mkdir -p "$RUN"
w() { cygpath -w "$1"; }
autres=$(tasklist.exe | grep -ci moderngekko)
if [[ "$autres" != 0 ]]; then echo "$autres runner(s) déjà ouverts : ferme-les d'abord (ils voleraient des perfs)"; exit 1; fi
"$PY" -I "$RELAIS" --sieges 2 --port 7846 --journal "$(w "$RUN/relais.log")" > "$RUN/relais.out" 2>&1 &
sleep 1
lance() {  # lance <siège> <entrée> <caméra> <son> <manette lue> <manette réservée>
  local r=$1 D="$RUN/runner$1"
  mkdir -p "$D/ck"
  cp -a "$W/userdir_modele" "$D/userdir"
  sed -i "s/^\[Core\]\$/[Core]\nEmulationSpeed = 1.0\nSIDevice2 = 0\nSIDevice3 = 0/" "$D/userdir/Config/Dolphin.ini"
  sed -i 's/^\[Interface\]$/[Interface]\nUsePanicHandlers = False/' "$D/userdir/Config/Dolphin.ini"
  # La manette lue même sans le focus et sous l'interface ImGui (écran d'attente, menu) : sinon
  # Dolphin coupe les entrées (Core::UpdateInputGate).
  sed -i 's/^BackgroundInput = False$/BackgroundInput = True/' "$D/userdir/Config/Dolphin.ini"
  # Le port 1 garde le clavier (sans touche) ; port 4 : la manette lue ; port 3 : l'autre, réservée.
  local cartes=""
  cartes="[GCPad1]
Device = DInput/0/Keyboard Mouse
Options/Always Connected = True
"
  [[ -n "$6" ]] && cartes+="[GCPad3]
Device = $6
"
  [[ -n "$5" ]] && cartes+="[GCPad4]
Device = $5
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
"
  printf '%s' "$cartes" > "$D/userdir/Config/GCPadNew.ini"
  mkdir -p "$D/userdir/Mods/srnp_etiquettes"
  printf 'name=srnp_etiquettes\ngame=GXEE8P\n' > "$D/userdir/Mods/srnp_etiquettes/mod.ini"
  powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(w "$D/userdir/Mods/srnp_etiquettes/files")' -Target '$(w "$W/etiquettes/mods/srnp_etiquettes/files")' | Out-Null"
  printf 'mod=srnp_etiquettes\n' >> "$D/userdir/config.ini"
  local SON=--mute; [[ "$4" == son ]] && SON=
  (cd "$CHASSIS" && SRNP_RELAY=127.0.0.1:7846 SRNP_SEAT=$r SRNP_SEATS=2 SRNP_RACERS=1 SRNP_INPUT=$2 \
     SRNP_CAMERA=$3 SRNP_DELAY="${DELAI:-2}" SRNP_CHECK=60 SRNP_CKDUMP="$(w "$D/ck")" \
     MODERNGEKKO_STATICRECOMP=1 ./moderngekko-run.exe --game "$(w "$W/games/GXEE8P")" --user-dir "$(w "$D/userdir")" \
     $SON --load-state "$(w "$STATE")" --module "$(w "$CHASSIS/gGXEE8P_recomp.dll")" > "$D/runner.log" 2>&1) &
  echo "$(date +%T) runner $r lancé (entrée $2, caméra sur le racer $3)"
}
lance 0 "${ENTREE0:-manette}" 0 son "$MANETTE" "$MANETTE2"
sleep 12
if [[ -n "$MANETTE2" ]]; then
  lance 1 manette "${CAM1:-1}" muet "$MANETTE2" "$MANETTE"
else
  lance 1 neutre "${CAM1:-1}" muet "$MANETTE" ""   # la manette de Gibax réservée, pas lue
fi
echo "Gibax : la manette pilote le racer 0 (Start pour partir). Fermer les deux fenêtres pour finir."
wait $(jobs -p | tail -2) 2>/dev/null
sleep 2
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { (\$_.Name -match 'moderngekko' -or \$_.Name -eq 'python.exe') -and \$_.CommandLine -like '*$(basename "$RUN")*' } | ForEach-Object { taskkill /F /T /PID \$_.ProcessId | Out-Null }"
grep -h "input:" "$RUN"/runner*/runner.log | head -4
grep -h "DIVERGENCE\|parti" "$RUN/relais.log" | tail -3
"$PY" -I "$W/phase2/compare_ck.py" "$(w "$RUN")" 2 | tail -3
echo "RUN=$RUN"
