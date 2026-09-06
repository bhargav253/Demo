# RISC-V architectural-test integration

The current collection is `suite.json`: 39 I and 8 M binaries for `core_sim`.
The configuration is an intended instruction-test contract; legacy privileged,
illegal-instruction and misalignment gaps remain documented in `ip/core/doc/riscv.md`.
Custom PE operations require their own specifications/models/tests. Future CPU
roles should reuse this generator, with explicit suite/platform configurations.

## Normal regression: no generation tools

From the repository root:

```bash
python3 tools/verification/run_firmware.py \
  --manifest prebuilt/riscv_arch/rv32im/core_sim/manifest.json --jobs 4
```

The manifest validates the platform inputs and binaries. Results go into a unique
`artifacts/` directory. CPU HDL comes only from its FuseSoC graph.

## Optional external tool environment

The setup recipe, source revision, and tool versions are tracked. Installations
stay outside the checkout. The current setup supports Linux x86-64 and Python
3.12+ (safe tar extraction uses the standard library data filter).

```bash
python3 tools/env/riscv_testgen.py --workspace /absolute/path/to/testgen
python3 tools/env/riscv_testgen.py --workspace /absolute/path/to/testgen --check
```

This installs pinned GCC, Sail, Ruby/Bundler and uv in that workspace and uses
the pinned ACT4 Python/Ruby locks. No system package manager or shell activation
is needed. Generation subprocesses receive explicit workspace-local paths and
cache settings. --check verifies tool versions and a clean pinned upstream tree.
Existing upstream changes are never reset automatically.

## Generate without modifying tracked source

```bash
python3 tools/verification/riscv_arch.py generate \
  --workspace /absolute/path/to/testgen --jobs 4
```

Each invocation snapshots the configuration into its own external run directory,
runs ACT4, verifies the exact reviewed test inventory, and writes a successful
`receipt.json` only after generation succeeds. The receipt records tool versions,
dependency lock, input hashes, command, generator hash and generated ELF hashes.
A failed generation cannot be imported as successful. Upstream generated assembly
is used as pinned; this recipe does not hand-edit it or regenerate the test plans.

## Explicitly publish a successful generation

```bash
python3 tools/verification/riscv_arch.py publish \
  --receipt /absolute/path/to/testgen/runs/<run>/receipt.json
```

Publication verifies the receipt against current suite/configuration/tool-lock
inputs and every ELF before staging changes. It then replaces binaries and writes
the manifest last. Run only one publication at a time; this is an explicit source
mutation, not part of normal regression. Re-run regression after publication.
Licenses are retained alongside the binaries; a new suite integration must add
its required notices before publication.

The suite's `config` and `destination` paths are repository-relative. To add a
platform/profile, create its reviewed configuration and inventory, then select
it with `--suite path/to/suite.json`. Installed generation tools are shared.
Neither another RISC-V firmware role nor another memory map requires duplicating
CPU RTL or the ACT4 checkout. Binary reuse additionally requires a compatible
ISA, memory/boot contract and completion interface.
