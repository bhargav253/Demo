#!/usr/bin/env bash
set -euo pipefail

router_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
smoke="$router_dir/configs/noc16_smoke.cfg"
balanced="$router_dir/configs/noc16_pe_to_llch.cfg"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

fail() { echo "NoC16 port telemetry test failed: $*" >&2; exit 1; }

run_case() {
  local name=$1 config=$2
  shift 2
  set +e
  "$booksim" "$config" "$@" \
    noc_telemetry_file="$test_dir/$name.csv" >"$test_dir/$name.log" 2>&1
  local status=$?
  set -e
  [[ $status -eq 0 || $status -eq 255 ]] || fail "$name simulator status $status"
  awk -F, 'NR==1 {if(NF!=19) exit 1; next} NF!=19 {exit 1}' \
    "$test_dir/$name.csv" || fail "$name CSV schema"
}

echo '[port 1/4] bypass has exact zero queue wait and residence'
run_case bypass "$smoke" voq_bypass=1 injection_rate=1.0 \
  sim_type=throughput noc_telemetry_interval=1 sample_period=80 max_samples=2
awk -F, '
  $2=="port" && ($14>0 || $16>0) {
    seen++
    if($15!=0 || $17!=0 || $18!=0 || $19!=0) bad=1
  }
  END {exit bad || seen<20}
' "$test_dir/bypass.csv" || fail 'bypass latency'

echo '[port 2/4] queued Q48 path has exact wait=1 and residence=4'
run_case queued "$smoke" voq_bypass=0 injection_rate=1.0 \
  sim_type=throughput noc_telemetry_interval=1 sample_period=80 max_samples=2
awk -F, '
  $2=="port" && $14>0 {qseen++; if($18!=1 || $15!=$14) bad=1}
  $2=="port" && $16>0 {rseen++; if($19!=4 || $17!=4*$16) bad=1}
  END {exit bad || qseen<20 || rseen<20}
' "$test_dir/queued.csv" || fail 'queued latency'

echo '[port 3/4] request/grant/loss and router totals conserve'
awk -F, '
  $2=="port" {
    if($9 != $10+$11) bad=1
    pa[$3]+=$6; pd[$3]+=$7
  }
  $2=="router" {ra[$3]+=$6; rd[$3]+=$7}
  END {
    for(r in pa) if(pa[r]!=ra[r] || pd[r]!=rd[r]) bad=1
    exit bad
  }
' "$test_dir/queued.csv" || fail 'counter conservation'

echo '[port 4/4] stressed network exposes real credit and allocator stalls'
run_case stress "$balanced" injection_rate=1.0 sim_type=throughput \
  noc_telemetry_interval=10 sample_period=100 max_samples=2
awk -F, '
  $2=="port" {
    if($9 != $10+$11) bad=1
    credit += $13; losses += $11
  }
  END {exit bad || credit<=0 || losses<=0}
' "$test_dir/stress.csv" || fail 'stress stall telemetry'

echo 'NoC16 per-port wait, residence, stall, and conservation tests passed.'
