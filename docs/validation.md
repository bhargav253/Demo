# Axon validation guide

The repository-owned FuseSoC fork provides commands to run tests, regressions,
coverage, dependency-selected smoke checks, and simulator cache operations.
The RISC-V and iSLIP configurations demonstrate firmware and SystemVerilog tests.
See each IP's documentation for qualification status and known limitations.

## Run and inspect core health

```sh
python3 tools/env/bootstrap.py
tools/bin/fusesoc regress axon:core:riscv:0.1.0 --suite smoke
tools/bin/fusesoc regress axon:core:riscv:0.1.0 --suite health
tools/bin/fusesoc coverage axon:core:riscv:0.1.0 --suite coverage
tools/bin/fusesoc status axon:core:riscv:0.1.0
```

Every campaign prints a link to `health.html`, `run.json`, and a terminal result.
The HTML report is a standalone local file with a test/status filter. Markdown
and JUnit versions are generated alongside it. No web service or account is
required. `status` displays the latest completed campaign's suite and result,
and compares revision, configuration and source-content fingerprint. It returns
nonzero when that evidence is stale or unsuccessful. A smoke pass describes
smoke only; it does not imply that the full health or coverage suite ran.

Select one test or inspect expansion before running:

```sh
tools/bin/fusesoc regress axon:core:riscv:0.1.0 --list
tools/bin/fusesoc regress axon:core:riscv:0.1.0 --suite health --dry-run
tools/bin/fusesoc test axon:core:riscv:0.1.0 --test act4/I-add-00 --run-mode wait3 --seed 42
```

`--jobs` bounds parallel simulations. `--timeout` overrides the default wall-clock
limit. `--seed` and `--run-mode` override the suite's seed/mode selection; they do
not change elaboration. Exact commands and effective selection are recorded.

## Declaration and ownership

The `.core` file remains authoritative for RTL, dependencies, filesets, build
parameters and targets. Its strictly validated `validation` section owns
per-core test intent. `verification/validation.json` owns shared local resource
limits. It contains no RTL source paths, test membership or CI-provider syntax.

The model is versioned independently of CAPI:

```yaml
validation:
  version: 1
  build_modes:
    sim:
      target: sim_fw
      kind: simulation
      pass_pattern: '(?m)^PASS status=1 cycles=[0-9]+$'
      wave_arg: WAVE
  run_modes:
    base: {parameters: {WAIT: 0}}
    wait3: {parameters: {WAIT: 3}}
  tests:
    act4:
      build_mode: sim
      manifest: prebuilt/riscv_arch/rv32im/core_sim/manifest.json
      parameters: {TEST: act4, CYCLES: 2000000}
  regressions:
    health:
      - tests: [act4]
        run_modes: [base, wait3]
        seeds: [1, 42]
  limitations:
    - Selected I/M tests, not full architectural certification.
```

This example deliberately expands the Cartesian product of two modes and two
seeds. The actual CPU health suite uses baseline seed 1 and wait3 seed 42.
Manifest paths are repository-relative; each ELF and associated configuration
checksum is verified before building. Manifest members become selectable names
such as `act4/I-add-00`. No binary generation or publication occurs during a run.

Build-mode parameters must be compile-time parameters declared by the target.
Test/run-mode parameters must be declared runtime plusargs. Wave/coverage output
arguments are adapter metadata, not hard-coded CPU behavior in the scheduler.
Unknown fields, versions, targets, tests, modes and parameters fail validation.
The schema is in `fusesoc/validation/schema.py`; normal core discovery validates
its shape, and campaign planning validates references and parameter categories.

## Example: RISC-V test suites

| Suite | Selection |
| --- | --- |
| `smoke` | Lint, built-in boot smoke, directed firmware: 3 jobs |
| `health` | Smoke plus 47 ACT4 I/M tests at wait0/seed1 and wait3/seed42: 97 jobs |
| `presubmit` | Currently the same fixed health suite; no change-impact selection |
| `postsubmit` | Currently the same fixed health suite; not automatically scheduled |
| `coverage` | Health selection, replacing simulation builds with the coverage target |
| `nightly` | Smoke plus 47 tests × four delay modes × two seeds: 379 jobs |

These are repository declarations, not promises of configured CI automation.
Dependency-selected smoke checks are now available through the repository
`presubmit` command below. CI enforcement is not configured. The iSLIP example
has its own smaller fixed suites; its existing formal gate remains separate.

## Execution and reproducibility

A campaign validates and expands all jobs before starting builds. Each selected
build mode is built once through FuseSoC in a unique disposable build directory.
The campaign snapshots the completed executable and makes it read-only; all jobs
consume it and write exclusively to private run directories. Two campaigns never
share a mutable build directory. Eligible Verilator simulator builds use the
content-addressed cache described below; target checks such as lint execute fresh.

Each build records resolved EDAM, exported source hashes, compiler/Verilator
versions and repository tool identity. The resulting build identity distinguishes
effective build inputs. Runtime seeds/ELFs do not cause per-test compilation.
Separately named build modes can reuse an identical cached simulator after
resolving their effective inputs.

