# Axon hardware review checklist

Load the sections relevant to the changed files and task.

## RTL structure

- Module and filename agree; ports and parameters follow Axon naming.
- Public and local parameters are typed and legal combinations are checked.
- Widths, casts, signedness, shifts, comparisons, and literals are explicit.
- Combinational blocks assign defaults and do not infer unintended latches.
- Sequential state uses `always_ff`, nonblocking assignments, and synchronous
  active-low reset through `rst_ni`.
- State intentionally left unreset cannot become externally visible as valid.
- Generate blocks and instances are named and connections are explicit.

## Protocol and control

- Transfer/commit conditions match the interface contract.
- Payload and control remain stable while stalled when required.
- Backpressure does not introduce an undocumented combinational loop.
- Reset, flush, cancellation, and error behavior are defined.
- Arbitration grants and accepts are mutually exclusive and legal.
- Fairness state advances only on the documented accepted operation.
- Queue occupancy, pointers, credits, and in-flight transfers conserve.
- No loss, duplication, unintended reorder, overflow, or underflow is possible.

## Clock and reset domains

- Each state element belongs to an identified clock/reset domain.
- Cross-domain data uses an intentional synchronizer, handshake, or FIFO.
- Multi-bit CDC data is not treated as independent synchronized bits.
- Resets are synchronous to their destination domains under Axon policy.

## Assertions and formal

- Assertions use the Axon wrappers and are not silently disabled.
- Assertions check DUT obligations; assumptions describe legal environments.
- Knownness checks are gated by validity where appropriate.
- Formal properties are non-vacuous and useful cover states are reachable.
- Unsupported temporal syntax has a documented portable or tool-specific form.

## Verification

- Tests are self-checking and cover the stated acceptance criteria.
- Directed corner cases precede randomized volume.
- Random seeds and failures can be replayed.
- Scoreboards model externally visible behavior rather than copying DUT logic.
- An expected failure returns nonzero and retains actionable logs/waves.
- Coverage is interpreted against the verification plan, not as a standalone
  quality score.

## FuseSoC and generation

- Core VLNV uses `axon:<library>:<name>:<version>`.
- `default` contains reusable synthesizable sources only.
- DV, formal, waiver, and generated filesets do not leak unintentionally into
  downstream dependencies.
- Source order, dependencies, parameters, top level, and tool options are
  correct.
- Generated files were changed through their source schema/templates and pass
  regeneration comparison.
- New lint waivers are narrow and justified.

## Documentation and integration

- Behavioral documentation agrees with RTL timing and limitations.
- Draw.io remains the diagram source and rendered PNG is current.
- Interface, clock/reset, address, interrupt, and parameter changes propagate
  to consumers.
- Top-level connectivity has no missing required port, multiple driver, width
  mismatch, address overlap, or undeclared crossing.

## Change hygiene

- Diff contains only task-scoped files.
- Imported copyright and SPDX notices remain intact.
- No credentials, local absolute paths, build products, logs, or waves are
  accidentally tracked.
- The handoff reports tests actually run and known gaps without overstating
  maturity.
