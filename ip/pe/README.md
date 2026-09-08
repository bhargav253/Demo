# Syst PE prototype

This directory currently contains the `syst` 2×2 matrix-multiply prototype,
not the complete future Axon processing element.

The RTL and `axon:pe:syst:0.1.0` core pass strict Verilator lint. The new self-failing `sim` target exposes a top-level matrix mismatch;
it is diagnostic evidence, not a functional pass. The independent `sim_fifo`
target passes capacity, ordering, simultaneous-operation and reset checks with
active FIFO assertions. Full integration verification remains pending. See `doc/syst.md` for the implemented microarchitecture and known
limitations.
