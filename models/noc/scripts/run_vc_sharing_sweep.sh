#!/usr/bin/env bash
set -uo pipefail

router_dir=$(cd "$(dirname "$0")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
output="$router_dir/results/vc_sharing_depth_sweep.csv"
summary="$router_dir/results/vc_sharing_depth_summary.csv"
mkdir -p "$router_dir/results"

printf 'scenario,total_q,entries_per_lane,islip_iterations,allocator,vcs,reserved_per_vc,pool_credits,policy,mix,seed,total_utilization,total_network_latency,req_rate,req_latency,rsp_rate,rsp_latency,read_conflicts,lookaside_high_water\n' > "$output"

class_stat() {
  local log=$1 class=$2 field=$3
  awk -v wanted="$class" -v field="$field" '
    $1=="Class" { c=$2; sub(":", "", c) }
    c==wanted && index($0, field " =") { print $NF; exit }
  ' "$log"
}

for scenario in t3_all_ports_all_lanes_hotspot t4_all_ports_all_lanes_balanced; do
  capacity=4
  [[ $scenario == t4_* ]] && capacity=32
  config="$router_dir/configs/$scenario.cfg"
  if [[ $scenario == t3_* ]]; then
    class_traffic='{fixed_port_lane({8,4,7}),fixed_port_lane({8,4,7})}'
    class_injection='{bernoulli_sources({{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27}}),bernoulli_sources({{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27}})}'
  else
    class_traffic='{lane_uniform({8,4}),lane_uniform({8,4})}'
    class_injection='{bernoulli,bernoulli}'
  fi
  for total_q in 32 48 64; do
    lane_depth=$((total_q / 4))
  for mode in islip1 islip2 max_size; do
    allocator=islip
    iterations=${mode#islip}
    if [[ $mode == max_size ]]; then allocator=max_size; iterations=0; fi
  for seed in 1 2 3 4 5; do
    log="/tmp/router_vc1_${scenario}_${total_q}_i${iterations}_${seed}.log"
    "$booksim" "$config" injection_rate=1.0 sim_type=throughput \
      voq_ideal_output=1 voq_bypass=1 vc_buf_size="$lane_depth" voq_shared_buf_size=0 \
      voq_storage=sram_fixed voq_bank_policy=fixed voq_tagged_credits=0 \
      voq_total_buf_size="$total_q" voq_lookaside_size=0 voq_vc_sharing=1 \
      voq_reserved_per_vc="$lane_depth" alloc_iters="$iterations" \
      voq_allocator="$allocator" seed="$seed" \
      voq_trace_file=/tmp/router_vc1_trace.csv > "$log"
    rate=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Accepted packet rate average =/{print $6; exit}' "$log")
    lat=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Network latency average =/{print $5; exit}' "$log")
    util=$(awk -v r="$rate" -v c="$capacity" 'BEGIN{printf "%.6f",r*32/c}')
    printf '%s,%d,%d,%d,%s,1,%d,0,exact,100/0,%d,%s,%s,%s,%s,0,0,0,0\n' "$scenario" "$total_q" "$lane_depth" "$iterations" "$allocator" "$lane_depth" "$seed" "$util" "$lat" "$rate" "$lat" >> "$output"
  done

  for mix in 50/50 75/25 90/10; do
    case "$mix" in
      50/50) rates='{1.0,1.0}' ;;
      75/25) rates='{1.0,0.333333}' ;;
      90/10) rates='{1.0,0.111111}' ;;
    esac
    for reserved in 1 2 4; do
      pool=$((lane_depth - 2 * reserved))
      (( pool >= 0 )) || continue
      for seed in 1 2 3 4 5; do
        log="/tmp/router_vc2_${scenario}_${total_q}_i${iterations}_${mix//\//_}_r${reserved}_${seed}.log"
        "$booksim" "$config" classes=2 num_vcs=2 injection_rate="$rates" \
          traffic="$class_traffic" injection_process="$class_injection" \
          sim_type=throughput \
          voq_vc_sharing=1 voq_reserved_per_vc="$reserved" voq_tagged_credits=0 \
          vc_buf_size="$lane_depth" voq_shared_buf_size=0 voq_storage=sram_fixed \
          voq_bank_policy=fixed voq_total_buf_size="$total_q" voq_lookaside_size=0 \
          voq_credit_policy=shared_first alloc_iters="$iterations" \
          voq_allocator="$allocator" voq_bypass=1 \
          voq_ideal_output=1 seed="$seed" voq_trace_file=/tmp/router_vc2_trace.csv > "$log"
        req_rate=$(class_stat "$log" 0 'Accepted packet rate average')
        req_lat=$(class_stat "$log" 0 'Network latency average')
        rsp_rate=$(class_stat "$log" 1 'Accepted packet rate average')
        rsp_lat=$(class_stat "$log" 1 'Network latency average')
        total_rate=$(awk -v a="$req_rate" -v b="$rsp_rate" 'BEGIN{printf "%.9f",a+b}')
        util=$(awk -v r="$total_rate" -v c="$capacity" 'BEGIN{printf "%.6f",r*32/c}')
        lat=$(awk -v ar="$req_rate" -v al="$req_lat" -v br="$rsp_rate" -v bl="$rsp_lat" 'BEGIN{printf "%.6f",(ar*al+br*bl)/(ar+br)}')
        stats=$(awk '/^BANK_STATS /{print; exit}' "$log")
        conflicts=$(sed -n 's/.*read_conflicts=\([0-9]*\).*/\1/p' <<< "$stats")
        high=$(sed -n 's/.*lookaside_high_water=\([0-9]*\).*/\1/p' <<< "$stats")
        printf '%s,%d,%d,%d,%s,2,%d,%d,pool_first,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s\n' \
          "$scenario" "$total_q" "$lane_depth" "$iterations" "$allocator" "$reserved" "$pool" "$mix" "$seed" "$util" "$lat" \
          "$req_rate" "$req_lat" "$rsp_rate" "$rsp_lat" "$conflicts" "$high" >> "$output"
      done
    done
  done
  done
  done
done

printf 'scenario,total_q,entries_per_lane,islip_iterations,allocator,vcs,reserved_per_vc,pool_credits,policy,offered_mix,utilization,network_latency,req_rate,req_latency,rsp_rate,rsp_latency\n' > "$summary"
awk -F, 'NR>1 {
  k=$1 FS $2 FS $3 FS $4 FS $5 FS $6 FS $7 FS $8 FS $9 FS $10; n[k]++; u[k]+=$12; l[k]+=$13;
  rr[k]+=$14; rl[k]+=$15; sr[k]+=$16; sl[k]+=$17
} END {
  for(k in n) printf "%s,%.6f,%.3f,%.6f,%.3f,%.6f,%.3f\n",
    k,u[k]/n[k],l[k]/n[k],rr[k]/n[k],rl[k]/n[k],sr[k]/n[k],sl[k]/n[k]
}' "$output" | sort >> "$summary"

echo "$output"
echo "$summary"
