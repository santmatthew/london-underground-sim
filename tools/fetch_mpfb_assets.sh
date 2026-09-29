#!/bin/bash
# Downloads MakeHuman/MPFB asset packs (CC0 + CC-BY) and unpacks them into the MPFB user data dir.
DATA="$HOME/.config/blender/5.2/extensions/.user/user_default/mpfb/data"
DL="$(dirname "$0")/../build/assetpacks"
mkdir -p "$DL" "$DATA"
BASE="https://files2.makehumancommunity.org/asset_packs"
PACKS="
makehuman_system_assets/cc0 skins01/cc0 skins02/cc0 skins03/cc0 shirts01/cc0 shirts02/ccby shirts03/ccby
pants01/cc0 pants02/ccby pants03/ccby shoes01/cc0 shoes02/ccby suits01/cc0 suits02/cc0 suits03/cc-by
dress01/cc0 skirts01/cc0 skirts02/cc-by hair01/cc0 hair02/ccby hair03/ccby hats02/cc0 glasses01/cc0
glasses02/ccby equipment01/cc0 equipment02/cc-by eyebrows01/cc0 eyelashes01/cc0 clothes_materials01/cc0
system_clothes_materials01/cc0 system_hair_materials01/cc0 system_hair_materials02/cc0 system_eye_materials01/cc0
gloves01/cc0 nose01/cc0
"
fetch() {
  p="${1%%/*}"; lic="${1##*/}"
  f="$DL/${p}_${lic}.zip"
  if [ ! -f "$f.done" ]; then
    curl -sS -L --retry 3 -m 1500 -o "$f" "$BASE/$p/${p}_${lic}.zip" && unzip -qo "$f" -d "$DATA" && touch "$f.done" && rm -f "$f" && echo "ok $p"
  fi
}
export -f fetch; export DATA DL BASE
echo $PACKS | tr ' ' '\n' | grep . | xargs -P4 -I{} bash -c 'fetch {}'
echo ALL_DONE
