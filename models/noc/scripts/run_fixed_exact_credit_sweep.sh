#!/usr/bin/env bash
set -u

router_dir=$(cd "$(dirname "$0")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
output="$router_dir/results/fixed_exact_credit_depth_sweep.csv"

mkdir -p "$router_dir/results"
printf 'scenario,total_q,advertised_credits_per_lane,shared_per_port,islip_iterations,bypass,seed,accepted_per_lane,total_accepted,output_capacity,utilization,network_latency,read_conflicts,lookaside_high_water\n' > "$output"

for test in \
  t1_one_port_all_lanes \
  t2_all_ports_one_lane_hotspot \
  t3_all_ports_all_lanes_hotspot \
  t4_all_ports_all_lanes_balanced; do
  case "$test" in
    t1_*) capacity=4 ;;
    t2_*) capacity=1 ;;
    t3_*) capacity=4 ;;
    t4_*) capacity=32 ;;
  esac
  config="$router_dir/configs/$test.cfg"
  for total_q in 32 48 64; do
    credits=$((total_q / 4))
    for iterations in 1 2; do
      for seed in 1 2 3 4 5; do
        name="${test}_${total_q}_${iterations}_${seed}"
        log="/tmp/router_fixed_exact_${name}.log"
        trace="/tmp/router_fixed_exact_${name}.csv"
        "$booksim" "$config" injection_rate=1.0 sim_type=throughput \
          voq_ideal_output=1 voq_bypass=1 \
          vc_buf_size="$credits" voq_shared_buf_size=0 \
          voq_storage=sram_fixed voq_bank_policy=fixed \
          voq_tagged_credits=1 voq_total_buf_size="$total_q" \
          voq_lookaside_size=0 voq_credit_policy=strict_pool \
          alloc_iters="$iterations" seed="$seed" \
          voq_trace_file="$trace" > "$log"
        rm -f "$trace"

        accepted=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Accepted packet rate average =/{print $6; exit}' "$log")
        latency=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Network latency average =/{print $5; exit}' "$log")
        stats=$(awk '/^BANK_STATS /{print; exit}' "$log")
        conflicts=$(sed -n 's/.*read_conflicts=\([0-9]*\).*/\1/p' <<< "$stats")
        high_water=$(sed -n 's/.*lookaside_high_water=\([0-9]*\).*/\1/p' <<< "$stats")
        [[ -n "$accepted" && -n "$latency" && "$conflicts" == 0 && "$high_water" == 0 ]] || {
          echo "Failed or unexpected fixed-bank conflict: $name" >&2
          exit 1
        }
        total=$(awk -v rate="$accepted" 'BEGIN { printf "%.6f", rate * 32.0 }')
        utilization=$(awk -v total="$total" -v cap="$capacity" 'BEGIN { printf "%.6f", total / cap }')
        printf '%s,%d,%d,0,%d,1,%d,%s,%s,%d,%s,%s,0,0\n' \
          "$test" "$total_q" "$credits" "$iterations" "$seed" \
          "$accepted" "$total" "$capacity" "$utilization" "$latency" \
          >> "$output"
      done
    done
  done
done

echo "$output"
