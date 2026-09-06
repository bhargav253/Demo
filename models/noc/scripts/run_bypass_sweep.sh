#!/usr/bin/env bash
set -u

router_dir=$(cd "$(dirname "$0")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
output="$router_dir/results/bypass_comparison.csv"

mkdir -p "$router_dir/results"
printf 'scenario,load,policy,bypass,seed,private_per_lane,shared_per_port,islip_iterations,accepted_per_lane,total_accepted,output_capacity,utilization,packet_latency,network_latency\n' > "$output"

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
  for load in nominal stress; do
    for policy in strict_pool lane_first; do
      for bypass in 0 1; do
        for private in 2 3 4; do
          for seed in 1 2 3 4 5; do
          log="/tmp/router_bypass_${test}_${load}_${policy}_${bypass}_${private}_${seed}.log"
          trace="/tmp/router_bypass_${test}_${load}_${policy}_${bypass}_${private}_${seed}.csv"
          args=(alloc_iters=2 voq_credit_policy="$policy" voq_bypass="$bypass"
                vc_buf_size="$private" voq_shared_buf_size=16 seed="$seed"
                voq_trace_file="$trace")
          if [[ "$load" == stress ]]; then
            args+=(injection_rate=1.0 sim_type=throughput voq_ideal_output=1)
          else
            args+=(injection_rate=0.03 sim_type=latency)
          fi
          "$booksim" "$config" "${args[@]}" > "$log"
          rm -f "$trace"

          accepted=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Accepted packet rate average =/{print $6; exit}' "$log")
          packet_latency=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Packet latency average =/{print $5; exit}' "$log")
          network_latency=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Network latency average =/{print $5; exit}' "$log")
          if [[ -z "$accepted" || -z "$packet_latency" || -z "$network_latency" ]]; then
            echo "Failed run: $test $load $policy bypass=$bypass seed=$seed" >&2
            exit 1
          fi
          total=$(awk -v rate="$accepted" 'BEGIN { printf "%.6f", rate * 32.0 }')
          utilization=$(awk -v total="$total" -v cap="$capacity" 'BEGIN { printf "%.6f", total / cap }')
          printf '%s,%s,%s,%d,%d,%d,16,2,%s,%s,%d,%s,%s,%s\n' \
            "$test" "$load" "$policy" "$bypass" "$seed" "$private" "$accepted" \
            "$total" "$capacity" "$utilization" "$packet_latency" \
            "$network_latency" >> "$output"
          done
        done
      done
    done
  done
done

echo "$output"
