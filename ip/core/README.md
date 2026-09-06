# RV32IM core

Ultra-Embedded v0.9-derived, locally maintained processor. The imported RTL
advertises RV32IM. The current verification milestone is a pass of the **47
ACT4 RV32 I/M instruction tests**, not complete architectural certification.
See [the integration and verification notes](doc/riscv.md) for limitations.

The `riscv` branch starts at `env-dev` commit `9a9a571`. It uses the repository's
FuseSoC/Edalize sources and bootstrap. No generator/compiler installation is
needed to execute the supplied ELF tests.

```bash
python3 tools/env/bootstrap.py
tools/bin/fusesoc run --target lint axon:core:riscv:0.1.0
tools/bin/fusesoc run --target sim axon:core:riscv:0.1.0

# Directed firmware and the official I/M collection; build once per campaign.
python3 tools/verification/run_firmware.py --manifest prebuilt/firmware/core_smoke/manifest.json
python3 tools/verification/run_firmware.py --manifest prebuilt/riscv_arch/rv32im/core_sim/manifest.json --jobs 4

# Repeat with deterministic instruction/data acceptance delays.
python3 tools/verification/run_firmware.py --manifest prebuilt/riscv_arch/rv32im/core_sim/manifest.json \
  --jobs 4 --wait 3 --seed 42 --cycles 2000000
```

`--waves` records FST files. Each invocation creates a unique campaign under
`artifacts/axon_core_riscv_0.1.0/firmware/`, containing a build log, executable
snapshot, input ELF snapshots, per-test logs, commands, hashes, and results JSON.
Any failed test, invalid ELF, checksum/configuration mismatch, or timeout returns
nonzero. These snapshots keep a concurrent later build from changing a run.

The standard `make sim CORE=axon:core:riscv:0.1.0` command runs the small built-in
boot/store smoke test. The firmware runner is a generic temporary Stage 1
orchestrator; HDL composition remains exclusively in the `.core` file.

| FuseSoC target | Contract |
| --- | --- |
| `default` | Ordered synthesizable RTL; no DV or waivers |
| `lint` | Verilator `-Wall`, with reviewed per-file/per-signal unused-field waivers |
| `sim` | C++ RAM/ELF harness; built-in smoke when no ELF is supplied |
| `sim_fw` | Same harness, named entry point for firmware campaigns |

For one external ELF use an absolute path:

```bash
tools/bin/fusesoc run --target sim_fw axon:core:riscv:0.1.0 --ELF=/absolute/path/test.elf
```

Firmware parameters are `ELF`, `CYCLES`, `WAIT`, `SEED`, `TEST`, and optional
`WAVE`. `WAIT=N` accepts a request once per N+1 cycles (0..1000); instruction
and data acceptance have independent phase offsets determined by `SEED`.
Responses arrive one cycle after acceptance. This is a deterministic handshake
stress test, not a randomized or arbitrary-latency memory proof.
