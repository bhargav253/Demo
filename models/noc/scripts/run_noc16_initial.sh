#!/usr/bin/env bash
set -euo pipefail

router_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
config="$router_dir/configs/noc16_pe_to_llch.cfg"
output="$router_dir/results/noc16_initial_summary.csv"
mkdir -p "$router_dir/results"
printf 'case,injection_per_pe,offered_packets_per_cycle,delivered_packets_per_cycle,network_latency,hops\n' > "$output"

run_case() {
  local name=$1 rate=$2 mode=$3
  local log="$router_dir/results/noc16_${name}.log"
  local telemetry="$router_dir/results/noc16_${name}_telemetry.csv"
  set +e
  "$booksim" "$config" injection_rate="$rate" sim_type="$mode" \
    sample_period=500 max_samples=3 noc_telemetry_file="$telemetry" > "$log" 2>&1
  local status=$?
  set -e
  [[ $status -eq 0 || $status -eq 255 ]]
  local accepted latency hops
  accepted=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Accepted packet rate average =/{print $6; exit}' "$log")
  latency=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Network latency average =/{print $5; exit}' "$log")
  hops=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Hops average =/{print $4; exit}' "$log")
  awk -v n="$name" -v r="$rate" -v a="$accepted" -v l="$latency" -v h="$hops" \
    'BEGIN{printf "%s,%.6f,%.6f,%.6f,%.6f,%.6f\n",n,r,64*r,384*a,l,h}' >> "$output"
}

run_case low 0.10 latency
run_case saturation 1.0 throughput
echo "wrote $output"
