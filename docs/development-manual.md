# Axon hardware development manual

## Purpose

This manual defines how hardware is added, built, verified, documented, and
reviewed in this repository. It is the shared operating model for designers
and AI coding agents.

The methodology is being introduced incrementally. Each command or workflow is
labeled with one of these states:

- **Available**: implemented and usable in the repository now.
- **Manual**: usable, but not automatically enforced.
- **Planned**: the intended contract; implementation is still pending.

Do not treat a planned command as working until its implementation and clean
checkout test are complete.

## Development lifecycle

Use this lifecycle for a scoped hardware task:

```text
ticket -> inspect -> plan -> approve -> implement -> verify -> review
       -> document -> commit
```

For changes to interfaces, timing, protocols, clocks/resets, address maps, or
generator schemas, obtain designer approval after planning and before
implementation. Small mechanical changes may proceed directly when the ticket
explicitly permits it.

A completed task reports:

- files changed;
- behavioral and interface decisions;
- deterministic commands run and their results;
- simulation test and seed;
- formal properties run, when applicable;
- generated and documentation products updated;
- remaining limitations or unverified behavior.

## Repository organization

The intended organization is:

```text
ip/
  prim/                 reusable hardware primitives
  bus/                  APB, AXI-Lite, and protocol adapters
  noc/                  NoC allocators, queues, credits, routers, and shims
  core/                 processor cores
  dma/                  DMA engines
  pe/                   processing-element and systolic datapaths
  soc/                  SoC-level composition

scripts/
  regtool/              register-description and top-generation tools
  fusesoc/              local FuseSoC starting point
  edalize/              local Edalize starting point

tools/
  checks/               deterministic repository-policy checks

.agents/
  skills/               repository-local AI workflows

docs/                   tracked project and development documentation
plan/                   private, ignored working notes and experiments
build/                  generated build artifacts; not source
```

Do not edit files under `build/`. Do not hand-edit generated RTL. Change its
schema, generator, or template and regenerate it.

Files retained solely as historical reference may use
`axon-policy-allow: legacy-file` only when they are placed under an explicit
`legacy/` directory, excluded from supported build targets, and documented
with the reason they cannot yet satisfy the policy. New or supported RTL and
DV must not use this escape hatch.

## Environment setup status

A portable repository-wide bootstrap is **Planned**, not currently available.
The eventual supported setup will provide:

```text
make doctor       inspect dependencies without modifying the machine
make bootstrap    create/install the pinned project environment
make cores        confirm FuseSoC can discover the repository cores
```

Until that work is complete, be aware of these existing limitations:

- `scripts_setup.sh` requires a hard-coded `python3.10` executable;
- the root Makefile refers to a missing `path_setup.sh`;
- the current FuseSoC configuration contains machine-specific paths;
- the checked-in FuseSoC/Edalize copies are local development starting points,
  not yet exposed through a clean reproducible bootstrap;
- Verilator, Yosys/SymbiYosys, UVM, Draw.io export, and pre-commit versions are
  not yet pinned as one supported tool matrix.

Do not add a second ad-hoc setup path to work around these limitations. Repair
the common bootstrap as part of the Stage 1 environment work. The customized
BookSim flow under `sim/noc` remains a separate documented simulator workflow.

## Source categories

Treat significant files as one of:

- **Project source**: handwritten and maintained as Axon code.
- **Derived source**: imported code that is now intentionally maintained here.
- **Generated source**: reproducible output of a schema/template/tool.
- **Vendored source**: captured external implementation intentionally kept as
  a dependency, such as BookSim.
- **Prototype**: incomplete or exploratory code without a support claim.
- **Artifact**: build output, log, wave, coverage, or generated comparison.

Preserve applicable copyright, license, and SPDX notices on derived files.
BookSim keeps its explicit upstream revision record. Other locally maintained
tool and RTL starting points are expected to diverge without an upstream-sync
policy.

## RTL coding rules

### Language and formatting

- Use synthesizable SystemVerilog (`.sv`) for RTL and packages.
- Use `.svh` only for content intended to be included.
- Match the primary module or package name to the filename.
- Use ANSI-style module declarations.
- Use two-space indentation and no tabs.
- As a readability preference, align the direction, type/range, and identifier
  columns within a port or declaration group. This is advisory and is not a
  pre-commit requirement; avoid large whitespace-only churn in unrelated RTL.
- Prefer one primary reusable module per file.
- Use `logic` unless a net type is specifically required.
- Declare port and parameter types explicitly.

### Naming

