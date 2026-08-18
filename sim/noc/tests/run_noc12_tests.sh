#!/usr/bin/env bash
set -euo pipefail
noc_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
booksim="$noc_dir/booksim2/src/booksim"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

g++ -std=c++11 -I"$noc_dir/booksim2/src" \
  "$noc_dir/tests/noc12_map_test.cpp" \
  "$noc_dir/booksim2/src/networks/noc12_map.cpp" -o "$tmp/map_test"
"$tmp/map_test"

run() {
  local name=$1; shift
  set +e
  "$booksim" "$noc_dir/configs/noc12_smoke.cfg" "$@" \
    noc_telemetry_file="$tmp/$name.csv" >"$tmp/$name.log" 2>&1
  local status=$?
  set -e
  [[ $status -eq 0 || $status -eq 255 ]]
  grep -q '====== Overall Traffic Statistics ======' "$tmp/$name.log"
  awk -F, 'NR==1{if(NF!=19)exit 1;next}NF!=19{exit 1}' "$tmp/$name.csv"
}

# Reach one lane on every LLCH from PE_00_00 and drain exactly.
for llch in $(seq 0 11); do
  node=$((320+llch*4+(llch%4)))
  run "route_$llch" "traffic=hotspot({$node})" injection_rate=0.04 \
      sample_period=30 max_samples=2
  grep -q 'Draining remaining packets' "$tmp/route_$llch.log"
done

# Both policies conserve port request/grant/loss counters. Weighted stress must
# expose real contention and deliver traffic through both L1 and L2 routers.
for policy in rr weighted; do
  set +e
  "$booksim" "$noc_dir/configs/noc12_pe_to_llch.cfg" \
    voq_grant_policy="$policy" injection_rate=1.0 sim_type=throughput \
    sample_period=100 max_samples=2 noc_telemetry_interval=10 \
    noc_telemetry_file="$tmp/$policy.csv" >"$tmp/$policy.log" 2>&1
  status=$?
  set -e
  [[ $status -eq 0 || $status -eq 255 ]]
  awk -F, '
    $2=="port" {if($9!=$10+$11)bad=1; credit+=$13; loss+=$11;
      if($4~/^L1_/&&$7>0)l1=1;if($4~/^L2_/&&$7>0)l2=1}
    END{exit bad||credit<=0||loss<=0||!l1||!l2}' "$tmp/$policy.csv"
done

echo 'noc12 graph, all-LLCH delivery, telemetry, RR, and weighted tests passed.'
