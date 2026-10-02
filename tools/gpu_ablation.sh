#!/bin/bash
# usage: tools/gpu_ablation.sh [level=3] [station="Oxford Circus"] [vp=3840x2160] [secs=15]    (real DISPLAY needed, see tools/fps_experiment.sh)
# GPU time (SubViewport render time, p50) of one scene under a list of render settings: what each full-screen effect, the upscaler and the render scale cost at the target size.
cd "$(dirname "$0")/.."
LV=${1:-3}; ST=${2:-"Oxford Circus"}; VP=${3:-3840x2160}; SECS=${4:-15}
run() {  # label, args...
  local label=$1; shift
  local line
  line=$(godot --path . --resolution 1920x1080 --windowed res://tests/fps_experiment.tscn -- --level=$LV --station="$ST" --vp=$VP --secs=$SECS --warm=0 "$@" 2>&1 | grep FRAMELOG | tail -1)
  python3 - "$label" "$line" <<'PY'
import sys, re
label, l = sys.argv[1], sys.argv[2]
m = re.search(r'fps_mean": ([0-9.]+), "frame_ms_p50": ([0-9.]+).*"frame_ms_p99": ([0-9.]+).*gpu_ms_p50": ([0-9.]+)', l)
print("%-46s GPU p50 %6s ms   (frame p50 %s, p99 %s, %s fps)" % ((label,) + ((m.group(4), m.group(2), m.group(3), m.group(1)) if m else ("?", "?", "?", "?"))))
PY
}
echo "level $LV, $ST, target $VP"
while IFS='|' read -r label args; do
  [ -z "$label" ] && continue
  run "$label" $args
done <<EOF
native (render scale 100%)|--scale=1.0
FSR 1 at the Auto scale (today's default)|--scale=0
Auto, glow off|--scale=0 --env=glow_enabled=false
Auto, ambient occlusion off|--scale=0 --env=ssao_enabled=false
Auto, TAA off|--scale=0 --vpset=use_taa=false
Auto, colour adjustment off|--scale=0 --env=adjustment_enabled=false
Auto, fog off|--scale=0 --env=fog_enabled=false
Auto, all five off|--scale=0 --env=glow_enabled=false,ssao_enabled=false,adjustment_enabled=false,fog_enabled=false --vpset=use_taa=false
FSR 1 at 40%|--scale=0.4
FSR 1 at 50%|--scale=0.5
FSR 1 at 60%|--scale=0.6
FSR 1 at 70%|--scale=0.7
FSR 2 at the Auto scale|--scale=0 --fsr=2
EOF
