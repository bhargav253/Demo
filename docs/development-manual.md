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
artifacts/              reproducible logs, waves, and run manifests
.venv/                  repository-local Python tool environment
```

Do not edit files under `build/`. Do not hand-edit generated RTL. Change its
schema, generator, or template and regenerate it.

Files retained solely as historical reference may use
`axon-policy-allow: legacy-file` only when they are placed under an explicit
`legacy/` directory, excluded from supported build targets, and documented
with the reason they cannot yet satisfy the policy. New or supported RTL and
DV must not use this escape hatch.

## Environment setup

### Fresh-clone quick start

From a new checkout, run:

```bash
git clone <repository-url>
cd <repository-directory>
python3 tools/env/bootstrap.py
python3 tools/env/doctor.py
tools/bin/fusesoc core list
```

The first bootstrap needs network access to download the external Python
packages pinned in `requirements/tools.lock`. It creates `.venv` inside the
checkout and does not modify the user's global Python installation. Repository
commands locate that environment automatically, so activation is not required.

The doctor command should report all required dependencies as available. Yosys and
SymbiYosys are optional for designers who do not run formal targets. Install the
pinned repository-local bundle with `python3 tools/env/formal_setup.py`. FuseSoC core listing then confirms that the tracked configuration
can discover the repository IP. Re-running the bootstrap script is the supported
way to refresh an existing checkout after tool inputs change; it is idempotent
when the environment is already current.

The root README is the concise user entry point. This manual is the
authoritative workflow and policy reference for both designers and agents.

The portable repository-wide bootstrap is **Available**:

```text
python3 tools/env/doctor.py       inspect dependencies without modifying the machine
python3 tools/env/bootstrap.py    create or refresh the pinned local environment
tools/bin/fusesoc core list       confirm local FuseSoC can discover Axon cores
```

Axon supports Python 3.10 or newer; Python 3.12 is the currently validated
host version. The bootstrap script creates `.venv`, installs the external Python
packages pinned in `requirements/tools.lock`, and then installs
`scripts/edalize` and `scripts/fusesoc` as editable Axon-owned packages. It
does not install EDA binaries or modify global Python packages.

Users do not need to activate `.venv`. The repository launcher at
`tools/bin/fusesoc` always invokes `.venv/bin/fusesoc` with the tracked
repository configuration. Activating `.venv` remains optional for interactive
Python development.

The doctor script is read-only. It reports host Python, Git, Make, GCC/G++,
Verilator, the local package versions and source paths, and planned optional
tools. Missing Yosys or SymbiYosys is informational unless a formal target is
required.
Missing required tools or a missing/broken `.venv` returns nonzero with a
suggested next action.

The tracked `fusesoc.conf` isolates FuseSoC state inside this checkout:

```text
cores_root   = ip
build_root   = build
cache_root   = build/cache/fusesoc
library_root = build/cache/libraries
```

Machine-specific EDA installation paths belong in the user's environment or a
future explicitly designed tool adapter, not in the tracked core graph.
Ordinary core discovery and open-source lint/simulation must not require local
configuration. The customized BookSim flow under `sim/noc` remains a separate
documented simulator workflow.

Tool dependency ownership is deliberately separated:

- `requirements/tools.lock` owns external Python-package versions;
- editable `scripts/fusesoc` and `scripts/edalize` are Axon monorepo source;
- FuseSoC `.core` dependencies own HDL/IP composition;
- `tools/env/doctor.py` observes host-installed EDA binaries.

Do not install FuseSoC or Edalize independently from PyPI for repository work.
Do not add a second setup path around `tools/env/bootstrap.py`.

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

The target contract is being introduced incrementally. `default` is the
reusable RTL target on supported cores. `lint` is **Available** on meaningful
lint boundaries that expose it. `formal` and `formal_cover` are **Available**
on the iSLIP reference core; the remaining targets below are **Planned**:

| Target | Meaning |
|---|---|
| `default` | Reusable synthesizable RTL |
| `lint` | Verilator lint for a meaningful module or family |
| `sim` | Default unit simulation environment |
| `formal` | Default unit formal harness |
| `formal_cover` | Generate witnesses for formal reachability goals |
| `elaborate` | Integration elaboration without simulation |
| `synth` | Synthesis target when introduced |
| `fpga_build` | Reproducible FPGA implementation target |

A core family may expose qualified targets such as `lint_sync` and
`lint_async`; private helper modules do not need individual targets.

New Axon RTL starts without broad warning suppression. Existing imported
waivers may remain while components are normalized. Every new waiver must be
narrow and justified.

New lint targets use Edalize's Flow API rather than its deprecated Tool API:

```yaml
lint:
  filesets: [files_rtl, files_verilator_waiver]
  flow: lint
  flow_options:
    tool: verilator
    verilator_options: [-Wall]
  toplevel: example_top
