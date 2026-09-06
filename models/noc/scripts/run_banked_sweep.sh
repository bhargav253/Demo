#!/usr/bin/env bash
set -u

router_dir=$(cd "$(dirname "$0")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
config="$router_dir/configs/t4_all_ports_all_lanes_balanced.cfg"
output="$router_dir/results/banked_vs_flop_t4.csv"

mkdir -p "$router_dir/results"
printf 'storage,bank_policy,credit_policy,total_q,private_per_lane,shared_per_port,islip_iterations,bypass,seed,utilization,network_latency,read_requests,read_matches,read_conflicts,read_conflict_rate,lookaside_bound,lookaside_high_water\n' > "$output"

for total_q in 32 48; do
  shared=$((total_q - 16))
  if [[ "$total_q" == 32 ]]; then bound=12; else bound=18; fi
  for policy in strict_pool lane_first; do
    for iterations in 1 2; do
      for seed in 1 2 3 4 5; do
        for mode in flop sram_fixed sram_shared_rr sram_shared_pressure; do
          storage=$mode
          bank_policy=none
          tagged=0
          lookaside=0
          if [[ "$mode" == sram_fixed ]]; then
            bank_policy=fixed
            tagged=1
            lookaside=$bound
          elif [[ "$mode" == sram_shared_rr ]]; then
            storage=sram_shared
            bank_policy=rr
            tagged=1
            lookaside=$bound
          elif [[ "$mode" == sram_shared_pressure ]]; then
            storage=sram_shared
            bank_policy=pressure
            tagged=1
            lookaside=$bound
          fi

          name="${mode}_${policy}_${total_q}_${iterations}_${seed}"
          log="/tmp/router_banked_${name}.log"
          trace="/tmp/router_banked_${name}.csv"
          "$booksim" "$config" injection_rate=1.0 sim_type=throughput \
            voq_ideal_output=1 voq_bypass=1 vc_buf_size=4 \
            voq_shared_buf_size="$shared" voq_total_buf_size="$total_q" \
            voq_storage="$storage" voq_bank_policy="$bank_policy" \
            voq_tagged_credits="$tagged" voq_lookaside_size="$lookaside" \
            voq_credit_policy="$policy" alloc_iters="$iterations" \
            seed="$seed" voq_trace_file="$trace" > "$log"
          rm -f "$trace"

          accepted=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Accepted packet rate average =/{print $6; exit}' "$log")
          latency=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Network latency average =/{print $5; exit}' "$log")
          [[ -n "$accepted" && -n "$latency" ]] || {
            echo "Failed $name" >&2
            exit 1
          }
          utilization="$accepted"
          requests=0; matches=0; conflicts=0; high_water=0
          if [[ "$storage" != flop ]]; then
            stats=$(awk '/^BANK_STATS /{print; exit}' "$log")
            requests=$(sed -n 's/.*read_requests=\([0-9]*\).*/\1/p' <<< "$stats")
            matches=$(sed -n 's/.*read_matches=\([0-9]*\).*/\1/p' <<< "$stats")
            conflicts=$(sed -n 's/.*read_conflicts=\([0-9]*\).*/\1/p' <<< "$stats")
            high_water=$(sed -n 's/.*lookaside_high_water=\([0-9]*\).*/\1/p' <<< "$stats")
          fi
          conflict_rate=$(awk -v c="$conflicts" -v r="$requests" 'BEGIN { if(r) printf "%.6f", c/r; else print "0.000000" }')
          printf '%s,%s,%s,%d,4,%d,%d,1,%d,%s,%s,%s,%s,%s,%s,%d,%s\n' \
            "$storage" "$bank_policy" "$policy" "$total_q" "$shared" \
            "$iterations" "$seed" "$utilization" "$latency" "$requests" \
            "$matches" "$conflicts" "$conflict_rate" "$bound" "$high_water" \
            >> "$output"
        done
      done
    done
  done
done

echo "$output"
