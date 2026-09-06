#!/usr/bin/env bash
set -u

router_dir=$(cd "$(dirname "$0")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
test_dir="$router_dir/results/tests"
mkdir -p "$test_dir"

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "[bank 1/4] exhaustive lookaside upper bounds"
python3 "$router_dir/tests/lookaside_exhaustive.py" || fail "lookaside proof"

echo "[bank 2/4] fixed-lane banks are conflict free"
"$booksim" "$router_dir/configs/t4_all_ports_all_lanes_balanced.cfg" \
  injection_rate=1.0 sim_type=throughput voq_ideal_output=1 \
  voq_storage=sram_fixed voq_tagged_credits=1 \
  voq_total_buf_size=32 voq_shared_buf_size=16 voq_lookaside_size=12 \
  alloc_iters=2 seed=1 voq_trace_file="$test_dir/bank_fixed.csv" \
  > "$test_dir/bank_fixed.log"
stats=$(awk '/^BANK_STATS /{print; exit}' "$test_dir/bank_fixed.log")
[[ "$stats" == *"read_conflicts=0"* && "$stats" == *"lookaside_high_water=0"* ]] ||
  fail "fixed-lane bank conflicts"

echo "[bank 3/4] Q32 shared-bank bound and conflicts"
"$booksim" "$router_dir/configs/t4_all_ports_all_lanes_balanced.cfg" \
  injection_rate=1.0 sim_type=throughput voq_ideal_output=1 \
  voq_storage=sram_shared voq_tagged_credits=1 voq_bank_policy=rr \
  voq_total_buf_size=32 voq_shared_buf_size=16 voq_lookaside_size=12 \
  alloc_iters=2 seed=2 voq_trace_file="$test_dir/bank_shared_q32.csv" \
  > "$test_dir/bank_shared_q32.log"
stats=$(awk '/^BANK_STATS /{print; exit}' "$test_dir/bank_shared_q32.log")
conflicts=$(sed -n 's/.*read_conflicts=\([0-9]*\).*/\1/p' <<< "$stats")
high=$(sed -n 's/.*lookaside_high_water=\([0-9]*\).*/\1/p' <<< "$stats")
(( conflicts > 0 && high <= 12 )) || fail "Q32 shared-bank checks"

echo "[bank 4/4] Q48 shared-bank bound and conflicts"
"$booksim" "$router_dir/configs/t4_all_ports_all_lanes_balanced.cfg" \
  injection_rate=1.0 sim_type=throughput voq_ideal_output=1 \
  voq_storage=sram_shared voq_tagged_credits=1 voq_bank_policy=pressure \
  voq_total_buf_size=48 voq_shared_buf_size=32 voq_lookaside_size=18 \
  alloc_iters=2 seed=2 voq_trace_file="$test_dir/bank_shared_q48.csv" \
  > "$test_dir/bank_shared_q48.log"
stats=$(awk '/^BANK_STATS /{print; exit}' "$test_dir/bank_shared_q48.log")
conflicts=$(sed -n 's/.*read_conflicts=\([0-9]*\).*/\1/p' <<< "$stats")
high=$(sed -n 's/.*lookaside_high_water=\([0-9]*\).*/\1/p' <<< "$stats")
(( conflicts > 0 && high <= 18 )) || fail "Q48 shared-bank checks"

echo "All banked-router tests passed."
