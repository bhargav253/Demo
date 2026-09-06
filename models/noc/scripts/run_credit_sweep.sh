#!/usr/bin/env bash
set -u

router_dir=$(cd "$(dirname "$0")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
scenario=${1:-t4}
case "$scenario" in
  t3)
    config="$router_dir/configs/t3_all_ports_all_lanes_hotspot.cfg"
    output="$router_dir/results/credit_policy_sweep_t3.csv"
    ;;
  t4)
    config="$router_dir/configs/t4_all_ports_all_lanes_balanced.cfg"
    output="$router_dir/results/credit_policy_sweep.csv"
    ;;
  t4_p5)
    config="$router_dir/configs/t4_all_ports_all_lanes_balanced.cfg"
    output="$router_dir/results/credit_policy_sweep_t4_p5.csv"
    ;;
  *)
    echo "usage: $0 [t3|t4|t4_p5]" >&2
    exit 2
    ;;
esac

mkdir -p "$router_dir/results"
printf 'policy,private_per_lane,shared_per_port,islip_iterations,seed,accepted_per_lane,total_accepted,network_latency\n' > "$output"

if [[ "$scenario" == "t4_p5" ]]; then
  private_values="5"
  shared_values="12 28"
else
  private_values="1 2 4"
  shared_values="16 32"
fi

for policy in strict_pool lane_first; do
  for private in $private_values; do
    for shared in $shared_values; do
      for iterations in 1 2; do
        for seed in 1 2 3 4 5; do
          log="/tmp/router_credit_${scenario}_${policy}_${private}_${shared}_${iterations}_${seed}.log"
          "$booksim" "$config" \
            injection_rate=1.0 sim_type=throughput voq_ideal_output=1 \
            voq_credit_policy="$policy" vc_buf_size="$private" \
            voq_shared_buf_size="$shared" alloc_iters="$iterations" \
            seed="$seed" voq_trace_file=/tmp/router_credit_trace.csv > "$log"

          accepted=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Accepted packet rate average =/{print $6; exit}' "$log")
          network_latency=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Network latency average =/{print $5; exit}' "$log")
          if [[ -z "$accepted" || -z "$network_latency" ]]; then
            echo "Failed run: $policy private=$private shared=$shared iterations=$iterations seed=$seed" >&2
            exit 1
          fi
          total=$(awk -v rate="$accepted" 'BEGIN { printf "%.6f", rate * 32.0 }')
          printf '%s,%d,%d,%d,%d,%s,%s,%s\n' \
            "$policy" "$private" "$shared" "$iterations" "$seed" \
            "$accepted" "$total" "$network_latency" >> "$output"
        done
      done
    done
  done
done

echo "$output"