A simulation passes only if the process exits zero, its required pass pattern
appears, and no failure pattern appears. Timeout, cancellation, missing coverage,
build failures and skipped jobs cannot produce an overall pass. Builds and jobs
record status and wall time; the CPU adapter also reports simulated cycles.
The live manifest distinguishes queued, running, passed, failed, timed-out,
cancelled and not-run jobs. Failures are grouped by recorded reason.

Defaults are four workers, 600 seconds per subprocess, 4 MiB logs, 32 MiB per
simulation output file, and 1 GiB per compiler output file. SIGINT/SIGTERM cancels
queued work and kills owned process groups. Machine loss/SIGKILL may leave a
RUNNING manifest; it is incomplete evidence. Passing simulation waves are deleted;
failure waves and bounded logs remain. No automatic retry can hide a failure.

```text
artifacts/<core>/validation/<campaign>/
  run.json, summary.md, health.html, junit.xml
  builds/<mode>/build.json, build.eda.yml, build.log, simulator
  runs/<job>/run.json, sim.log, input.elf, [waves.fst], [coverage.dat]
  coverage/merged.dat, summary.json, summary.txt, merge.log
```

Replay a simulation without rebuilding or relying on the current prebuilt ELF:

```sh
tools/bin/fusesoc replay artifacts/<core>/validation/<campaign>/runs/<job>/run.json
```

Replay verifies retained executable/ELF hashes, runs the recorded parameters in a
new directory and preserves the original. A tool/build failure instead includes
the original command in `build.json`; rerun the campaign to rebuild. Replay is
currently local to this checkout/host environment; portable artifact relocation
and hermetic container/toolchain capture are not implemented.

## Coverage meaning

The CPU coverage target enables Verilator line, branch, toggle and user cover
instrumentation. The harness clears counters after reset initialization and
writes each run's database. Merge requires all selected jobs to pass and every
coverage database to belong to the same build identity. Partial campaigns remain
failed and are not published as merged coverage. There is no cross-campaign merge
command or automatic coverage closure threshold.

The existing categorized reporter is reused. Files tagged `coverage_exclude` in
FuseSoC metadata contribute no automatic line/branch/toggle points; explicit user
cover bins remain. This prevents verification-monitor ports from diluting RTL
metrics. Exclusions and their counts are recorded in the coverage summary.

Eleven CPU observation bins cover fetched opcode classes, accepted loads/stores,
and cycles with memory acceptance withheld. The CPU gates request outputs with
acceptance, so request-high/accept-low is not used as a ready/valid stall bin.
These bins are not instruction-retirement coverage, proof of the M extension,
privileged coverage or architectural certification. Missing checks remain visible
in each report's scope section even when all selected tests pass.

## Implementation and DVSim relationship