```

Do not combine `lint_only: true` with a manually supplied `--lint-only` option.
The `lint` flow owns the Verilator lint mode. Tool-specific waivers or options
that are needed by a Flow API target must be declared in that target's
`flow_options`; legacy dependency tool options are not implicitly its policy.

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

Formal verification asks a mathematical solver to explore all behaviors allowed
by a model instead of executing a chosen list of test vectors. Yosys elaborates
the RTL into a formal model, SymbiYosys coordinates proof engines and result
directories, and engines such as ABC PDR or Boolector solve the resulting
problem. These tools are free and open source in the pinned OSS CAD Suite.

The three basic property roles are:

- `assert`: behavior the DUT must always satisfy;
- `assume`: legal behavior promised by the surrounding environment;
- `cover`: behavior the solver should demonstrate is reachable.

Assumptions are powerful and dangerous. Keep them at the DUT boundary, document
each one, and use cover witnesses to detect accidentally impossible models.
Never describe a bounded pass as an unbounded proof. A PDR `PASS` establishes an
invariant for all modeled cycles; a bounded-model-checking pass establishes only
that no counterexample exists up to its configured depth.

Formal is used selectively for control and conservation properties such as:

- grant/accept mutual exclusion;
- grant requires request;
- FIFO occupancy bounds and ordering;
- no loss or duplication;
- credit conservation;
- legal state transitions;
- bounded fairness under documented assumptions.

Formal complements rather than replaces simulation. It is especially effective
for arbiters, FIFOs, protocol bookkeeping, reset/state invariants, deadlock
abstractions, and corner cases that require unlikely event sequences. Simulation
remains better for software-driven scenarios, analog/timing effects, performance
measurement, large data-path reference models, and behavior that has not been
expressed as a property.

The iSLIP reference flow is **Available**. Install its pinned local tools once:

```text
python3 tools/env/formal_setup.py
python3 tools/env/doctor.py
```

Then use FuseSoC, which supplies the RTL dependency graph and formal fileset:

```text
tools/bin/fusesoc run --target formal axon:noc:islip_arbiter:0.1.0
tools/bin/fusesoc run --target formal_cover axon:noc:islip_arbiter:0.1.0
```

The `formal` target uses ABC PDR to prove, without a cycle bound, that every
match was requested, input and output matches are one-hot-or-zero, reset clears
priority state, and priority state changes only following a match. The
`formal_cover` target uses Boolector to find bounded witnesses for request
contention, simultaneous independent matches, and round-robin priority wrap.
The harness drives a synchronous reset for the first formal step and allows an
arbitrary request matrix on every later step; it makes no traffic-shape or
fairness assumption.

Results are disposable build evidence under:

```text
build/axon_noc_islip_arbiter_0.1.0/formal-symbiyosys/build/
build/axon_noc_islip_arbiter_0.1.0/formal_cover-symbiyosys/build/
```

Read `status` and the console summary first. On failure, open
`engine_0/trace.vcd` in GTKWave and inspect the reported property source line.
Cover mode may produce multiple `traceN.vcd` witnesses. A formal failure returns
nonzero, so the target can participate in a later smoke or submission gate.

Assertions shared with simulation use the portable wrapper subset when
practical. Tool-specific harness logic remains in `dv/formal`; the iSLIP RTL
exposes priority state only when `FPV_ON` is defined and uses Yosys's formal
global clock so every formal step corresponds to one synchronous design edge.
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

## Command surface

The environment and FuseSoC discovery commands are **Available**:

```text
python3 tools/env/doctor.py
python3 tools/env/bootstrap.py
tools/bin/fusesoc core list
```

Lint is **Available** for a core that exposes `lint` or a qualified `lint_*`
target:

```text
tools/bin/fusesoc run --target lint axon:noc:islip_arbiter:0.1.0
tools/bin/fusesoc run --target <lint_target> <vlnv>
```

The core must be a complete `axon:<library>:<name>:<version>` VLNV. FuseSoC is
responsible for resolving the source and dependency graph. Build products are
disposable; retained operational logs are owned by the validation layer chosen
in Stage 2.

The iSLIP unit simulations are **Available**:

```text
tools/bin/fusesoc run --target sim axon:noc:islip_arbiter:0.1.0 --TEST=smoke --SEED=1
tools/bin/fusesoc run --target sim axon:noc:islip_arbiter:0.1.0 --TEST=directed --SEED=1
tools/bin/fusesoc run --target sim axon:noc:islip_arbiter:0.1.0 --TEST=random --SEED=42 --CYCLES=200
```

It compiles `ip/noc/dv/tb/noc_islip_arbiter_tb.sv` as a timed SystemVerilog
binary through the Edalize `sim` flow. No custom C++ harness is required.
Requests are driven away from the rising edge, results are checked against an
independent priority-pointer model, and a mismatch calls `$fatal`. The terminal
output is retained in a unique
`artifacts/<core>/sim/<test>/seed-<seed>/<run-id>/sim.log` with the test, seed,
build-reuse result, simulation result, and exit status.

`random` uses an explicit xorshift32 stimulus generator so a seed has stable
meaning without relying on simulator-specific `$urandom` sequences. `CYCLES`
defaults to 200. Every cycle compares the complete match matrix against the
independent pointer-based model and separately checks that matches were
requested and are one-hot-or-zero for every input and output.

A temporary Stage 1 build-once, run-many-seeds regression proves the required
behavior. Its coordinator completes one locked incremental build check, releases the
build lock, and then launches up to `JOBS` run-only simulator processes. It
allows all scheduled seeds to finish, returns nonzero if any seed fails, and
writes `regression.log` plus `results.json` beneath a unique
`artifacts/<core>/regress/<test>/<regression-id>/` directory. Individual seed
logs remain in their normal unique simulation artifact directories.

The FuseSoC `coverage` target is **Available** and uses a separate instrumented
build from normal simulation. A single raw run is:

```text
tools/bin/fusesoc run --target coverage axon:noc:islip_arbiter:0.1.0 \
  --TEST=random --SEED=42 --CYCLES=200
