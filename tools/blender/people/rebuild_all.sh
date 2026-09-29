#!/bin/bash
# Full crowd-people pipeline (run from anywhere):
#   1. Blender/MPFB: 36 characters + bags           -> assets/people/chars/*.glb, bags/*.glb
#   2. venv python : textures (skin/outfit/face/hair) -> assets/people/tex/*.png (+ .import stubs)
#   3. venv python : CMU mocap retarget               -> build/people_tmp/anims_raw.json + assets/people/anims/anims_meta.json
#   4. Godot       : AnimationLibrary                 -> assets/people/anims/people_anims.res
#   5. manifest + credits, sync into the sandbox Godot project and import
# Usage: rebuild_all.sh [chars] [tex] [anims] [bags] [manifest] [sandbox]   (default: everything)
P=/home/msant/Projects/Personal/underground-sim
T=$P/tools/blender/people
PY=$P/build/people_tmp/venv/bin/python
STEPS="${@:-chars tex anims bags manifest sandbox}"
has() { [[ " $STEPS " == *" $1 "* ]]; }
cd $P
if has chars;  then blender -b --factory-startup -P $T/make_people.py 2>&1 | grep -E "^  OK|FAIL|Traceback|Error" ; fi
if has bags;   then blender -b --factory-startup -P $T/make_bags.py 2>&1 | grep -E "^bag|Traceback|Error"; fi
if has tex;    then PEOPLE_HQ=${PEOPLE_HQ:-1} $PY $T/make_shared_textures.py && PEOPLE_HQ=${PEOPLE_HQ:-1} $PY $T/make_textures.py | tail -1; fi
if has anims;  then
  $PY $T/make_anims.py | tail -3
  mkdir -p $P/build/sandbox_people/tools && cp $T/build_anim_library.gd $P/build/sandbox_people/tools/
  (cd $P/build/sandbox_people && godot --headless --path . --script res://tools/build_anim_library.gd 2>&1 | tail -1)
fi
if has manifest; then $PY $T/build_manifest.py && python3 $T/make_credits.py; fi
if has sandbox; then
  $T/sync_sandbox.sh
  (cd $P/build/sandbox_people && godot --headless --path . --import 2>&1 | tail -1)
fi
echo REBUILD_DONE
