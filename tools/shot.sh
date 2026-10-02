#!/bin/bash
# usage: tools/shot.sh res://tests/foo.tscn [-- --shot=a ...]   (renders headless under xvfb, prints errors/prints only)
cd "$(dirname "$0")/.."
scene="$1"; shift
UG_SETTINGS=user://test_settings.cfg timeout ${SHOT_TIMEOUT:-75} xvfb-run -a -s "-screen 0 1600x900x24" godot ${SHOT_ENGINE_ARGS} --path . --resolution ${SHOT_RES:-1280x720} "$scene" "$@" > build/shot.log 2>&1
code=$?
grep -v "xic\|DRI3\|Vulkan 1\|^$\|Godot Engine\|Note: you\|at: _create\|main.tscn\|resource_loader.cpp" build/shot.log | head -${SHOT_LINES:-25}
[ $code -eq 124 ] && echo "TIMEOUT (script error or hang?)"
exit 0
