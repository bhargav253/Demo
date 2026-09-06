#!/usr/bin/env bash
set -euo pipefail
noc_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
g++ -std=c++11 -I"$noc_dir/booksim2/src" "$noc_dir/tests/noc16c_map_test.cpp" \
  "$noc_dir/booksim2/src/networks/noc16c_map.cpp" -o "$tmp/map_test"
"$tmp/map_test"
set +e
"$noc_dir/booksim2/src/booksim" "$noc_dir/configs/noc16c_smoke.cfg" \
  noc_telemetry_file="$tmp/telemetry.csv" >"$tmp/smoke.log" 2>&1
status=$?
set -e
[[ $status -eq 0 || $status -eq 255 ]]
grep -q 'Overall Traffic Statistics' "$tmp/smoke.log"
grep -q 'Hops average = 4 ' "$tmp/smoke.log"
grep -q ',router,0,L1_00,' "$tmp/telemetry.csv"
grep -q ',router,16,L2_00,' "$tmp/telemetry.csv"
grep -q ',shim,96,SHIM_00_00,' "$tmp/telemetry.csv"
echo 'noc16c smoke delivery and telemetry passed.'
