#!/usr/bin/env bash
set -uo pipefail

router_dir=$(cd "$(dirname "$0")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
output="$router_dir/results/q48_read_latency_sweep.csv"
summary="$router_dir/results/q48_read_latency_summary.csv"
mkdir -p "$router_dir/results"

printf 'scenario,read_latency,trace_read_stage,trace_send_stage,mix,seed,utilization,network_latency,req_rate,req_latency,rsp_rate,rsp_latency,read_conflicts,lookaside_high_water\n' > "$output"

class_stat() {
  local log=$1 class=$2 field=$3
  awk -v wanted="$class" -v field="$field" '
    $1=="Class" { c=$2; sub(":", "", c) }
    c==wanted && index($0, field " =") { print $NF; exit }
  ' "$log"
}

for scenario in t3_all_ports_all_lanes_hotspot t4_all_ports_all_lanes_balanced; do
  capacity=4
  config="$router_dir/configs/$scenario.cfg"
  if [[ $scenario == t3_* ]]; then
    traffic='{fixed_port_lane({8,4,7}),fixed_port_lane({8,4,7})}'
    injection='{bernoulli_sources({{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27}}),bernoulli_sources({{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27}})}'
  else
    capacity=32
    traffic='{lane_uniform({8,4}),lane_uniform({8,4})}'
    injection='{bernoulli,bernoulli}'
  fi
  for read_latency in 1 2 3; do
    case "$read_latency" in
      1) read_stage=S2; send_stage=S3 ;;
      2) read_stage=S3; send_stage=S4 ;;
      3) read_stage=S4; send_stage=S5 ;;
    esac
    for mix in 50/50 75/25 90/10; do
      case "$mix" in
        50/50) rates='{1.0,1.0}' ;;
        75/25) rates='{1.0,0.333333}' ;;
        90/10) rates='{1.0,0.111111}' ;;
      esac
      for seed in 1 2 3 4 5; do
        log="/tmp/router_read_${scenario}_l${read_latency}_${mix//\//_}_${seed}.log"
        "$booksim" "$config" classes=2 num_vcs=2 injection_rate="$rates" \
          traffic="$traffic" injection_process="$injection" sim_type=throughput \
          voq_vc_sharing=1 voq_reserved_per_vc=1 voq_tagged_credits=0 \
          vc_buf_size=12 voq_shared_buf_size=0 voq_storage=sram_fixed \
          voq_bank_policy=fixed voq_total_buf_size=48 voq_lookaside_size=0 \
          voq_credit_policy=shared_first alloc_iters=2 voq_allocator=islip \
          voq_read_latency="$read_latency" voq_bypass=1 voq_ideal_output=1 \
          seed="$seed" voq_trace_file=/tmp/router_read_trace.csv > "$log"
        req_rate=$(class_stat "$log" 0 'Accepted packet rate average')
        req_lat=$(class_stat "$log" 0 'Network latency average')
        rsp_rate=$(class_stat "$log" 1 'Accepted packet rate average')
        rsp_lat=$(class_stat "$log" 1 'Network latency average')
        util=$(awk -v a="$req_rate" -v b="$rsp_rate" -v c="$capacity" 'BEGIN{printf "%.6f",(a+b)*32/c}')
        lat=$(awk -v ar="$req_rate" -v al="$req_lat" -v br="$rsp_rate" -v bl="$rsp_lat" 'BEGIN{printf "%.6f",(ar*al+br*bl)/(ar+br)}')
        stats=$(awk '/^BANK_STATS /{print; exit}' "$log")
        conflicts=$(sed -n 's/.*read_conflicts=\([0-9]*\).*/\1/p' <<< "$stats")
        high=$(sed -n 's/.*lookaside_high_water=\([0-9]*\).*/\1/p' <<< "$stats")
        printf '%s,%d,%s,%s,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s\n' \
          "$scenario" "$read_latency" "$read_stage" "$send_stage" "$mix" "$seed" \
          "$util" "$lat" "$req_rate" "$req_lat" "$rsp_rate" "$rsp_lat" \
          "$conflicts" "$high" >> "$output"
      done
    done
  done
done

printf 'scenario,read_latency,trace_read_stage,trace_send_stage,mix,utilization,network_latency,req_rate,req_latency,rsp_rate,rsp_latency\n' > "$summary"
awk -F, 'NR>1 {k=$1 FS $2 FS $3 FS $4 FS $5; n[k]++; u[k]+=$7; l[k]+=$8; rr[k]+=$9; rl[k]+=$10; sr[k]+=$11; sl[k]+=$12}
  END {for(k in n) printf "%s,%.6f,%.3f,%.6f,%.3f,%.6f,%.3f\n",k,u[k]/n[k],l[k]/n[k],rr[k]/n[k],rl[k]/n[k],sr[k]/n[k],sl[k]/n[k]}' \
  "$output" | sort >> "$summary"

echo "$output"
echo "$summary"
