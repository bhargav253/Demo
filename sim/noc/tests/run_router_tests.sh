#!/usr/bin/env bash
set -u

router_dir=$(cd "$(dirname "$0")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
test_dir="$router_dir/results/tests"
mkdir -p "$test_dir"

fail()
{
  echo "FAIL: $*" >&2
  exit 1
}

run_case()
{
  name=$1
  config=$2
  shift 2
  # This pinned BookSim revision returns status 1 even after a successful
  # simulation, so completion is judged from its mandatory summary marker.
  "$booksim" "$config" "$@" \
    voq_trace_file="$test_dir/$name.csv" > "$test_dir/$name.log"
  grep -q '====== Overall Traffic Statistics ======' "$test_dir/$name.log" || \
    fail "$name did not complete"
}

echo "[1/8] iSLIP matching and fairness"
g++ -Wall -I"$router_dir/booksim2/src" \
  -I"$router_dir/booksim2/src/allocators" \
  "$router_dir/tests/islip_unit.cpp" \
  "$router_dir/booksim2/src/module.o" \
  "$router_dir/booksim2/src/config_utils.o" \
  "$router_dir"/booksim2/src/allocators/*.o \
  "$router_dir"/booksim2/src/arbiters/*.o \
  "$router_dir/booksim2/src/random_utils.o" \
  "$router_dir/booksim2/src/rng_wrapper.o" \
  "$router_dir/booksim2/src/rng_double_wrapper.o" \
  "$router_dir/booksim2/src/lex.yy.o" \
  "$router_dir/booksim2/src/y.tab.o" \
  -o "$test_dir/islip_unit" || fail "compile iSLIP unit test"
"$test_dir/islip_unit" || fail "iSLIP unit test"

common=('injection_process=bernoulli_sources({{0}})' injection_rate=1.0
        voq_ideal_output=1 sim_type=throughput seed=1)

echo "[2/8] exact queued pipeline and S2 credit timing"
run_case single_queue "$router_dir/configs/lane_voq_trace_2lane.cfg" \
  "${common[@]}" voq_bypass=0
awk -F, '
  NR>1 && $4==0 { cycle[$2]=$1; action[$2]=$13 }
  END {
    exit !(cycle["S0_ENQUEUE"]==2 && cycle["S1_MATCH"]==3 &&
           cycle["S2_READ_DONE"]==4 && cycle["S3_SEND"]==4 &&
           action["S2_READ_DONE"]=="REPLENISH_SHARED_STRICT" &&
           action["S3_SEND"]=="CREDIT_HANDLED_IN_S2")
  }' "$test_dir/single_queue.csv" || fail "queued pipeline sequence"

echo "[3/8] exact bypass fast path and early landing credit"
run_case single_bypass "$router_dir/configs/lane_voq_trace_2lane.cfg" \
  "${common[@]}" voq_bypass=1
awk -F, '
  NR>1 && $4==0 {
    seen[$2]++; cycle[$2]=$1; action[$2]=$13; occupancy=$10;
    free=$11; debt=$12; gsub(/"/, "", debt)
  }
  END {
    exit !(seen["S0_BYPASS"]==1 && seen["S3_BYPASS_SEND"]==1 &&
           !seen["S0_ENQUEUE"] && cycle["S0_BYPASS"]==cycle["S3_BYPASS_SEND"] &&
           action["S0_BYPASS"]=="RETURN_BYPASS_LANDING" &&
           occupancy==0 && free==16 && debt=="[0;0;0;0]")
  }' "$test_dir/single_bypass.csv" || fail "bypass fast path"

echo "[4/8] bypass contention and loser enqueue"
run_case bypass_contention \
  "$router_dir/configs/t2_all_ports_one_lane_hotspot.cfg" \
  'injection_process=bernoulli_sources({{0,4}})' injection_rate=1.0 \
  voq_ideal_output=1 sim_type=throughput seed=1 voq_bypass=1
awk -F, '
  NR>1 && $1==2 && $2=="S0_BYPASS" { bypass++ }
  NR>1 && $1==2 && $2=="S0_ENQUEUE" { enqueue++ }
  NR>1 && (($5%4)!=$8 || ($6%4)!=$8) { bad_lane=1 }
  END { exit !(bypass==1 && enqueue==1 && !bad_lane) }
  ' "$test_dir/bypass_contention.csv" || fail "bypass contention/lane preservation"

debt_common=('injection_process=bernoulli_sources({{0,4}})'
             injection_rate=1.0 voq_bypass=0 voq_ideal_output=1
             sim_type=throughput vc_buf_size=4 voq_shared_buf_size=2 seed=1)

echo "[5/8] strict-pool debt-first repayment"
run_case debt_strict "$router_dir/configs/t2_all_ports_one_lane_hotspot.cfg" \
  "${debt_common[@]}" voq_credit_policy=strict_pool
awk -F, '
  NR>1 && $7==0 && $1==5 && $2=="S0_ENQUEUE" && $13=="WITHHOLD_LANE" { withheld=1 }
  NR>1 && $7==0 && $1==6 && $2=="S2_READ_DONE" {
    debt=$12; gsub(/"/, "", debt)
    if(debt=="[1;0;0;0]" && $13=="REPLENISH_SHARED_STRICT") repaid=1
  }
  END { exit !(withheld && repaid) }
  ' "$test_dir/debt_strict.csv" || fail "strict-pool repayment ordering"

echo "[6/8] lane-first eager repayment"
run_case debt_lane_first "$router_dir/configs/t2_all_ports_one_lane_hotspot.cfg" \
  "${debt_common[@]}" voq_credit_policy=lane_first
awk -F, '
  NR>1 && $7==0 && $1==5 && $2=="S0_ENQUEUE" && $13=="WITHHOLD_LANE" { withheld=1 }
  NR>1 && $7==0 && $1==6 && $2=="S2_READ_DONE" {
    debt=$12; gsub(/"/, "", debt)
    if(debt=="[2;0;0;0]" && $13=="RETURN_LANE_EAGER") returned=1
  }
  END { exit !(withheld && returned) }
  ' "$test_dir/debt_lane_first.csv" || fail "lane-first repayment ordering"

echo "[7/8] capacity and token conservation assertions"
# Every case above executes LaneVOQRouter::_CheckInvariants each cycle. Also
# independently bound every traced occupancy for the small debt configurations.
for trace in "$test_dir/debt_strict.csv" "$test_dir/debt_lane_first.csv"; do
  awk -F, 'NR>1 && ($10<0 || $10>18 || $11<0 || $11>2) { exit 1 }' "$trace" ||
    fail "capacity bounds in $trace"
done

echo "[8/8] full-rate four-lane bypass throughput"
run_case t1_full "$router_dir/configs/t1_one_port_all_lanes.cfg" \
  injection_rate=1.0 voq_ideal_output=1 sim_type=throughput seed=1 \
  vc_buf_size=4 voq_shared_buf_size=16 alloc_iters=2 voq_bypass=1
awk '
  /====== Overall Traffic Statistics ======/ { overall=1 }
  overall && /Network latency average =/ { latency=$5; have_latency=1 }
  overall && /Accepted packet rate average =/ { accepted=$6; have_accepted=1 }
  END { exit !(have_latency && have_accepted && latency==4 && accepted==0.125) }
  ' "$test_dir/t1_full.log" || fail "full-rate bypass throughput/latency"

echo "All router regression tests passed."
