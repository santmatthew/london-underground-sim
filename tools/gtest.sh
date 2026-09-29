#!/bin/bash
# usage: tools/gtest.sh test_name [test args...]  -> runs tests/<name>.gd headless with a timeout and prints its output
# env: GTEST_TIMEOUT (s), GTEST_LINES, GTEST_ENGINE_ARGS (e.g. "--fixed-fps 60" to simulate as fast as possible)
cd "$(dirname "$0")/.."
log="build/gtest_$$.log"
timeout ${GTEST_TIMEOUT:-120} godot --headless ${GTEST_ENGINE_ARGS} --path . res://tests/runner.tscn -- --test=$1 "${@:2}" > "$log" 2>&1
code=$?
grep -v "^$\|Godot Engine\|main.tscn\|resource_loader.cpp" "$log" | head -${GTEST_LINES:-60}
[ $code -eq 124 ] && echo "TIMEOUT"
rm -f "$log"
exit 0
