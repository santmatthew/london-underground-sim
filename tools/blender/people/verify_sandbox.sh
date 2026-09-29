#!/bin/bash
# Renders the verification screenshots + perf numbers in the sandbox Godot project (build/sandbox_people/tests/*.png)
#   a) neutral lineup, b) station-like tunnel lineup, c) 150 person crowd timing
P=/home/msant/Projects/Personal/underground-sim
S=$P/build/sandbox_people
cd $S
run() { xvfb-run -a -s "-screen 0 1600x900x24" godot --path . "$@" 2>&1 | grep -E "ERROR|SCRIPT|PERF|WARNING: Node" ; }
run --resolution 1600x700 res://tests/lineup.tscn -- neutral 0 6 6 res://tests/final_neutral full
run --resolution 1600x700 res://tests/lineup.tscn -- tunnel 0 6 6 res://tests/final_tunnel full
run --resolution 1280x720 res://tests/lineup.tscn -- neutral 0 4 4 res://tests/final_close full idle_stand_2
run --resolution 1280x720 res://tests/crowd.tscn -- 150 20 res://tests/crowd150 1 1
run --resolution 1280x720 res://tests/crowd.tscn -- 150 20 res://tests/crowd150_nolod 0 1
run --resolution 1280x720 res://tests/crowd.tscn -- 150 20 res://tests/crowd150_noshadow 1 0
echo VERIFY_DONE
