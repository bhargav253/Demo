# Axon contributor map

Read `docs/development-manual.md` before editing supported RTL or tooling.
`docs/repository-layout.md` defines source ownership and the current platform map.
Do not infer architectural behavior from directory names or from a passing test.

## Where to look

- `ip/`: RTL, FuseSoC source graphs, IP-local DV and interface documentation.
- `models/`: executable architectural/performance models; not RTL signoff evidence.
- `platforms/`: integration manifests linking hardware, firmware and verification.
- `sw/`: firmware source, startup/platform support, drivers and kernels as added.
- `verification/`: shared test profiles, adapters, suite inventories and contracts.
- `prebuilt/`: intentionally retained firmware ELFs, checksums and licenses.
- `third_party/sources.lock.json`: exact external source/tool identities.
- `tools/verification/`: test generation, explicit binary import, and runtime runners.
- `tools/env/`: setup and diagnosis; tool installations are optional and untracked.
- `build/`: disposable builds; `artifacts/`: unique retained run evidence.

`platforms/core_sim/platform.json` describes the existing RV32IM RAM harness.
Orchestrator and PE tile platforms are planned, not implemented. Reuse the CPU
implementation; do not duplicate it solely because firmware roles differ.

## Commands and evidence

Use `tools/bin/fusesoc`, backed by the repository bootstrap. HDL source lists
belong only in `.core` files. See `ip/core/README.md` for tested CPU commands and
`verification/riscv_arch/README.md` for generation/import/runtime boundaries.
Run `python3 tools/checks/check_repo_policy.py` and relevant component checks.
Use `.agents/skills/axon-precheck/SKILL.md` for the required final review.
Report unrun checks and architectural limitations explicitly. Preserve test
seeds, input and executable hashes, commands, and per-run logs.

## Change boundaries

Specifications and configuration files own behavior; this file is a navigation
and workflow guide. Avoid copying architectural constants into agent instructions.
Ordinary builds/tests must not change tracked sources or prebuilt binaries.
Binary publication is a separate explicit operation after successful generation.
Preserve upstream notices and pin revisions. Do not edit generated test sources.
Do not commit or push unless the user requests it. Preserve existing user changes.
