---
name: axon-precheck
description: Review Axon RTL, verification, FuseSoC, generator, documentation, and integration changes before commit. Use when a user asks to precheck, review, validate, sign off, or prepare hardware changes for commit; when an agent finishes an RTL/DV/build task; or when a ticket requires verification evidence and a handoff. Do not use as a substitute for deterministic lint, simulation, formal, or generation checks.
---

# Axon Precheck

Produce an evidence-backed pre-commit review of the requested change. Run
deterministic checks first, then apply hardware-design judgment. Do not commit
unless the user explicitly requests a commit.

## 1. Establish scope

1. Read root and nearest scoped `AGENTS.md` files when present.
2. Read the ticket/specification and relevant block documentation.
3. Inspect `git status`, staged and unstaged diffs, and untracked task files.
4. Separate task changes from pre-existing or unrelated changes.
5. Identify affected FuseSoC cores, generated products, interfaces, clocks,
   resets, and verification environments.

Stop and ask before proceeding if the intended behavior, interface timing,
clock/reset contract, generated source of truth, or task ownership is
materially ambiguous.

## 2. Run deterministic policy checks

Run the repository checker against changed policy-controlled files:

```bash
python3 tools/checks/check_repo_policy.py
```

The pre-commit integration is initially manual while legacy RTL is normalized.
Do not dismiss failures merely because the hook is not enabled automatically.
Classify findings as introduced by the task or pre-existing.

Run the narrowest available FuseSoC/build targets for the affected core. Use
repository commands when present. Otherwise report the missing command surface
instead of inventing a permanent parallel build flow.

Never claim a command passed unless it was run successfully in the current
worktree. Record the exact command, test, seed, and artifact path.

## 3. Review hardware semantics

Read [references/review-checklist.md](references/review-checklist.md) and apply
only relevant sections. Prioritize concrete functional risks over cosmetic
style observations.

For every blocking finding provide:

- severity;
- file and line;
- violated contract or invariant;
- concrete failure scenario;
- recommended correction;
- confidence.

Allow a clean review with no findings. Do not manufacture issues to make the
review look substantial.

## 4. Check verification evidence

Confirm that the evidence matches the change:

- Lint is necessary but not functional verification.
- A behavioral change needs a self-checking test at the narrowest useful level.
- Randomized tests record reproducible seeds.
- Assertions check DUT responsibilities; formal assumptions constrain only
  the environment.
- Generated outputs match their declared inputs and generator.
- Formal pass/cover claims name the property set and target.
- Performance claims compare identical configurations and seeds.

Do not require UVM for a small unit when a direct self-checking SystemVerilog
test is clearer. Use the repository's UVM methodology for blocks/subsystems
that benefit from reusable transaction agents, sequences, coverage, and
scoreboards.

## 5. Produce the handoff

Return:

1. Overall status: `ready`, `ready-with-notes`, or `not-ready`.
2. Blocking findings, highest severity first.
3. Non-blocking findings.
4. Commands run and results, including seeds.
5. Verification not run and why.
6. Changed/generated/documentation files reviewed.
7. Remaining risks or decisions.

Do not weaken a deterministic gate to obtain `ready`. If a required tool is
unavailable, report the review as incomplete rather than treating it as a
pass.
