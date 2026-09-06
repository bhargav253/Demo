#!/usr/bin/env bash
set -u

router_dir=$(cd "$(dirname "$0")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
output="$router_dir/results/full_load_matrix.csv"

mkdir -p "$router_dir/results"
printf 'scenario,policy,total_q,private_per_lane,shared_per_port,islip_iterations,bypass,seed,accepted_per_lane,total_accepted,output_capacity,utilization,network_latency\n' > "$output"

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
  for policy in strict_pool lane_first; do
    for total_q in 32 48; do
      shared=$((total_q - 16))
      for iterations in 1 2; do
        for seed in 1 2 3 4 5; do
          log="/tmp/router_full_${test}_${policy}_${total_q}_${iterations}_${seed}.log"
          trace="/tmp/router_full_${test}_${policy}_${total_q}_${iterations}_${seed}.csv"
          "$booksim" "$config" \
            injection_rate=1.0 sim_type=throughput voq_ideal_output=1 \
            voq_credit_policy="$policy" voq_bypass=1 \
            vc_buf_size=4 voq_shared_buf_size="$shared" \
            alloc_iters="$iterations" seed="$seed" \
            voq_trace_file="$trace" > "$log"
          rm -f "$trace"

          accepted=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Accepted packet rate average =/{print $6; exit}' "$log")
          network_latency=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Network latency average =/{print $5; exit}' "$log")
          if [[ -z "$accepted" || -z "$network_latency" ]]; then
            echo "Failed run: $test $policy total_q=$total_q iterations=$iterations seed=$seed" >&2
            exit 1
          fi
          total=$(awk -v rate="$accepted" 'BEGIN { printf "%.6f", rate * 32.0 }')
          utilization=$(awk -v total="$total" -v cap="$capacity" 'BEGIN { printf "%.6f", total / cap }')
          printf '%s,%s,%d,4,%d,%d,1,%d,%s,%s,%d,%s,%s\n' \
            "$test" "$policy" "$total_q" "$shared" "$iterations" "$seed" \
            "$accepted" "$total" "$capacity" "$utilization" \
            "$network_latency" >> "$output"
        done
      done
    done
  done
done

echo "$output"
