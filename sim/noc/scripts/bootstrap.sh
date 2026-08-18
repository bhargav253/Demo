#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
noc_dir="$(cd "${script_dir}/.." && pwd)"
booksim_dir="${noc_dir}/booksim2"
booksim_revision="$(tr -d '[:space:]' < "${noc_dir}/BOOKSIM_REVISION")"

for tool in make g++ flex bison; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "Missing required tool: ${tool}" >&2
        echo "On Debian/Ubuntu, install prerequisites with:" >&2
        echo "  sudo apt install build-essential flex bison" >&2
        exit 1
    fi
done

if [[ ! -f "${booksim_dir}/src/Makefile" ]]; then
    echo "Missing vendored BookSim source: ${booksim_dir}" >&2
    exit 1
fi

echo "Building vendored BookSim (upstream base ${booksim_revision})"
make -C "${booksim_dir}/src" -j"$(nproc)"

echo
echo "BookSim is ready: ${booksim_dir}/src/booksim"
