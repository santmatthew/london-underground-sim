#!/bin/bash
# usage: tools/hub_journeys.sh [journeys-file]   -> autopilot journeys between hubs, all in parallel, one summary block per journey
# journeys-file lines: seed|start|dest|hour   (station names with spaces as underscores; default set below). Logs in build/hubjourneys/.
# Each journey is bounded by `timeout` (JTIMEOUT, default 2600 s). Flags: falls ("Player fell"/DROP), stuck events, missed trains, unplanned rides.
cd "$(dirname "$0")/.."
mkdir -p build/hubjourneys
DEFAULT="61|Victoria|Oxford_Circus|9.0
62|Oxford_Circus|Victoria|17.9
63|Victoria|King's_Cross_St._Pancras|8.5
55|Green_Park|Bank|13.3
56|Euston|Liverpool_Street|19.1
53|Tottenham_Court_Road|Green_Park|17.6
64|King's_Cross_St._Pancras|Victoria|12.2
51|Bank|Waterloo|9.2
54|Liverpool_Street|Oxford_Circus|8.6
65|Waterloo|Victoria|18.4
66|Piccadilly_Circus|Bank|8.3
67|Victoria|Piccadilly_Circus|17.2"
LIST="${1:+$(cat "$1")}"; LIST="${LIST:-$DEFAULT}"
pids=(); n=0
while IFS='|' read -r seed from to hour; do
  [ -z "$seed" ] && continue
  n=$((n+1)); log="build/hubjourneys/j${n}_${seed}.log"
  ( timeout ${JTIMEOUT:-2600} godot --headless --fixed-fps 60 --path . res://tests/runner.tscn -- --test=bot_test --seed=$seed --every=100000 --start="$from" --spot=street_entrance --dest="$to" --hour=$hour > "$log" 2>&1 ) &
  pids+=($!)
done <<< "$LIST"
wait "${pids[@]}"
for log in build/hubjourneys/j*_*.log; do
  echo "== $(basename "$log" .log): $(grep -a '^journey' "$log" | cut -c1-100)"
  grep -a "RESULT" "$log" | cut -c1-140 || echo "   NO RESULT"
  grep -aq "SCRIPT ERROR" "$log" && echo "   !! SCRIPT ERROR"
  grep -aq "Player fell\|^DROP" "$log" && echo "   !! FELL / DROP (see log)"
  c=$(grep -a "^BOT" "$log" | grep -ac "stuck near"); [ "$c" -gt 0 ] && echo "   stuck events: $c"
  grep -a "^BOT" "$log" | grep -a "missed the train\|unplanned\|giving up" | awk '!s[$0]++' | cut -c1-140 | sed 's/^/   /'
done
