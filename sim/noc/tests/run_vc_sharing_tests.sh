#!/usr/bin/env bash
set -euo pipefail

router_dir=$(cd "$(dirname "$0")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

common=(classes=2 num_vcs=2 'injection_rate={1.0,1.0}'
  'traffic={fixed_port_lane({8,4,7}),fixed_port_lane({8,4,7})}'
  'injection_process={bernoulli_sources({{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27}}),bernoulli_sources({{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27}})}' voq_vc_sharing=1
  voq_tagged_credits=0
  voq_shared_buf_size=0 voq_storage=sram_fixed voq_bank_policy=fixed
  voq_lookaside_size=0 alloc_iters=2
  voq_ideal_output=1 voq_bypass=1 sim_type=throughput seed=7)

run_case() {
  local total_q=$2
  local iterations=$3
  local allocator=${4:-islip}
  local reserved=$1
  local lane_depth=$((total_q / 4))
  set +e
  "$booksim" "$router_dir/configs/t3_all_ports_all_lanes_hotspot.cfg" \
    "${common[@]}" vc_buf_size="$lane_depth" voq_total_buf_size="$total_q" \
    voq_reserved_per_vc="$reserved" voq_credit_policy=shared_first \
    alloc_iters="$iterations" voq_allocator="$allocator" \
    voq_trace_file="$test_dir/r${reserved}_${total_q}_i${iterations}_${allocator}.csv" \
    > "$test_dir/r${reserved}_${total_q}_i${iterations}_${allocator}.log"
  status=$?
  set -e
  (( status == 0 || status == 255 )) || fail "R$reserved Q$total_q simulator status $status"
  grep -q 'Overall Traffic Statistics' "$test_dir/r${reserved}_${total_q}_i${iterations}_${allocator}.log" || fail "R$reserved Q$total_q I$iterations $allocator no results"
}

echo '[vc 1/4] pool-first counters conserve Q32/Q48/Q64 credits'
for total_q in 32 48 64; do
  for reserved in 1 2 4; do
    for iterations in 1 2; do run_case "$reserved" "$total_q" "$iterations"; done
  done
done
run_case 1 32 0 max_size

set +e
"$booksim" "$router_dir/configs/t3_all_ports_all_lanes_hotspot.cfg" \
  "${common[@]}" vc_buf_size=12 voq_total_buf_size=48 \
  voq_reserved_per_vc=1 alloc_iters=2 voq_allocator=islip \
  voq_read_latency=3 voq_trace_file="$test_dir/read3.csv" \
  > "$test_dir/read3.log"
status=$?
set -e
(( status == 0 || status == 255 )) || fail "three-cycle read simulator status $status"

echo '[vc 2/4] both VC VOQs make forward progress'
for reserved in 1 2 4; do
  for vc in 0 1; do
    count=$(awk -F, -v vc="$vc" 'NR>1 && $2=="S1_MATCH" && $14==vc {n++} END{print n+0}' "$test_dir/r${reserved}_32_i2_islip.csv")
    (( count > 100 )) || fail "R$reserved VC $vc did not make progress"
  done
  stats=$(awk '/^BANK_STATS /{print; exit}' "$test_dir/r${reserved}_32_i2_islip.log")
  [[ $stats == *'read_conflicts=0'* && $stats == *'lookaside_high_water=0'* ]] ||
    fail "R$reserved fixed-bank conflict/lookaside"
done

echo '[vc 3/4] receiver returns only untagged VC credits at release'
awk -F, 'NR>1 && $2=="S2_READ_DONE" {seen++; if($13!="RETURN_VC_UNTAGGED") bad=1}
  END{exit bad || seen<100}' "$test_dir/r1_32_i2_islip.csv" || fail 'untagged VC credit return'

awk -F, 'NR>1 && $2=="S1_MATCH" && $13=="MAX_SIZE" {seen++}
  END{exit seen<100}' "$test_dir/r1_32_i0_max_size.csv" || fail 'maximum matcher not exercised'

awk -F, '
  NR>1 && $2=="S1_MATCH" {mcycle[$4]=$1}
  NR>1 && $2=="S4_READ_DONE" && ($4 in mcycle) {
    seen++; if($1-mcycle[$4] != 3) bad=1
  }
  NR>1 && $2=="S5_SEND" {sent++}
  END{exit bad || seen<100 || sent<100}
' "$test_dir/read3.csv" || fail 'pipelined S1/S4/S5 timing'

echo '[vc 4/4] hierarchical selection preserves one physical transfer per lane output'
for trace in "$test_dir"/*.csv; do
  awk -F, '
    NR>1 && ($2=="S3_BYPASS_SEND" || $2=="S3_SEND") {
      key=$1 ":" $9 ":" $8
      if(++seen[key] > 1) exit 1
    }
  ' "$trace" || fail "multiple VC winners on one physical output"
done

echo 'All VC-sharing router tests passed.'
