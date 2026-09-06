#!/usr/bin/env bash
set -euo pipefail

router_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
config="$router_dir/configs/noc16_smoke.cfg"

run_case() {
  local llch=$1 lane=$2 target_router=$3
  local node=$((320 + llch * 4 + lane))
  local row=$((target_router / 4)) col=$((target_router % 4))
  local hops=$((4 + row + col))
  local latency=$((2 * hops + 2))
  local log="/tmp/noc16_route_${llch}_${lane}.log"
  set +e
  "$booksim" "$config" "traffic=hotspot({$node})" \
    sample_period=30 max_samples=2 injection_rate=0.05 > "$log" 2>&1
  local status=$?
  set -e
  [[ $status -eq 0 || $status -eq 255 ]]
  grep -q "Hops average = $hops " "$log"
  grep -q "Network latency average = $latency " "$log"
  grep -q 'Draining remaining packets' "$log"
}

# One destination on every LLCH, rotating through all four physical lanes.
llch_router=(0 1 2 3 3 7 11 15 15 14 13 12 12 8 4 0)
for llch in $(seq 0 15); do
  run_case "$llch" "$((llch % 4))" "${llch_router[$llch]}"
done

echo 'noc16 all-LLCH, all-lane, near/far XY route tests passed.'
