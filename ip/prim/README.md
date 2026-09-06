# Axon primitives

This directory contains the reusable RTL primitive library used by Axon IP.
FuseSoC cores use the `axon:prim:*:0.1.0` namespace. Axon-owned versions use
synchronous active-low reset and may intentionally diverge from their source.

## Import baseline

The initial lowRISC/OpenTitan-derived primitive set was fingerprinted against:

- repository: `https://github.com/lowRISC/opentitan`
- commit: `bd069a06711746a9bb25146bf39df9b43043173c`
- snapshot date: September 30, 2025

Before Axon normalization, the existing assertion, counter, FIFO, CDC-delay,
flop-macro, and utility sources matched that snapshot. The request/acknowledge,
sum-tree, fixed-priority arbiter, PPC round-robin arbiter, tree round-robin
arbiter, and PPC leading-one helper were imported from the same commit.

This record identifies the starting point; these files are maintained as Axon
RTL and are not automatically synchronized with upstream.
