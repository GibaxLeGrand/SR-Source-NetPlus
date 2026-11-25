#!/usr/bin/env bash
# Le jeu normal : le runner démarre le jeu comme d'habitude (écran-titre, menus), sans relais ni save
# state, la manette de Gibax sur le port 1 (MANETTE, défaut SDL/0/Xbox One Controller), avec le son.
#   jeu_normal.sh      (fermer la fenêtre pour finir)
set -uo pipefail
W=/d/_SonicRidersSource/work
CHASSIS="${CHASSIS:-$W/chassis_p2}"
MANETTE="${MANETTE:-SDL/0/Xbox One Controller}"
RUN="$W/runs/$(date +%Y%m%d-%H%M%S)-jeu"
D="$RUN/runner0"
w() { cygpath -w "$1"; }
mkdir -p "$D"
cp -a "$W/userdir_modele" "$D/userdir"
sed -i "s/^\[Core\]\$/[Core]\nEmulationSpeed = 1.0/" "$D/userdir/Config/Dolphin.ini"
sed -i 's/^\[Interface\]$/[Interface]\nUsePanicHandlers = False/' "$D/userdir/Config/Dolphin.ini"
sed -i 's/^BackgroundInput = False$/BackgroundInput = True/' "$D/userdir/Config/Dolphin.ini"
# BOUTONS=1 (défaut) : le pack UniversalDynamicInput (work\dit, téléchargé avec l'accord de Gibax ; jamais
# dans un dépôt) dans Load\DynamicInputTextures, en vraies copies (Dolphin ne suit pas les jonctions) :
# les boutons du jeu dessinés selon la manette (patch 0035).
if [[ "${BOUTONS:-1}" != 0 && -d "$W/dit/DynamicInputTextures" ]]; then
  mkdir -p "$D/userdir/Load"
  cp -r "$W/dit/DynamicInputTextures" "$D/userdir/Load/"
fi
cat > "$D/userdir/Config/GCPadNew.ini" <<EOF
[GCPad1]
Device = $MANETTE
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
EOF
(cd "$CHASSIS" && MODERNGEKKO_STATICRECOMP=1 ./moderngekko-run.exe --game "$(w "$W/games/GXEE8P")" \
   --user-dir "$(w "$D/userdir")" --automation-dir "$(w "$D/auto")" \
   --module "$(w "$CHASSIS/gGXEE8P_recomp.dll")" > "$D/runner.log" 2>&1)
echo "RUN=$RUN"
