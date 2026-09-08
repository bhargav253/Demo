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
tools/bin/fusesoc regress axon:core:riscv:0.1.0 --suite smoke
tools/bin/fusesoc regress axon:core:riscv:0.1.0 --suite health
tools/bin/fusesoc coverage axon:core:riscv:0.1.0 --suite coverage
tools/bin/fusesoc status axon:core:riscv:0.1.0
```

The health suite runs 97 jobs: lint, boot smoke, directed firmware, and the 47
instruction tests with baseline and delayed memory acceptance. Coverage uses a
separate instrumented build. Each campaign produces HTML/Markdown health reports,
JSON evidence, JUnit, and retained diagnostic artifacts. Coverage percentages
are descriptive; a selected-suite pass does not close architectural gaps.

Run/replay one member:

```bash
tools/bin/fusesoc test axon:core:riscv:0.1.0 --test act4/I-add-00 --run-mode wait3 --seed 42
tools/bin/fusesoc replay <campaign>/runs/<job>/run.json
```

See [the validation guide](../../docs/validation.md) for schema, modes, suites,
limits, coverage scope and deferred work. `validation` in `riscv.core` owns the
suite definitions; the existing firmware runner remains a compatibility path.

The standard `make sim CORE=axon:core:riscv:0.1.0` command runs the small built-in
boot/store smoke test. The firmware runner is a generic legacy
orchestrator; HDL composition remains exclusively in the `.core` file.

| FuseSoC target | Contract |
| --- | --- |
| `default` | Ordered synthesizable RTL; no DV or waivers |
| `lint` | Verilator `-Wall`, with reviewed per-file/per-signal unused-field waivers |
| `sim` | C++ RAM/ELF harness; built-in smoke when no ELF is supplied |
| `sim_fw` | Same harness, named entry point for firmware campaigns |
| `coverage` | Instrumented harness and bus observation cover bins |

For one external ELF use an absolute path:

```bash
tools/bin/fusesoc run --target sim_fw axon:core:riscv:0.1.0 --ELF=/absolute/path/test.elf
```

Firmware parameters are `ELF`, `CYCLES`, `WAIT`, `SEED`, `TEST`, and optional
`WAVE`. `WAIT=N` accepts a request once per N+1 cycles (0..1000); instruction
and data acceptance have independent phase offsets determined by `SEED`.
Responses arrive one cycle after acceptance. This is a deterministic handshake
stress test, not a randomized or arbitrary-latency memory proof.
