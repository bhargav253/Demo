#!/usr/bin/env bash
set -euo pipefail

noc_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
comparison="$noc_dir/results/noc12_grant_comparison"
rr="$comparison/rr"
weighted="$comparison/weighted"

NOC_TOPOLOGY=noc12 NOC16_GRANT_POLICY=rr NOC16_OUT_DIR="$rr" \
  "$noc_dir/scripts/run_noc16_phase3_sweep.sh"
NOC_TOPOLOGY=noc12 NOC16_GRANT_POLICY=weighted NOC16_OUT_DIR="$weighted" \
  "$noc_dir/scripts/run_noc16_phase3_sweep.sh"
python3 "$noc_dir/scripts/compare_noc16_grants.py" \
  "$rr" "$weighted" "$comparison" 12

echo "wrote $comparison/by_rate.csv"
echo "wrote $comparison/delta_by_rate.csv"
