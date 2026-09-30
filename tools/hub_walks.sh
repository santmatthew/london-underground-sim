#!/bin/bash
# usage: tools/hub_walks.sh   -> walkbot on every authored hub (each ticket hall -> every platform, plus every platform -> street), all in parallel
# prints one line per run: "<station> <from>: N routes, M failed"; anything else (FAIL details) is in build/hubwalks/<name>.log
cd "$(dirname "$0")/.."
mkdir -p build/hubwalks; rm -f build/hubwalks/*.log
HUBS=(
  "Oxford Circus:hall_unpaid hall2_unpaid"
  "King's Cross St. Pancras:hall_unpaid hall2_unpaid"
  "Bank:hall_unpaid hall2_unpaid"
  "Waterloo:hall_unpaid hall2_unpaid"
  "Liverpool Street:hall_unpaid hall2_unpaid hall3_unpaid"
  "Tottenham Court Road:hall_unpaid"
  "Euston:hall_unpaid"
  "Green Park:hall_unpaid"
  "Victoria:hall_unpaid hall2_unpaid"
  "Piccadilly Circus:hall_unpaid"
  "Leicester Square:hall_unpaid"
  "Charing Cross:hall_unpaid"
  "Embankment:hall_unpaid hall2_unpaid"
  "Westminster:hall_unpaid"
  "Holborn:hall_unpaid"
  "London Bridge:hall_unpaid"
  "Paddington:hall_unpaid hall2_unpaid"
  "Bond Street:hall_unpaid"
  "Canary Wharf:hall_unpaid"
)
pids=()
for h in "${HUBS[@]}"; do
  st="${h%%:*}"; halls="${h#*:}"; slug=$(echo "$st" | tr -c 'A-Za-z0-9\n' '_')
  for from in $halls reverse; do
    args=(--station="$st" --rot=180)
    [ "$from" = reverse ] && args+=(--reverse) || args+=(--from=$from)
    log="build/hubwalks/${slug}__${from}.log"
    ( GTEST_TIMEOUT=${GTEST_TIMEOUT:-1200} GTEST_LINES=200 GTEST_ENGINE_ARGS="--fixed-fps 60" tools/gtest.sh walkbot_test "${args[@]}" > "$log" 2>&1 ) &
    pids+=($!)
  done
done
wait "${pids[@]}"
for log in build/hubwalks/*.log; do
  line=$(grep -a "routes, " "$log" | tail -1)
  echo "$(basename "$log" .log): ${line:-NO RESULT (see log)}"
done
