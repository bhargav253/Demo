#!/usr/bin/env bash
# Compatibility wrapper. The supported entry point is `make bootstrap`.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON:-python3}" "$repo_root/tools/env/bootstrap.py"
