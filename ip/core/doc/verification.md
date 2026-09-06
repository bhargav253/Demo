# RV32IM bring-up verification handoff

Precheck status: **ready-with-notes** for RTL methodology integration and the
I/M instruction-test milestone. Full architectural certification is not ready;
known inherited trap/CSR/privilege gaps are listed in [riscv.md](riscv.md).
No claim of processor formal proof is made.

Base: `env-dev` commit `9a9a571`; working branch: `riscv`.
Host: Python 3.12.3, Verilator 5.020, GCC/G++ 13.3.0.

| Check | Result |
| --- | --- |
| Repository bootstrap and doctor | PASS; formal tools optional and not installed in this clone |
| `make lint CORE=axon:core:riscv:0.1.0` | PASS, strict lint plus scoped unused-field waivers |
| `python3 tools/checks/check_repo_policy.py` | PASS, 11 controlled files, zero findings |
| `git diff --check` | PASS |
| `make sim CORE=axon:core:riscv:0.1.0` | PASS, built-in smoke, seed 1 |
| Directed ELF, `--wait 3 --waves` | PASS, seed 1; FST retained |
| Official ACT4 I/M, wait 0, seed 1 | 47/47 PASS |
| Official ACT4 I/M, wait 3, seed 42 | 47/47 PASS |
| Negative harness campaign | Explicit status=3, timeout, truncated ELF, wrong class, invalid entry all rejected |

Commands for repeating the firmware campaigns are in [the core guide](../README.md).
The corresponding retained evidence in this checkout is under
`artifacts/axon_core_riscv_0.1.0/firmware/`:

- `run-3_0wluuh/results.json`: official suite, wait 0, seed 1, 1,000,000-cycle limit.
- `run-xhzwwqec/results.json`: official suite, wait 3, seed 42, 2,000,000-cycle limit.
- `run-4o_3030v/results.json`: directed ELF and waves, wait 3, seed 1.
- `run-1fg3nqx8/results.json`: five intentional negative cases, 100-cycle limit;
  each simulator returned nonzero. Explicit failing firmware wrote status 3 at cycle 7.

Build artifacts and operational evidence are intentionally ignored. Each report
records source revision/dirty status, executable and ELF hashes, exact command,
seed, acceptance delay, cycle limit, and each simulator exit status. ELF and
platform hashes are also recorded in the tracked manifests.

Reviewed source scope: all ten core RTL files, `riscv.core`, narrow lint waivers,
the C++ ELF/bus harness, generic firmware runner, directed firmware/linker,
architectural platform configuration/linker/macros, binary manifests/licenses,
core documentation, and methodology/catalog additions. Generation completed in
the separate workspace; no ACT4 upstream source changes were needed.

Remaining validation: arbitrary memory response latency/reordering, reset during
in-flight work, interrupts, unsupported/reserved instruction traps, privileged
CSR behavior, processor formal properties, and measured RTL coverage. The
reference/model configuration is an intended I/M testing contract and is not
proof of conformance of the old machine-mode implementation.

## Monorepo reorganization verification

The generator and runner now live under `tools/verification`; firmware source is
under `sw`; ACT configuration is under `verification/riscv_arch`; retained ELFs
are under `prebuilt`. CPU RTL and its FuseSoC graph were unchanged by this move.

- Optional generation setup replay and tool/source version check: PASS against
  the existing external environment. A second completely fresh tool installation
  was not repeated; pinned binary provisioning supports Linux x86-64 only.
- Tracked generator: PASS, 47 ELFs from an isolated configuration snapshot.
- Explicit publication: PASS with validated receipt, configuration and ELF hashes.
- Altered ELF/config receipt checks: both rejected before changing the manifest.
- Current suite: 47/47 PASS, `run-htcyd66x/results.json` (wait 0, seed 1).
- Backpressure suite: 47/47 PASS, `run-b2fa8k4p/results.json` (wait 3, seed 42).
- Firmware smoke: PASS, `run-v4da8y48/results.json`.
- Policy, diff whitespace and strict lint: PASS.

All firmware report names above are relative to the same artifact directory as
the earlier evidence. The new generation receipt is retained in the external
workspace, and its hash is included in the published manifest.

BookSim moved from sim/noc to models/noc: all 208 originally tracked model files
are byte-for-byte unchanged. `make -C models/noc test` passed all eight router
checks after relocation. No topology behavior was changed, so the additional
NoC12/16/16C campaigns were not repeated for this path-only move.