- Module, package, signal, instance, and generate names use lower snake case.
- Primitive modules use `prim_`; NoC modules use `noc_`.
- Inputs end in `_i`, outputs in `_o`, and bidirectional ports in `_io`.
- Active-low signals end in `_n`; the normal reset is `rst_ni`.
- Registered/current state ends in `_q`; combinational next state ends in `_d`.
- Instances begin with `u_`; generate blocks begin with `gen_`.
- Packages end in `_pkg`.
- Public parameters and local parameters use UpperCamelCase.
- Assertion names end in `_A`, formal assumptions in `_M`, and covers in `_C`.

Example:

```systemverilog
module noc_example #(
  parameter int unsigned NumPorts = 8,
  parameter int unsigned DataWidth = 32,
  parameter bit EnableBypass = 1'b0,
  localparam int unsigned PortWidth = prim_util_pkg::vbits(NumPorts)
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic [DataWidth-1:0] data_i,
  input  logic                 valid_i,
  output logic                 ready_o,
  output logic [DataWidth-1:0] data_o
);
```

Preferred declaration alignment:

```systemverilog
input  logic                    clk_i;
input  logic [DataWidth-1:0]    data_i;
output logic                    ready_o;
output logic [DataWidth-1:0]    data_o;
```

### Width and signedness

- Use explicit packed widths.
- Make signedness explicit at arithmetic and comparison boundaries.
- Use `'0` or `'1` when the entire destination width is intended.
- Use sized literals or explicit casts when inference could truncate, extend,
  or change signedness.
- Use `prim_util_pkg::vbits()` when a one-entry structure still needs a one-bit
  index.
- Add elaboration checks for illegal parameters and parameter combinations.

### Combinational logic

- Use `always_comb`, continuous assignments, or functions.
- Give every procedurally assigned output/next-state value a default before
  conditional overrides.
- Use blocking assignments in combinational blocks.
- Avoid unintended latches and combinational ready/valid loops.
- Parenthesize mixed Boolean expressions when precedence is not immediately
  clear.

### Sequential logic and reset

Axon uses synchronous, active-low reset:

```systemverilog
always_ff @(posedge clk_i) begin
  if (!rst_ni) begin
    state_q <= ResetValue;
  end else begin
    state_q <= state_d;
  end
end
```

- Do not put reset in the event control.
- Use nonblocking assignments for sequential state.
- Reset control and architecturally visible state.
- Large data arrays may remain unreset when valid state prevents stale data
  from becoming externally visible. Document this choice.
- Each clock domain receives a reset synchronous to that domain.
- Do not create derived clocks in ordinary RTL. Use clock enables or a reviewed
  clock-gating primitive.

### Handshakes and arbitration

For ready/valid interfaces, transfer occurs only when both are asserted:

```systemverilog
logic handshake;
assign handshake = valid_i && ready_o;
```

- Update transaction state only on the documented transfer/commit event.
- Hold valid and payload stable during backpressure when the interface requires
  it.
- Document whether backpressure propagates combinationally.
- Define reset, flush, cancellation, and error behavior for buffered paths.
- Advance round-robin/fairness state on an accepted operation, not merely a
  request or unaccepted grant.

### Instances and generate blocks

- Use named parameter and port connections.
- Shorthand such as `.clk_i` is allowed when names intentionally match.
- Show intentionally unused outputs as `.unused_o()`.
- Name every generate block.
- Prefer SystemVerilog generate constructs over preprocessor-selected hardware.

## Assertions and coverage

Use the project assertion wrappers rather than tool-specific assertion code in
functional RTL.

The intended policy is:

- supported assertions execute in Verilator simulation;
- portable assertions map into formal verification;
- unsupported temporal constructs receive an explicit portable or
  tool-specific implementation;
- assertions are never silently disabled merely to make a target pass.

This policy is **Planned**. The imported wrapper currently disables assertions
under Verilator and will be corrected after the assertion compatibility test.

Use:

- `ASSERT_INIT` for parameter legality;
- `ASSERT`/`ASSERT_NEVER` for local protocol and state invariants;
- `ASSERT_KNOWN` for post-reset control outputs;
- `ASSERT_KNOWN_IF` for payload knownness when valid;
- `ASSUME_FPV` only for formal environment constraints;
- `COVER`/`COVER_FPV` to demonstrate useful reachability.

OpenTitan security-alert, redundant fault-injection, and sparse-FSM assertion
infrastructure is outside the Axon methodology and will be removed. Ordinary
functional assertions and formal checking remain required.

## FuseSoC model

FuseSoC is the authoritative source-composition and dependency layer. Root
Make targets will provide stable user-facing orchestration without duplicating
source lists.

### Core identities

Use complete identifiers:

```text
axon:<library>:<name>:<version>
```

Examples:

```text
axon:prim:fifo:0.1.0
axon:lint:common:0.1.0
axon:noc:islip_arbiter:0.1.0
axon:bus:components:0.1.0
axon:pe:syst:0.1.0
```

### Filesets

