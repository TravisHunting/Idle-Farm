#!/usr/bin/env bash
# Click-through of the multiplayer UI: a host and a guest copy driven by synthetic input (headless).
# Usage (from the project folder): bash tests/run_click_test.sh [port]
G="${GODOT:-C:/Dev/Godot/Godot_v4.7.2-stable_win64_console.exe}"
PORT="${1:-24700}"
OUT="${TMPDIR:-${TEMP:-/tmp}}"
"$G" --headless --path . -s tests/click_test.gd -- role=host port=$PORT profile=4 > "$OUT/click_host.log" 2>&1 &
HOST=$!
"$G" --headless --path . -s tests/click_test.gd -- role=guest port=$PORT profile=5 > "$OUT/click_guest.log" 2>&1 &
GUEST=$!
wait $GUEST; G_EXIT=$?
wait $HOST; H_EXIT=$?
echo "---- host (exit $H_EXIT)"; grep -E "ok \[|FAIL|SCRIPT ERROR|ERROR|ALL CHECKS" "$OUT/click_host.log"
echo "---- guest (exit $G_EXIT)"; grep -E "ok \[|FAIL|SCRIPT ERROR|ERROR|ALL CHECKS" "$OUT/click_guest.log"
[ $H_EXIT -eq 0 ] && [ $G_EXIT -eq 0 ]
