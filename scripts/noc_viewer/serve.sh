#!/usr/bin/env bash
set -euo pipefail
viewer_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
demo_dir=$(cd "$viewer_dir/../.." && pwd)
echo "Open http://127.0.0.1:8000/scripts/noc_viewer/"
python3 -m http.server 8000 --directory "$demo_dir"