Separate files by purpose:

```text
rtl
assertions
dv
formal
verilator_waivers
constraints
generated
```

Rules:

- Preserve source ordering.
- Express reusable dependencies by VLNV.
- Keep `default` synthesizable and reusable.
- Do not leak testbench/formal files into downstream RTL dependencies.
- Attach lint waivers only to targets that need them.
- Declare generated products explicitly; do not glob arbitrary build trees.

### Standard targets

The target contract is **Planned**:

| Target | Meaning |
|---|---|
| `default` | Reusable synthesizable RTL |
| `lint` | Verilator lint for a meaningful module or family |
| `sim` | Default unit simulation environment |
| `formal` | Default unit formal harness |
| `elaborate` | Integration elaboration without simulation |
| `synth` | Synthesis target when introduced |
| `fpga_build` | Reproducible FPGA implementation target |

A core family may expose qualified targets such as `lint_sync` and
`lint_async`; private helper modules do not need individual targets.

New Axon RTL starts without broad warning suppression. Existing imported
waivers may remain while components are normalized. Every new waiver must be
narrow and justified.

## Verification strategy

Use the smallest environment that provides convincing evidence.

| Level | Default approach |
|---|---|
| Primitive | Direct self-checking SV testbench, assertions, formal where useful |
| Simple bus/NoC component | Direct SV testbench and protocol assertions |
| IP block | UVM environment with reusable agents and scoreboards |
| Subsystem | UVM, reusable protocol agents, coverage, DPI traffic where useful |
| SoC | System UVM harness, software tests, external traffic/workload models |

UVM with Verilator is the intended block/subsystem methodology. Do not force a
small counter, FIFO, slice, or arbiter into a large UVM environment solely for
uniformity.

### Unit testbench requirements

A unit testbench should:

- be self-checking;
- terminate with nonzero status on failure;
- use deterministic stimulus by default;
- record any random seed;
- check reset and parameter boundaries;
- test backpressure and simultaneous operations;
- compare externally visible behavior through a scoreboard or reference model;
- retain an FST wave and useful transaction log on failure when supported;
- avoid depending on internal DUT implementation unless the test is explicitly
  microarchitectural.

### UVM requirements

The reusable UVM framework is **Planned**. It will establish:

- transaction, sequencer, driver, monitor, agent, and scoreboard structure;
- configuration and factory conventions;
- objection/end-of-test behavior;
- constrained-random and directed sequence conventions;
- functional coverage tied to a verification plan;
- deterministic seed replay;
- failure artifact and reporting conventions;
- DPI integration for external traffic generators.

Existing DMA cocotb tests are not the target methodology and may be removed as
the DMA is reworked.

### DPI traffic

The DPI bridge is **Planned**. External traffic generators should communicate
through a versioned transaction representation with explicit ownership,
backpressure, reset, end-of-stream, and error semantics. Support deterministic
record/replay so an RTL failure can be reproduced without rerunning the
architectural model.

Prefer explicit DPI arguments over arbitrary VPI access into DUT signals.
Batch transactions where measurements show that per-call overhead matters.

### Formal verification

Formal verification is used selectively for bounded control and conservation
properties such as:

- grant/accept mutual exclusion;
- grant requires request;
- FIFO occupancy bounds and ordering;
- no loss or duplication;
- credit conservation;
- legal state transitions;
- bounded fairness under documented assumptions.

Formal flow integration is **Planned**. Assertions shared with simulation use
the portable wrapper subset. Tool-specific properties remain clearly labeled.
Every formal result records assumptions, property set, engine/target, and
whether the result was prove, bounded pass, cover, fail, or inconclusive.

## Adding a new IP or component

Use this sequence:

1. Define purpose, non-goals, interfaces, timing, reset, parameters, and
   invariants.
2. Decide its location and Axon VLNV.
3. Create RTL and documentation skeletons.
4. Create the reusable FuseSoC `default` fileset/target.
5. Add lint coverage.
6. Add the smallest suitable self-checking test environment.
7. Add local protocol/state assertions.
8. Add formal properties where they provide useful proof.
9. Run the component checks.
10. Update diagram and microarchitecture documentation.
11. Run `$axon-precheck` and address blocking findings.
12. Commit only task-scoped files after required gates pass.

The first methodology pilot is the iSLIP arbiter under `ip/noc`. The second is
the existing systolic logic under `ip/pe`.

## Adding a unit testbench to an existing IP

1. Read the RTL, core file, specification, and known limitations.
2. Write a verification matrix mapping behaviors and invariants to tests and
   assertions.
