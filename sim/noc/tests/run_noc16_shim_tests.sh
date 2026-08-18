#!/usr/bin/env bash
set -euo pipefail

router_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
booksim="$router_dir/booksim2/src/booksim"
config="$router_dir/configs/noc16_shim_contention.cfg"
log=/tmp/noc16_shim_contention.log
set +e
"$booksim" "$config" > "$log" 2>&1
status=$?
set -e
[[ $status -eq 0 || $status -eq 255 ]]

line=$(grep 'SHIM_STATS shim=96 ' "$log")
[[ $line =~ offered_l2=([0-9]+) ]]; offered=${BASH_REMATCH[1]}
[[ $line =~ sent_l3=([0-9]+) ]]; sent=${BASH_REMATCH[1]}
[[ $line =~ contention_cycles=([0-9]+) ]]; contention=${BASH_REMATCH[1]}
[[ $line =~ lane_sends=\[([0-9]+)\;([0-9]+)\;([0-9]+)\;([0-9]+)\] ]]
lanes=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}")
(( offered > 0 && sent > 0 && contention > 0 ))
(( offered == sent ))
min=${lanes[0]}; max=${lanes[0]}
for value in "${lanes[@]}"; do
  (( value > 0 ))
  (( value < min )) && min=$value
  (( value > max )) && max=$value
done
(( max - min <= 1 ))

# Accepted rate is normalized over 384 BookSim nodes. One shim ejection per
# cycle therefore appears as approximately 1/384.
rate=$(awk '/====== Overall Traffic Statistics ======/{p=1} p && /Accepted packet rate average =/{print $6; exit}' "$log")
awk -v r="$rate" 'BEGIN { delivered=r*384; exit !(delivered > 0.99 && delivered < 1.01) }'

echo 'noc16 shim 4:1 throughput, contention, and round-robin fairness passed.'
