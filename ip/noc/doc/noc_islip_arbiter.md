# iSLIP arbiter

## Purpose

`noc_islip_arbiter` selects a conflict-free matching between the inputs and
outputs of a square switch. It currently implements one iSLIP grant/accept
iteration per cycle.

## Parameters

`NumPorts` is the number of switch inputs and outputs. The implementation also
supports the degenerate one-port case.

## Interfaces

Both request and match matrices use `[input][output]` orientation:

- `req_i[input][output]` requests an input-to-output connection;
- `match_o[input][output]` identifies an accepted connection.

Each input and each output appears in at most one asserted match.

## Clock and reset

Priority state is clocked by `clk_i`. `rst_ni` is active low and synchronous.
Reset gives port zero the initial highest priority.

## Microarchitecture

Every output first performs a round-robin grant among its requesting inputs.
Every input then performs a round-robin accept among the outputs that granted
to it. The combinational match is visible in the same cycle as the request.

The grant and accept stages use the stateless `prim_arbiter_rr_select`. The
iSLIP block owns the priority masks and commits a new mask only for an accepted
match. The existing stateful `prim_arbiter_ppc` and `prim_arbiter_tree` are not
used directly because their ready/valid state update occurs at grant time;
iSLIP separates grant from acceptance.

## Operation and timing

Requests pass through one combinational grant stage and one combinational
accept stage. There is no output register. On the following rising edge, each
successful match advances its output grant priority and input accept priority.

## Assertions and invariants

The Stage 1 verification slice will check:

- at most one match per input and per output;
- every match was requested;
- priorities change only following an accepted match;
- persistent contenders receive service under sustained eligible traffic;
- reset restores the documented initial priority.

## FuseSoC targets

- `default`: synthesizable RTL and primitive dependencies;
- `lint`: strict Verilator lint.

Simulation and formal targets are intentionally deferred to Stage 1.

## Limitations and deferred work

This version performs exactly one iSLIP iteration. Standard multi-iteration
iSLIP can improve matching size by repeating grant and accept for unmatched
ports. If that feature is added, priority masks must still update only from
matches accepted during the first iteration.

The block is linted but not yet functionally verified. A Draw.io source and
rendered PNG will be added with the Stage 1 documentation pilot.
