#!/bin/bash
# usage: tools/gtest.sh test_name   -> runs tests/<name>.gd headless with timeout, prints output
cd "$(dirname "$0")/.."
timeout ${GTEST_TIMEOUT:-120} godot --headless ${GTEST_ENGINE_ARGS} --path . res://tests/runner.tscn -- --test=$1 > build/gtest.log 2>&1
code=$?
grep -v "^$\|Godot Engine\|main.tscn\|resource_loader.cpp" build/gtest.log | head -${GTEST_LINES:-60}
[ $code -eq 124 ] && echo "TIMEOUT"
exit 0
