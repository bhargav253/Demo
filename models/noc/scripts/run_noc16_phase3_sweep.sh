#!/usr/bin/env bash
set -euo pipefail

noc_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
booksim="$noc_dir/booksim2/src/booksim"
topology=${NOC_TOPOLOGY:-noc16}
config="$noc_dir/configs/${topology}_pe_to_llch.cfg"
grant_policy=${NOC16_GRANT_POLICY:-rr}
out_dir=${NOC16_OUT_DIR:-$noc_dir/results/${topology}_phase3}
if [[ $topology == noc12 ]]; then node_count=368; else node_count=384; fi
mkdir -p "$out_dir"

read -r -a rates <<< "${NOC16_RATES:-0.05 0.10 0.20 0.30 0.40 0.50 0.60 0.75 1.00}"
read -r -a seeds <<< "${NOC16_SEEDS:-31 32 33 34 35}"
sample_period=${NOC16_SAMPLE_PERIOD:-300}
samples=${NOC16_SAMPLES:-3}
warmup_periods=${NOC16_WARMUP_PERIODS:-1}
telemetry_interval=${NOC16_TELEMETRY_INTERVAL:-100}

raw="$out_dir/runs.csv"
summary="$out_dir/by_rate.csv"
printf '%s\n' 'rate,seed,offered_packets_per_cycle,delivered_packets_per_cycle,acceptance_fraction,network_latency,packet_latency,hops,hot_port,hot_port_queue_wait,hot_port_residence,hot_port_throughput,hot_port_credit_stalls,hot_port_allocator_losses' > "$raw"

for rate in "${rates[@]}"; do
  for seed in "${seeds[@]}"; do
    tag="r${rate//./p}_s${seed}"
    log="$out_dir/$tag.log"
    telemetry="$out_dir/$tag.csv"
    echo "$topology phase3 grant=$grant_policy rate=$rate seed=$seed"
    set +e
    "$booksim" "$config" injection_rate="$rate" seed="$seed" \
      sim_type=throughput warmup_periods="$warmup_periods" \
      sample_period="$sample_period" max_samples="$samples" \
      noc_telemetry_interval="$telemetry_interval" \
      voq_grant_policy="$grant_policy" \
      noc_telemetry_file="$telemetry" >"$log" 2>&1
    status=$?
    set -e
    [[ $status -eq 0 || $status -eq 255 ]] || {
      echo "BookSim failed for rate=$rate seed=$seed status=$status" >&2
      exit 1
    }

    accepted=$(awk '/====== Overall Traffic Statistics ======/{p=1} p&&/Accepted packet rate average =/{print $6;exit}' "$log")
    network_latency=$(awk '/====== Overall Traffic Statistics ======/{p=1} p&&/Network latency average =/{print $5;exit}' "$log")
    packet_latency=$(awk '/====== Overall Traffic Statistics ======/{p=1} p&&/Packet latency average =/{print $5;exit}' "$log")
    hops=$(awk '/====== Overall Traffic Statistics ======/{p=1} p&&/Hops average =/{print $4;exit}' "$log")
    warmup=$(awk '/Warmed up ...Time used is/{print $6;exit}' "$log")
    [[ -n $warmup ]] || warmup=$((warmup_periods * sample_period))
    measurement_end=$((warmup + sample_period * samples))

    hot=$(awk -F, -v begin="$warmup" -v end="$measurement_end" '
      NR>1 && $2=="port" && $1>begin && $1<=end {
        k=$4 ".p" $5
        qs[k]+=$14; qc[k]+=$15; rs[k]+=$16; rc[k]+=$17
        dep[k]+=$7; stalls[k]+=$13; losses[k]+=$11
      }
      END {
        best=""; bestq=-1
        for(k in qs) if(qs[k]>0 && qc[k]/qs[k]>bestq) {
          best=k; bestq=qc[k]/qs[k]
        }
        if(best=="") print "none,0,0,0,0,0"
        else printf "%s,%.6f,%.6f,%.6f,%d,%d\n", best,bestq,
          rs[best]?rc[best]/rs[best]:0,dep[best]/(end-begin),
          stalls[best],losses[best]
      }
    ' "$telemetry")

    awk -v r="$rate" -v s="$seed" -v a="$accepted" -v nl="$network_latency" -v nodes="$node_count" \
        -v pl="$packet_latency" -v h="$hops" -v hot="$hot" '
      BEGIN {
        offered=64*r; delivered=nodes*a
        printf "%.6f,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%s\n",
          r,s,offered,delivered,offered?delivered/offered:0,nl,pl,h,hot
      }
    ' >> "$raw"
  done
done

awk -F, '
  NR>1 {
    r=$1; n[r]++; delivered[r]+=$4; accept[r]+=$5; latency[r]+=$6
    packet[r]+=$7; qwait[r]+=$10
    if(!(r in min_delivered)||$4<min_delivered[r])min_delivered[r]=$4
    if(!(r in max_delivered)||$4>max_delivered[r])max_delivered[r]=$4
    if(!(r in min_latency)||$6<min_latency[r])min_latency[r]=$6
    if(!(r in max_latency)||$6>max_latency[r])max_latency[r]=$6
  }
  END {
    print "rate,seeds,mean_delivered,min_delivered,max_delivered,mean_acceptance_fraction,mean_network_latency,min_network_latency,max_network_latency,mean_packet_latency,mean_hot_port_queue_wait"
    for(r in n) printf "%.6f,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
      r,n[r],delivered[r]/n[r],min_delivered[r],max_delivered[r],
      accept[r]/n[r],latency[r]/n[r],min_latency[r],max_latency[r],
      packet[r]/n[r],qwait[r]/n[r]
  }
' "$raw" | { read -r header; echo "$header"; sort -t, -k1,1n; } > "$summary"

echo "wrote $raw"
echo "wrote $summary"
