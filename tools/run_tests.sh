#!/bin/bash
# Quick regression suite (a few minutes). Usage: tools/run_tests.sh [--full]
# --full also runs a physical walk-through of several stations and a short autopilot journey.
cd "$(dirname "$0")/.."
fail=0
check() {  # name, grep-pattern-that-must-match, log
  if grep -qE "$2" "$3"; then echo "PASS  $1"; else echo "FAIL  $1  (see $3)"; fail=1; fi
}
GTEST_TIMEOUT=200 tools/gtest.sh test_timetable > build/t_timetable.log 2>&1
check "timetable: no platform overlaps" "overlap check: 0 overlaps" build/t_timetable.log
GTEST_TIMEOUT=200 tools/gtest.sh test_planner > build/t_planner.log 2>&1
check "planner: routes found" "arrive exit" build/t_planner.log
if grep -q "no route" build/t_planner.log; then echo "FAIL  planner: some case had no route"; fail=1; fi
GTEST_TIMEOUT=250 tools/gtest.sh walk_test > build/t_walk.log 2>&1
check "floor audit: no gaps" "TOTAL gap spots: 0" build/t_walk.log
GTEST_ENGINE_ARGS="--fixed-fps 60" GTEST_TIMEOUT=200 tools/gtest.sh plan_warm_test > build/t_planwarm.log 2>&1
check "background builds: plans and timetable equal the synchronous ones" "^OK" build/t_planwarm.log
GTEST_ENGINE_ARGS="--fixed-fps 60" GTEST_TIMEOUT=200 tools/gtest.sh open_style_test > build/t_openstyle.log 2>&1
check "photo-authored surface stations: roofs, spans, bridge" "^OK" build/t_openstyle.log
for t in settings_test input_bindings_test announcer_test palette_test lift_plan_test step_free_plan_test lift_ride_test lift_crowd_test spiral_plan_test spiral_ride_test door_warning_test explore_test crowd_avoid_test el_timetable_test plan_faces_test bend_test ride_curve_test curved_platform_test curved_ride_test door_side_test path_vs_module_test esc_signs_test tunnel_clearance_test stock_test scenery_test grade_test door_clearance_test ride_stand_test ambience_test platform_clear_test tunnel_seam_test; do
  GTEST_ENGINE_ARGS="--fixed-fps 60" GTEST_TIMEOUT=${T_TIMEOUT:-200} tools/gtest.sh $t > build/t_$t.log 2>&1
  check "$t" "^OK" build/t_$t.log
done
GTEST_TIMEOUT=300 tools/gtest.sh route_audit_test --stations="Covent Garden|Borough|Goodge Street|Hampstead|Russell Square" --spiral > build/t_spiral_routes.log 2>&1
check "spiral stairs: every route through them (doors and helix swept) is free" "TOTAL: 5 stations, [0-9]+ routes, 0 failed" build/t_spiral_routes.log
GTEST_TIMEOUT=300 GTEST_LINES=200 tools/gtest.sh zfight_audit_test --stations="Goodge Street|Oxford Circus|Kennington|Covent Garden" --max=3 > build/t_zfight.log 2>&1
check "z-fighting: no large coplanar overlaps in the architecture of four stations" "^OK" build/t_zfight.log
GTEST_TIMEOUT=100 tools/gtest.sh audio_test > build/t_audio.log 2>&1
check "audio: streams load, speech plays" "speech playing: true \(missing streams: 0\)" build/t_audio.log
if [ "$1" == "--full" ]; then
  for st in "King's Cross St. Pancras" "Barbican" "Chiswick Park"; do
    GTEST_ENGINE_ARGS="--fixed-fps 60" GTEST_TIMEOUT=300 tools/gtest.sh walkbot_test --station="$st" > build/t_walkbot.log 2>&1
    check "walk-through: $st" " 0 failed" build/t_walkbot.log
  done
  GTEST_ENGINE_ARGS="--fixed-fps 60" GTEST_TIMEOUT=600 tools/gtest.sh bot_test --seed=3 --length=short > build/t_bot.log 2>&1
  check "autopilot journey completes" "state 4|RESULT" build/t_bot.log
fi
exit $fail
