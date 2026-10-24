#!/usr/bin/env bash
# Starts a host and a guest copy of the game (headless, localhost) and waits for both.
# Usage (from the project folder): bash tests/run_net_test.sh [port]
G="${GODOT:-C:/Dev/Godot/Godot_v4.7.2-stable_win64_console.exe}"
PORT="${1:-24690}"
OUT="${TMPDIR:-${TEMP:-/tmp}}"
"$G" --headless --path . -s tests/net_test.gd -- role=host port=$PORT > "$OUT/net_host.log" 2>&1 &
HOST=$!
"$G" --headless --path . -s tests/net_test.gd -- role=guest port=$PORT profile=2 > "$OUT/net_guest.log" 2>&1 &
GUEST=$!
"$G" --headless --path . -s tests/net_test.gd -- role=solo port=$((PORT + 5)) profile=3 > "$OUT/net_solo.log" 2>&1 &
SOLO=$!
wait $GUEST; G_EXIT=$?
wait $HOST; H_EXIT=$?
wait $SOLO; S_EXIT=$?
echo "---- host (exit $H_EXIT)"; grep -E "ok \[|FAIL|SCRIPT ERROR|ERROR|ALL CHECKS|stats|\[net\]" "$OUT/net_host.log"
echo "---- guest (exit $G_EXIT)"; grep -E "ok \[|FAIL|SCRIPT ERROR|ERROR|ALL CHECKS|stats|steady|took|\[net\]" "$OUT/net_guest.log"
echo "---- solo (exit $S_EXIT)"; grep -E "ok \[|FAIL|SCRIPT ERROR|ERROR|ALL CHECKS|\[solo\]" "$OUT/net_solo.log"
[ $H_EXIT -eq 0 ] && [ $G_EXIT -eq 0 ] && [ $S_EXIT -eq 0 ]
