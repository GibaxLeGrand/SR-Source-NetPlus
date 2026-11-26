#!/usr/bin/env bash
# SR-Source Net Plus : l'option voix japonaises du launcher, sans lancer le jeu.
#   1. SR-Source.exe --japanese-voices <disque japonais> dans un dossier utilisateur de test ; comparaison
#      fichier à fichier avec le mod fait par construire_mod_voix_jp.py (work\voix_jp\mods\srnp_voix_jp) ;
#   2. la salle : hôte sans le mod, ami avec (activé) : l'ami doit être « OTHER MODS », départ impossible ;
#      photos des deux launchers, empreintes dans le journal du relais.
set -uo pipefail
W=/d/_SonicRidersSource/work
L=$W/launcher_online
EXE="$L/SR-Source.exe"
DISQUE="$W/disques/Sonic Riders (Japan) (En,Ja,Fr,De,Es,It).rvz"
STATE="$W/states/gxee8p_pret1p_100pc_metal_1tour_jit.sav"
PORT=7852
RUN="$L/runs/$(date +%Y%m%d-%H%M%S)-voix"
w() { cygpath -w "$1"; }
autres=$(tasklist.exe | grep -ciE "SR-Source")
if [[ "$autres" != 0 ]]; then echo "$autres launcher(s) ouvert(s) : rien lancé"; exit 1; fi
mkdir -p "$RUN"
prepare() {  # prepare <pc> <tag>
  local U="$RUN/$1/sr-source"
  mkdir -p "$U/Logs" "$U/Mods"
  cp -a "$W/userdir_modele/Config" "$U/Config"
  sed -e 's/^music_volume=.*/music_volume=0/' -e 's/^game_volume=.*/game_volume=0/' -e 's/^check_for_updates=.*/check_for_updates=false/' \
      "$W/userdir_modele/config.ini" > "$U/config.ini"
  w "$W/games/GXEE8P" > "$U/default-game.txt"
  printf 'tag=%s\naddress=127.0.0.1:%s\nport=%s\nstart_state=%s\n' "$2" "$PORT" "$PORT" "$(w "$STATE")" > "$U/online.ini"
}
prepare pcA HOTE
prepare pcB AMI
# 1. L'extraction, chez l'ami.
t0=$(date +%s)
(cd "$L" && env LOCALAPPDATA="$(w "$RUN/pcB")" "$EXE" --japanese-voices "$(w "$DISQUE")" > "$RUN/extraction.out" 2>&1)
echo "extraction : code $? en $(( $(date +%s) - t0 )) s : $(cat "$RUN/extraction.out" | tr -d '\r')"
"/c/Program Files/Python313/python.exe" -I - "$(w "$RUN/pcB/sr-source/Mods/srnp_voix_jp")" "$(w "$W/voix_jp/mods/srnp_voix_jp")" <<'PY'
import hashlib, os, sys
a, b = sys.argv[1], sys.argv[2]
def liste(d):
    r = {}
    for racine, _, fichiers in os.walk(d):
        for f in fichiers:
            p = os.path.join(racine, f)
            h = hashlib.sha1(open(p, "rb").read()).hexdigest()
            r[os.path.relpath(p, d)] = (os.path.getsize(p), h)
    return r
la, lb = liste(a), liste(b)
diff = sorted(k for k in set(la) | set(lb) if la.get(k) != lb.get(k))
print(f"launcher : {len(la)} fichiers ; script : {len(lb)} fichiers ; différents ou manquants : {len(diff)} {diff[:5]}")
PY
printf 'mod=srnp_voix_jp\n' >> "$RUN/pcB/sr-source/config.ini"
# 2. La salle : l'hôte sans le mod, l'ami avec.
lance() {  # lance <pc> <auto> [variables...]
  local pc=$1 auto=$2; shift 2
  (cd "$L" && env LOCALAPPDATA="$(w "$RUN/$pc")" SRNP_ONLINE_AUTO="$auto" "$@" "$EXE" --x11 "$pc-$(basename "$RUN")" > "$RUN/$pc/launcher.out" 2>&1) &
}
pid_de() {
  powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"name='SR-Source.exe'\" | Where-Object { \$_.CommandLine -like '*$1*' } | Select-Object -First 1).ProcessId" | tr -d '\r'
}
lance pcA host SRNP_ONLINE_START="2:4"
sleep 6
lance pcB connect SRNP_ONLINE_READY=1
sleep 10
LA=$(pid_de "pcA-$(basename "$RUN")"); LB=$(pid_de "pcB-$(basename "$RUN")")
powershell -NoProfile -ExecutionPolicy Bypass -File "$(w "$L/photo_pid.ps1")" -ProcessId "$LA" -Png "$(w "$RUN/lobby_hote.png")"
powershell -NoProfile -ExecutionPolicy Bypass -File "$(w "$L/photo_pid.ps1")" -ProcessId "$LB" -Png "$(w "$RUN/lobby_ami.png")"
for p in $LA $LB; do taskkill.exe //F //PID "$p" > /dev/null 2>&1; done
grep -E "joined|not started|match" "$RUN/pcA/sr-source/Logs/relay.log"
echo "RUN=$RUN"
