# RISC-V integration and verification

## Implementation and migration

The source headers identify Ultra-Embedded RISC-V Core v0.9 (2014–2018), under
BSD-3-Clause. The precise upstream revision and historical ISA/privileged spec
revision are unknown. Original copyright and license text remains in the RTL.
The decoder contains the RV32 integer instructions and all eight M operations;
`misa` reports RV32IM. There is no compressed, atomic, or floating-point datapath.

Migration replaces macro includes with a typed `riscv_defs_pkg`, changes internal
net declaration assignments into explicit continuous assignments, uses `logic`,
`always_comb`, and `always_ff`, and normalizes module ports and next-state names.
Reset is now synchronous active-low `rst_ni` throughout; the old `rst_i` interface
was synchronous active-high. All consumers in the core hierarchy were updated.
The testbench asserts reset for five edges and starts execution at the ELF entry.
Legacy debug backdoors and in-RTL `$finish`/console behavior were removed: only
an accepted platform store can report test success. Functional pipeline and bus
behavior, including known architectural gaps, otherwise remains the baseline.
Unused legacy internal interface fields have narrow documented Verilator waivers.
There is no blanket warning or width suppression.

## Interfaces and microarchitecture

`riscv_core` connects fetch, scoreboard/decode and register file, execution/ALU,
load/store, multiply/divide, and CSR blocks. Decode stalls for unavailable source
registers and execution-unit backpressure. Separate unit writeback paths retire
results into the register file. Multiplication and iterative division use their
original execution units. The register file has 32 architectural names with x0
hardwired to zero, and four prioritized writeback inputs.

The top uses separate native instruction and data memory interfaces, not AXI or
TileLink. Instruction requests carry a PC; responses return instruction, matching
PC, valid and error. Data requests carry aligned word address, write byte enables,
write data, cache controls, and an 11-bit response tag. The adapter echoes tags
unchanged on completion. The tag encodes destination register and load size/sign
information. **Data read/write strobes are gated by `mem_d_accept_i` in the old
LSU. The responder must offer acceptance independently of seeing a strobe.**
The C++ harness does this and snapshots accepted requests before the rising edge.
This interface should not be connected to a generic ready/valid adapter without
accounting for that contract.

`reset_vector_i` supplies boot PC, `cpu_id_i` supplies hart ID, and `intr_i` is the
legacy external interrupt input. The harness sets hart ID and interrupt to zero.
Cache flush/invalidate requests are acknowledged as no-ops in the uncached RAM
platform. No memory response reordering, MMU, caches, or SoC bus is modeled.

## Firmware platform

| Region | Address / behavior |
| --- | --- |
| RAM | `0x80000000` through `0x800fffff` (1 MiB), little endian |
| Reset | ELF `e_entry`, aligned to four bytes and in executable RAM |
| Exit | Word store to `0x10000000`: 1 means pass; any other value means fail |
| Console | Low-byte write to `0x10000004` |

The ELF loader checks class, endianness, machine, type, header bounds, segment
bounds and executable entry point. It loads PT_LOAD segments at physical
addresses, requires matching virtual addresses, and zeros their BSS tails.
Out-of-map bus accesses return errors. The legacy LSU masks low address bits,
so this harness cannot retrofit correct misaligned architectural traps.

ACT's alignment macros mark ELF files with EF_RISCV_RVC even in I/M tests. That
flag alone is not evidence of executed compressed instructions, and is therefore
not used as an ELF rejection rule. The hardware still does not implement C.

`sw/platforms/core_sim/link.ld` and `sw/tests/core_smoke.S` define the small bring-up program. `verification/riscv_arch/configs/rv32im_core_sim`
owns the ACT linker, platform macros, UDB contract, and Sail configuration. The
linker places `.text.rvmodel` after data as ACT requires. Test-generation tools
and intermediates stay in a separate folder; generated ELFs and provenance are
intentionally version-controlled exceptions to the normal build-output rule.

## Architectural test generation

The imported test collection is from the official [riscv-arch-test ACT4
repository](https://github.com/riscv/riscv-arch-test). Exact source revision, tool
versions, generation command, platform input hashes, and ELF hashes are recorded
in `prebuilt/riscv_arch/rv32im/core_sim/manifest.json`. BSD, Apache and CC attribution/license files
accompany the binaries. The linker and UDB starting configuration were adapted
from ACT's Sail and Spike RVI20U32 examples; Sail configuration was derived from
the pinned model's defaults.

Generation uses Sail 0.13.1 and xPack RISC-V GCC 15.2.0-1, with ACT's locked Python
and Ruby/UDB packages, in the sibling `riscv-testgen` directory. Ruby, Bundler,
UDB (including its Z3 dependency), uv and the downloaded compiler/reference model
are generation-only dependencies. A temporary Verible formatter is also outside
the demo checkout and is not needed for builds. No system EDA package is added.

The tracked setup/generation/import recipe is documented in
`verification/riscv_arch/README.md`. It accepts an explicit external workspace;
no sibling directory name is required. Generation uses private configuration
snapshots and emits a receipt only after the reviewed inventory succeeds.
Publication is a separate operation that checks current inputs and ELF hashes.
No compiler/Sail/ACT installation is needed for runtime.

## Verification scope and known limitations

The 47 supplied tests comprise 39 I and 8 M tests. Their expected results come
from Sail and their self-checks execute on the RTL. Both immediate acceptance
and deterministic backpressure campaigns pass. This establishes the tested I/M
instruction behavior only. It is not a full ISA, privileged, interrupt, formal,
or certification claim. `include_priv_tests: false` and `--extensions I,M` are
explicit scope limits, not a way of marking omitted tests as passed.

The UDB Sm configuration provides the framework's intended machine-mode test
contract; it does **not** certify that this old implementation conforms to Sm
1.12. The platform bypasses privilege switching at boot and has empty interrupt
macros because interrupts are excluded. Do not extend this platform to privileged
or interrupt tests until those facilities have been implemented and validated.

Known inherited gaps requiring a separately reviewed architectural change:

- Invalid-instruction detection exists but is not routed into an illegal trap.
- Misaligned fetch/load/store trap sources are tied off; LSU addresses are masked.
- Machine privilege is forced each cycle; other privilege transitions are incomplete.
- CSR access legality and machine trap-value handling are incomplete.
- The old timer CSR write behavior is nonstandard; cache-control CSRs overlap
  standard PMP addresses. `misa` alone cannot identify a conforming privileged spec.
- Reserved instruction encoding checks need a dedicated audit.

No processor formal properties, RTL coverage campaign, arbitrary response-latency
stress, interrupt campaign, or complete reset-during-flight campaign was run.
The inherited NoC formal setup remains available independently.