```

Temporary Stage 1 campaign scaffolding runs `smoke` and `directed` once and runs `random` over
the requested seed range. `COVERAGE_TESTS=smoke,random` selects a subset. Each
worker owns a unique `sim.log` and `coverage.dat`; only successful runs are
merged, and any failed or missing database fails the campaign.

Output under `artifacts/<core>/coverage/<campaign-id>/` includes `merged.dat`,
categorized `summary.txt` and `summary.json`, `coverage.info`, annotated RTL,
`coverage.log`, and a JSON manifest. The summary is printed automatically and
separates line, branch, toggle, and property/functional points. In Verilator,
explicit `cover property` statements are the functional/property coverage
category rather than two independent metrics.

Ordinary testbench implementation is excluded from the RTL denominator. A
coverage-only monitor, selected solely by the FuseSoC `coverage` target, binds
to the DUT and owns verification-plan cover properties. Its helper logic has
automatic code/toggle instrumentation disabled so only its intentional user
coverage points enter the report. The manifest's build identity covers the
instrumented executable, generated EDAM/VC inputs, and Verilator version.

The reusable database parser is `scripts/coverage/report.py`. Although FuseSoC
supports build and single-run hooks, final reporting is a campaign operation:
it must happen after all isolated parallel runs and the compatibility-checked
merge. Therefore the campaign coordinator invokes the reporter immediately
after merging instead of attaching it to a per-build or per-seed hook.

An earlier compatible campaign can be accumulated with
`MERGE_FROM=artifacts/<core>/coverage/<prior-campaign-id>`. The command rejects
the merge when exact build identities differ, preventing coverage from
different RTL or tool builds from being combined accidentally.

Simulation builds are incremental by default. The build phase runs under a
per-core/target lock, and test execution starts only after that lock is
released. Existing outputs are reused when FuseSoC/Edalize's generated Make
dependencies are current. Use `REBUILD=1` to clean and rebuild that target
explicitly. Separate tests and seeds never share a result directory.

The remaining validation operations are **Planned** for the vertical slice:

```text
formal <core>
check-ip <core>
check-fast
check
```

These are operation names, not promises about a Make-based final CLI. Stage 2
selects the unified command surface.

Expected meanings:

- `lint`: run the selected meaningful RTL lint target;
- `sim`: run a named reproducible simulation;
- `coverage`: run isolated tests and merge compatible Verilator coverage;
- `formal`: run a named formal property set;
- `check-ip`: execute the required gates for one IP;
- `check-fast`: deterministic pre-commit subset;
- `check`: complete normal review/CI gate.

Long regressions, synthesis, FPGA builds, and NoC performance sweeps remain
separate from the default fast gate.

## Artifact model

The normalized artifact layout is **Planned**. Disposable tool work belongs
under `build/`; retained diagnostic evidence belongs under `artifacts/`:

```text
artifacts/<core>/<target>/<run-id>/
  run.json
  build.log
  simulation.log
  results.xml
  metrics.json
  waves.fst
```

### Build and run isolation principles

These rules are mandatory for every new target and generator:

- Tracked source is read-only during ordinary lint, build, simulation, formal,
  synthesis, and regression commands.
- A generator or post-processing step writes only within its assigned private
  build directory. It must never create or update collateral in `ip/`,
  `scripts/`, or another shared source location.
- Build products are reusable; test results are not build products. Each test
  invocation receives a unique artifact directory.
- Concurrent jobs must not configure or compile in the same mutable directory.
  A per-build lock is the Stage 1 local mechanism; immutable content-addressed
  cache entries are deferred to Stage 2.
- Runtime-only inputs such as TEST and SEED reuse a matching simulator build.
  Compile-time parameters, defines, sources, generators, tools, or build options
  may require rebuilding.
- A failed or interrupted build cannot be presented as a reusable completed
  build.
- FuseSoC dependencies should represent actual reusable source boundaries.
  Do not depend on a broad family core when the consumer needs one independently
  reusable component.

Direct simulation through the authoritative core target is:

```text
tools/bin/fusesoc run --target sim <vlnv> --TEST=<name> --SEED=<seed>
```

Use FuseSoC's clean/rebuild controls only for diagnosis or explicit
invalidation. The final validation CLI must offer the same semantic operation
without making Make variable syntax part of the methodology.

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
