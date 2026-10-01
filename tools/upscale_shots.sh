#!/bin/bash
# usage: tools/upscale_shots.sh   -> 4K renders of a few views under each upscaler setting (build/up/<view>__<mode>.png); sheets are made by tools/upscale_sheet.py
# Native = TAA at full resolution; fsr1 = what the game does today at 4K (Auto scale); fsr2 = Godot's temporal upscaler (the same class of technique as DLSS,
# but NOT DLSS: Godot has no DLSS support) at the DLSS-equivalent scales Quality 0.667 / Balanced 0.58 / Performance 0.5.
cd "$(dirname "$0")/.."
mkdir -p build/up
declare -A VIEWS=(
  [edgware_plat]='--station=Edgware Road (Bakerloo) --view=plat --fi=0'
  [oxford_hall]='--station=Oxford Circus --view=hall'
  [acton_open]='--station=Acton Town --view=plat --fi=2 --hour=14'
  [covent_wall]='--station=Covent Garden --view=pwall --fi=0 --x=63 --dx=0 --fov=80'
)
MODES=("native:1.0" "fsr1:0.538" "fsr2:0.667" "fsr2:0.58" "fsr2:0.5")
for v in "${!VIEWS[@]}"; do
  for m in "${MODES[@]}"; do
    mode=${m%%:*}; sc=${m##*:}
    out="build/up/${v}__${mode}_${sc}.png"
    [ -s "$out" ] && continue
    eval "args=(${VIEWS[$v]// --/ --})" 2>/dev/null
    IFS=$'\n' read -r -d '' -a parts < <(printf '%s' "${VIEWS[$v]}" | sed 's/ --/\n--/g' && printf '\0')
    SHOT_TIMEOUT=400 SHOT_RES=3840x2160 tools/shot.sh res://tests/station_test.tscn -- "${parts[@]}" --mode=$mode --scale=$sc --frames=90 --out=res://$out > /dev/null 2>&1
    echo "$out $(stat -c %s "$out" 2>/dev/null)"
  done
done
