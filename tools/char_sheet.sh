#!/bin/bash
# usage: tools/char_sheet.sh out.png view "Station A" "Station B" ...   (extra station_test args via CHAR_ARGS="--x=30 --fov=85")
# renders one station_test view per station and tiles them into a contact sheet (2 columns)
cd "$(dirname "$0")/.."
out="$1"; view="$2"; shift 2
files=()
i=0
for s in "$@"; do
  SHOT_RES=${SHOT_RES:-960x540} tools/shot.sh res://tests/station_test.tscn -- --station="$s" --view=$view $CHAR_ARGS > /dev/null 2>&1
  cp build/shot_station_$view.png build/_cs_$i.png
  files+=("build/_cs_$i.png")
  i=$((i+1))
done
python3 - "$out" "${files[@]}" <<'PY'
import sys
from PIL import Image
out=sys.argv[1]; fs=sys.argv[2:]
ims=[Image.open(f).convert('RGB') for f in fs]
w,h=ims[0].size
cols=2; rows=(len(ims)+cols-1)//cols
sheet=Image.new('RGB',(w*cols,h*rows))
for i,im in enumerate(ims):
    sheet.paste(im,((i%cols)*w,(i//cols)*h))
sheet.save(out)
PY