3. Separate DUT RTL, assertions, testbench, and formal filesets.
4. Add or repair the FuseSoC `sim` target.
5. Implement deterministic reset and directed corner cases first.
6. Add a scoreboard/reference model.
7. Add constrained-random stimulus only when it improves coverage.
8. Record seeds and provide an exact rerun command.
9. Demonstrate that an intentional failure returns nonzero.
10. Run lint, simulation, applicable formal checks, and `$axon-precheck`.

## Documentation model

Draw.io (`.drawio`) is the editable source of truth for block diagrams. PNG is
the default rendered image embedded in Markdown.

```text
ip/<area>/doc/
  <area>.drawio
  <block>_overview.png
  <block>.md
```

One Draw.io file may contain multiple named pages for a related IP area. Never
edit an exported PNG independently of its Draw.io source.

Nontrivial block documentation should cover:

```text
purpose
parameters
interfaces
clock and reset
microarchitecture
operation and timing
backpressure/arbitration/ordering
assertions and invariants
FuseSoC targets
limitations and deferred work
```

Tiny primitives and simple bus helpers may use module-header documentation or
shared area-level documentation.

## Generated registers and subsystem composition

Register descriptions and subsystem descriptions are separate schemas sharing
explicit typed metadata.

Register descriptions own:

- registers and fields;
- access behavior;
- reset values;
- register address layout;
- register RTL/package, documentation, headers, and optional verification
  model.

Subsystem descriptions own:

- instances and parameters;
- clocks and resets;
- typed interfaces and connections;
- address regions;
- interrupts and events;
- memories and interconnect endpoints;
- generated composition collateral.

Generated products must be deterministic and eventually support a check mode
that fails when checked-in output is stale.

## Deterministic repository policy check

**Available, manual:**

```bash
python3 tools/checks/check_repo_policy.py
```

Check selected files:

```bash
python3 tools/checks/check_repo_policy.py \
  ip/noc/rtl/noc_islip_arbiter.sv \
  ip/noc/noc_islip.core
```

Audit the complete existing tree without returning failure:

```bash
python3 tools/checks/check_repo_policy.py --all --warn-only
```

The checker currently enforces mechanically recognizable rules including
whitespace, synchronous reset event control, modern procedural block usage,
module/filename matching, parameter naming, complete Axon VLNVs, and removal
of legacy `lowrisc:*` dependencies.

The pre-commit hook is intentionally disabled for normal commits while legacy
RTL is normalized. It is configured for the manual stage:

```bash
pre-commit run axon-repo-policy --hook-stage manual --all-files
```

After the existing baseline is clean, change its configured stage from
`manual` to `pre-commit` and install it with `pre-commit install`.

## AI-assisted precheck

**Available:** the repository-local skill is stored at:

```text
.agents/skills/axon-precheck/
```

Codex users can invoke it from the repository:

```text
$axon-precheck Review my current hardware changes before commit.
```

The skill runs deterministic evidence first and then reviews semantics,
verification adequacy, FuseSoC integration, generation, documentation, and
change hygiene. It is explicit-only and does not run from the Git hook.

The AI review is judgment and guidance. Deterministic lint, simulation, formal,
and generated-file failures remain authoritative.

## Planned command surface

The stable root command surface will be implemented and tested during the
FuseSoC vertical slice:

```text
make doctor
make lint CORE=<vlnv>
make sim CORE=<vlnv> TEST=<name> SEED=<seed>
make formal CORE=<vlnv>
make check-ip CORE=<vlnv>
make check-fast
make check
```

Expected meanings:

- `doctor`: report tool versions and actionable missing dependencies without
  modifying the machine;
- `lint`: run the selected meaningful RTL lint target;
- `sim`: run a named reproducible simulation;
- `formal`: run a named formal property set;
- `check-ip`: execute the required gates for one IP;
- `check-fast`: deterministic pre-commit subset;
- `check`: complete normal review/CI gate.

Long regressions, synthesis, FPGA builds, and NoC performance sweeps remain
separate from the default fast gate.

## Artifact model

The normalized artifact layout is **Planned**:

```text
build/<core>/<target>/<run-id>/
  run.json
  build.log
  simulation.log
  results.xml
  metrics.json
  waves.fst
```

`run.json` should record repository revision and dirty state, core/target,
tool versions, command, parameters, test, seed, status, and rerun command.
Passing runs may retain compact summaries; failures retain actionable logs and
waves.

## Commit and review policy

- Local deterministic hooks are convenience; CI will eventually be the
  authoritative merge gate.
- AI review is invoked explicitly and is not part of pre-commit.
- Do not weaken a lint, simulation, formal, or generator gate to obtain a pass.
- Do not include unrelated user changes in a task commit.
- Do not commit unless the task/user authorizes it.
- Report checks not run and why; absence of a tool is not a passing result.
- A review may legitimately contain no findings.

The current methodology is proven only when a second component can use the
same commands, target semantics, artifacts, and review flow without special
root-level changes.
