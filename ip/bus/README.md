# Axon bus components

This directory contains APB and AXI4-Lite helpers under the FuseSoC core
`axon:bus:components:0.1.0`.

The Stage 0 cleanup establishes syntax, style, dependency, elaboration, and
Verilator lint correctness. It does not establish AXI/APB protocol correctness.
The modules predate the Axon methodology and require directed unit tests before
being classified as `unit_verified` or used as reference implementations.

Known verification priorities include independent AXI write-address and write-
data arrival, ready/valid stability under backpressure, response ordering,
decode misses, APB setup/access timing, and reset during outstanding requests.

In particular, several current AXI-Lite write paths assume that address and data
valid arrive together. The custom-interface adapter also needs a test proving
that its request and response-tag queues advance atomically. Do not treat these
as protocol-safe assumptions until the Stage 1 tests resolve them.
