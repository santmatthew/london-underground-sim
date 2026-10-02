#!/bin/bash
# usage: tools/fps_experiment.sh [secs=300] [resolution=1920x1080] [rungs...]      (DISPLAY must be a real display: a virtual one has no real present path)
# The ladder of progressively more complex scenes, one run of `secs` seconds each, every frame logged (FrameLog) with a once-a-second system sampler beside it
# (GPU clocks / power / temperature / throttling, CPU frequency / temperature / load). Results: build/fps/run_<time>/<rung>.csv + <rung>_sys.csv; then tools/fps_report.py.
cd "$(dirname "$0")/.."
SECS=${1:-300}; RES=${2:-1920x1080}; shift 2 2>/dev/null
RUNS=${@:-"L0 L1 L2 L3 L4 L5 L5_open L3_bug L5_bug L6_game"}
OUT=build/fps/run_$(date +%m%d_%H%M); mkdir -p $OUT
echo "$OUT" > build/fps/latest
exp() {  # name, level, station, extra args, env
  local name=$1 lv=$2 st=$3 extra=$4 envs=$5
  python3 tools/sys_sampler.py $OUT/${name}_sys.csv & local sp=$!
  env $envs godot --path . --resolution $RES --windowed res://tests/fps_experiment.tscn -- --level=$lv --station="$st" --secs=$SECS --out=res://$OUT/$name.csv $extra > $OUT/${name}.log 2>&1
  kill $sp 2>/dev/null; wait $sp 2>/dev/null
  grep FRAMELOG $OUT/${name}.log | tail -1
}
for r in $RUNS; do
  echo "== $r $(date +%H:%M:%S)"
  case $r in
    L0) exp L0 0 "Oxford Circus" "" "";;
    L1) exp L1 1 "Oxford Circus" "" "";;
    L2) exp L2 2 "Oxford Circus" "" "";;
    L3) exp L3 3 "Oxford Circus" "" "";;
    L4) exp L4 4 "Oxford Circus" "" "";;
    L5) exp L5 5 "Oxford Circus" "" "";;
    L5_open) exp L5_open 5 "Acton Town" "" "";;
    L3_bug) exp L3_bug 3 "Oxford Circus" "" "UG_ON=tubemap_redraw";;
    L5_bug) exp L5_bug 5 "Oxford Circus" "" "UG_ON=tubemap_redraw";;
    L6_game)
      python3 tools/sys_sampler.py $OUT/L6_game_sys.csv & sp=$!
      godot --path . --resolution $RES --windowed --disable-vsync res://scenes/main.tscn -- --autopilot --seed=5 --length=long --fps-log=$OUT/L6_game.csv --fps-secs=$SECS --fps-quit > $OUT/L6_game.log 2>&1
      kill $sp 2>/dev/null; wait $sp 2>/dev/null
      grep FRAMELOG $OUT/L6_game.log | tail -1;;
  esac
done
echo "done: $OUT"
