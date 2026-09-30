#!/bin/bash
# usage: tools/check_layout.sh "<station name or NaPTAN>" ...
# Runs every automatic check on an authored layout and prints one PASS/FAIL block per station (exit code 1 if any fails):
#   compile   the layout file compiles into an authored plan (LayoutCompiler errors are shown)
#   routes    route_audit_test: the real player capsule can walk every street door <-> platform, platform <-> platform and start-spot route
#   signs     sign_audit_test: no sign clips anything
#   walls     wall_audit_test: visible surfaces without a collider (walk-through walls); fails above 40 ghost rays per 1000
#   walks     walkbot_test with a moving capsule: from every ticket hall to every platform, and from every platform to the street
# ~1-2 minutes per station.  Set GTEST_TIMEOUT (default 900 s) if a check needs longer.
cd "$(dirname "$0")/.."
export GTEST_ENGINE_ARGS="--fixed-fps 60" GTEST_TIMEOUT=${GTEST_TIMEOUT:-900} GTEST_LINES=600
strip() { grep -av "ObjectDB\|resources still\|at: clear\|at: cleanup\|^$"; }
mkdir -p build/chk
rc=0
for arg in "$@"; do
  name=$(python3 - "$arg" <<'PY'
import json, sys
s = json.load(open("data/network.json"))["stations"]
a = sys.argv[1]
if a in s:
    print(s[a]["name"])
elif any(v["name"] == a for v in s.values()):
    print(a)
else:
    print("")
PY
)
  if [ -z "$name" ]; then echo "== $arg: FAIL  unknown station"; rc=1; continue; fi
  # at most 3 station checks at a time across all callers (each starts ~6 Godot processes)
  slot_fd=""
  while [ -z "$slot_fd" ]; do
    for i in 1 2 3; do
      exec {fd}>"build/chk/slot$i.lock"
      if flock -n "$fd"; then slot_fd=$fd; break; fi
      exec {fd}>&-
    done
    [ -z "$slot_fd" ] && sleep 3
  done
  slug=$(echo "$name" | tr -c 'A-Za-z0-9' '_')
  d="build/chk/$slug"; rm -rf "$d"; mkdir -p "$d"
  fails=()
  info=()

  # ---- compile
  tools/gtest.sh layouts_test --station="$name" 2>&1 | strip > "$d/compile.txt"
  if grep -aq "BAD\|ERROR: Layout" "$d/compile.txt"; then
    fails+=("compile: $(grep -a 'ERROR: Layout\|BAD' "$d/compile.txt" | head -3 | tr '\n' ' ')")
    echo "== $name: FAIL"; for f in "${fails[@]}"; do echo "   - $f"; done; rc=1; exec {slot_fd}>&-; continue
  fi
  halls=$(grep -ao '[0-9]* halls' "$d/compile.txt" | head -1 | grep -o '[0-9]*'); halls=${halls:-1}
  info+=("$(grep -a '  ok ' "$d/compile.txt" | sed 's/^ *ok *[^ ]* *//' | cut -c1-90)")

  # ---- everything else in parallel
  ( tools/gtest.sh route_audit_test --stations="$name" 2>&1 | strip > "$d/routes.txt" ) &
  ( tools/gtest.sh sign_audit_test --stations="$name" 2>&1 | strip > "$d/signs.txt" ) &
  ( tools/gtest.sh wall_audit_test --station="$name" --step=3 --max=4 2>&1 | strip > "$d/walls.txt" ) &
  for ((h = 1; h <= halls; h++)); do
    node="hall_unpaid"; [ "$h" -gt 1 ] && node="hall${h}_unpaid"
    ( tools/gtest.sh walkbot_test --station="$name" --rot=180 --from=$node 2>&1 | strip > "$d/walk_$h.txt" ) &
  done
  ( tools/gtest.sh walkbot_test --station="$name" --rot=180 --reverse 2>&1 | strip > "$d/walk_rev.txt" ) &
  wait

  # ---- routes
  tot=$(grep -a "^TOTAL:" "$d/routes.txt" | tail -1)
  if [ -z "$tot" ] || ! echo "$tot" | grep -q " 0 failed"; then
    fails+=("routes: ${tot:-no result}"); grep -a "FAIL\|NO PATH" "$d/routes.txt" | head -6 | sed 's/^/        /' >> "$d/detail.txt"
  else
    info+=("$(echo "$tot" | sed 's/TOTAL: 1 stations, //; s/, 0 failed.*//')")
  fi
  # ---- signs
  tot=$(grep -a "^TOTAL:" "$d/signs.txt" | tail -1)
  if [ -z "$tot" ] || ! echo "$tot" | grep -q " 0 bad"; then
    fails+=("signs: ${tot:-no result}"); grep -a "bad\|clip" "$d/signs.txt" | head -6 | sed 's/^/        /' >> "$d/detail.txt"
  else
    info+=("$(echo "$tot" | sed 's/TOTAL: //; s/, 0 bad//')")
  fi
  # ---- walls: ghost rays per 1000
  line=$(grep -a "^== " "$d/walls.txt" | head -1)
  rays=$(echo "$line" | sed -E 's/.*: ([0-9]+) rays.*/\1/'); ghost=$(echo "$line" | sed -E 's/.*GHOST ([0-9]+).*/\1/')
  if [ -z "$rays" ] || [ -z "$ghost" ] || ! [[ "$rays" =~ ^[0-9]+$ ]]; then
    fails+=("walls: no result")
  else
    per=$((ghost * 1000 / (rays > 0 ? rays : 1)))
    if [ "$per" -gt 40 ]; then
      fails+=("walls: $ghost visible-but-not-solid rays of $rays ($per per 1000): something visible is not solid")
      grep -a "GHOST x" -A1 "$d/walls.txt" | head -8 | sed 's/^/        /' >> "$d/detail.txt"
    else
      info+=("ghost $per/1000")
    fi
  fi
  # ---- walks
  wtot=0; wfail=0
  for f in "$d"/walk_*.txt; do
    r=$(grep -a "routes, " "$f" | tail -1)
    if [ -z "$r" ]; then wfail=$((wfail + 1)); echo "        $(basename "$f"): no result" >> "$d/detail.txt"; continue; fi
    n=$(echo "$r" | sed -E 's/.*: ([0-9]+) routes.*/\1/'); fl=$(echo "$r" | sed -E 's/.* ([0-9]+) failed.*/\1/')
    wtot=$((wtot + n)); wfail=$((wfail + fl))
    if [ "$fl" != "0" ]; then grep -a "FAIL\|blocker\|BLOCKED" "$f" | head -4 | sed "s|^|        $(basename "$f" .txt): |" >> "$d/detail.txt"; fi
  done
  if [ "$wfail" != "0" ]; then fails+=("walks: $wfail of $wtot walked routes failed"); else info+=("walked $wtot routes"); fi

  if [ ${#fails[@]} -eq 0 ]; then
    echo "== $name: PASS   ($(IFS=';'; echo "${info[*]}" | sed 's/;/;  /g'))"
  else
    echo "== $name: FAIL"; for f in "${fails[@]}"; do echo "   - $f"; done
    [ -f "$d/detail.txt" ] && cat "$d/detail.txt"
    rc=1
  fi
  exec {slot_fd}>&-
done
exit $rc