The chosen design is an Axon-owned integrated implementation, not a bundled
upstream DVSim executable or a drop-in Hjson-compatible DVSim frontend. It follows
the concepts in the [DVSim design document](https://github.com/lowRISC/dvsim/blob/master/doc/design_doc.md)
and the [OpenTitan UART configuration](https://github.com/lowRISC/opentitan/blob/master/hw/ip/uart/dv/uart_sim_cfg.hjson):
build/run modes, named tests/regressions, reseeding, bounded scheduling,
pass/fail parsing, isolated evidence and coverage merging.

Internally, schema/model, execution, scheduler, coverage and reporting remain
separate modules under `scripts/fusesoc/fusesoc/validation/`. The runner supports
CPU firmware and SV tests without requiring UVM. Farm launchers, a report
publication service, and full DVSim feature parity are not implemented.

## Migration

The commands above are the primary validation interface. Direct `fusesoc run`
remains the single-target build/run interface. Earlier Make targets, `tools/build/`,
and `tools/verification/run_firmware.py` are retained as legacy compatibility
paths. New campaign features belong in the integrated FuseSoC layer. Firmware
generation/import remains a separate, explicit operation under
`tools/verification`.

## Dependency-selected smoke checks

```sh
# Inspect affected cores, their tests, counts, and selection reasons.
tools/bin/fusesoc presubmit --base HEAD --dry-run
# Include branch changes since the merge base with your chosen base reference.
tools/bin/fusesoc presubmit --base main
# Explicitly request a broader per-core suite, or all registered cores.
tools/bin/fusesoc presubmit --base main --suite health
tools/bin/fusesoc presubmit --base main --full
```

`presubmit` is a repository command. Its default suite is each affected core's
`validation.regressions.smoke`; it does not invoke the older per-core fixed
`presubmit` regression alias. `--base HEAD` includes staged, unstaged and
untracked changes. A branch reference also includes committed changes since its
merge base with HEAD. Deleted and renamed paths participate in selection.

Each core owns its tests and smoke membership. For example, a future PE mesh
core would declare its CPU dependency in its reusable RTL fileset and its own
integration smoke tests in `validation`. A change to CPU sources selects CPU
smoke plus PE mesh smoke automatically. No separately maintained reverse list
or instruction-level test mapping is required. Dependencies must be declared in
FuseSoC: this command does not infer missing dependencies by parsing RTL module
instantiations.

The selector resolves registered cores through FuseSoC's dependency solver,
including version/provider resolution, and traverses direct and transitive
consumers. It unions declared target graphs and Boolean conditional variants;
this can conservatively select a consumer whose dependency appears only in a
particular target. Each selected core's suite runs once, regardless of the number
of changed files or dependency paths. Core campaigns execute sequentially;
`--jobs` bounds workers within each campaign. Seeds and tests still share a
single build per declared build mode within that campaign.

Source ownership comes from resolved files and the owning `.core` path. For
unlisted/deleted IP-local files, containing core directories provide a
conservative ownership fallback. Firmware manifests automatically associate
their ELFs and configuration files with the owning core. Platform manifests associate their hardware core and
referenced inputs. Selected cores validate all declared firmware/configuration
hashes before execution, including manifests outside the selected smoke suite.
`verification/impact.json` explicitly classifies documentation, shared policy,
and optional non-HDL owner rules (for example generator schemas/templates).
Exact source/platform ownership takes precedence over documentation exclusions.
Unknown paths and shared tooling select all registered cores, including explicit
missing-suite findings. Unresolved/generated graphs broaden selection and block
execution until their composition is known; a parse error cannot silently remove
a core. Boolean flag enumeration is bounded at eight flags per core. No generator
is run merely to inspect impact; generated targets without a resolved graph are
explicitly incomplete.

An affected core without the requested suite is reported as `BLOCKED`; execution
does not silently skip it or manufacture a lint-only smoke definition. Many
legacy cores, including syst, still need qualified smoke declarations before a
repository-wide gate can pass changes that affect them. The selection report
identifies missing suite qualification; it does not waive the required checks. `--full` includes every registered core and reports missing
suites; it does not silently restrict the gate to already-qualified cores.

Before execution, `artifacts/impact/<id>/selection.json` and `selection.txt` record
changed paths, merge base, source identity, resolved edges, selected jobs/counts,
reasons, fallback explanations and missing suites. The JSON then records aggregate
results and links to per-core campaign manifests. Each campaign records its
selection-manifest link and dependency reasons alongside the normal run evidence.
Source changes during selection or execution invalidate the aggregate result.
A dry run creates selection evidence but does not build or simulate. A no-change
execution reports `NO_CHANGES`; an explicitly classified documentation-only change
reports `NO_HARDWARE_CHANGES`. Neither result claims that hardware tests ran.
These local commands do not configure CI enforcement.


## Compiled simulator cache

Eligible standalone Verilator simulation builds automatically use
`build/cache/validation/v1/entries/<sha256>/`. Every campaign first resolves,
generates/exports, and configures its target through FuseSoC in a private work
directory. It then computes a versioned identity from effective EDAM compile
options/parameters, source and exported/generated file contents, declared include
directory contents, repository tool/launcher identity, compiler executables,
Verilator runtime files, system header contents and link inputs, installed
package versions, host identity, and a digest of inherited environment values.
Environment values outside the existing diagnostic allowlist are not recorded in
plain text. Runtime TEST/SEED/ELF/WAIT plusargs do not enter the compile key.

A hit verifies the identity and executable/log hashes, then copies the simulator
into that campaign's retained artifacts. A miss compiles through FuseSoC and
publishes only a successful, unchanged build. Per-key OS locks serialize matching
misses. Publication uses a private directory, a completion marker written last,
and atomic rename. Entries are read-only; simulations always use their own
retained copy and private output directory. Cache pruning cannot invalidate a
running campaign or a retained replay. Lint, formal and simulation results are
never cached. Deleting cache entries causes recompilation, not skipped checks.

The build table and `build.json` report `HIT`, `MISS` or `BYPASS`, the key, the
reason, and the original build provenance for a hit. Commands:

```sh
tools/bin/fusesoc cache list
tools/bin/fusesoc cache show <full-sha256>
tools/bin/fusesoc cache diff <first-sha256> <second-sha256>
tools/bin/fusesoc cache prune --max-mib 1024 --dry-run
tools/bin/fusesoc cache prune --max-mib 1024
tools/bin/fusesoc regress axon:core:riscv:0.1.0 --suite health --no-cache
```

Pruning removes least-recently-used entries until the requested byte budget is
met, skips locked entries, and cleans abandoned publication directories when
unlocked. A zero budget removes all unlocked entries. `--no-cache` bypasses both
lookup and publication. The versioned directory is the explicit invalidation
boundary for future identity/adaptor changes; older versions are never hits.

Version 1 qualifies the repository's local Linux/GNU, packaged-toolchain,
standalone Verilator flows. Build hooks, VPI, custom compiler/launcher overrides
and undeclared external compiler/include/library options bypass reuse and build
fresh. This is a local filesystem cache, not portable binary relocation or a
remote execution service. ccache and remote cache distribution are not integrated.
