#!/bin/bash
# usage: tools/hub_walks.sh   -> walkbot on every authored hub (each ticket hall -> every platform, plus every platform -> street), all in parallel
# prints one line per run: "<station> <from>: N routes, M failed"; anything else (FAIL details) is in build/hubwalks/<name>.log
cd "$(dirname "$0")/.."
mkdir -p build/hubwalks; rm -f build/hubwalks/*.log
# every authored layout (data/layouts) is walked: "Name:hall_unpaid hall2_unpaid ..." built from layouts_test --list
HUBS=()
while IFS='|' read -r tag name halls naptan; do
  [ "$tag" = "LAYOUT" ] || continue
  hs="hall_unpaid"; for ((h = 2; h <= halls; h++)); do hs="$hs hall${h}_unpaid"; done
  HUBS+=("$name:$hs")
done < <(GTEST_TIMEOUT=300 GTEST_LINES=2000 tools/gtest.sh layouts_test --list 2>&1)
echo "hub walks over ${#HUBS[@]} authored stations"
JOBS=${JOBS:-12}          # at most this many Godot instances at once (dozens in parallel made an engine crash in ~1 of 47 runs)
running=0
for h in "${HUBS[@]}"; do
  st="${h%%:*}"; halls="${h#*:}"; slug=$(echo "$st" | tr -c 'A-Za-z0-9\n' '_')
  for from in $halls reverse; do
    args=(--station="$st" --rot=180)
    [ "$from" = reverse ] && args+=(--reverse) || args+=(--from=$from)
    log="build/hubwalks/${slug}__${from}.log"
    ( GTEST_TIMEOUT=${GTEST_TIMEOUT:-1200} GTEST_LINES=200 GTEST_ENGINE_ARGS="--fixed-fps 60" tools/gtest.sh walkbot_test "${args[@]}" > "$log" 2>&1 ) &
    running=$((running+1))
    if [ "$running" -ge "$JOBS" ]; then wait -n; running=$((running-1)); fi
  done
done
wait
for log in build/hubwalks/*.log; do
  line=$(grep -a "routes, " "$log" | tail -1)
  echo "$(basename "$log" .log): ${line:-NO RESULT (see log)}"
done
