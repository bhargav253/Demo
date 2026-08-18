# Router simulation

This directory contains the customized BookSim model of the generic router and
the NoC12, NoC16, and NoC16C topologies. BookSim is vendored under `booksim2/`
so the exact simulator implementation is captured by this repository. The
unmodified upstream base revision is recorded in `BOOKSIM_REVISION`.

Compiled objects and simulation results remain local artifacts. Private study
notes and generated results live under `plan/` and `results/`; both directories
are intentionally ignored by the parent repository.

## 1. Install prerequisites

On Debian or Ubuntu:

```sh
sudo apt install build-essential flex bison
```

`flex` and `bison` generate BookSim's configuration-file parser. They are build
dependencies rather than Python packages.

## 2. Build the vendored BookSim source

From this directory:

```sh
make setup
```

The bootstrap script validates the checked-in `booksim2/` source and builds
`booksim2/src/booksim`. `BOOKSIM_REVISION` documents the upstream commit from
which the customized source was derived; setup does not fetch or overwrite the
local model.

## 3. Run the first experiment

```sh
make run
```

The result is printed to the terminal and saved as
`results/single_router_uniform.log`.

The initial configuration is deliberately simple:

- `topology = fly`, `k = 8`, and `n = 1` create one radix-8 router.
- Eight traffic sources are attached to its eight input ports.
- Uniform random traffic chooses among the destinations.
- A packet is one flit; for our DAT network, one flit represents 256 bytes.
- Each input has one eight-flit VC.
- The switch allocator uses one iSLIP iteration.
- The offered load is 0.02 packets per source per cycle, safely below the
  baseline router's saturation point.

The reported packet latency includes injection, router pipeline, and ejection
behavior in BookSim's model. The initial run proves the toolchain and provides a
stock reference; it does not yet implement our per-output VOQs, four physical
lanes, endpoint shim, or shared-buffer credit policy.

## Custom lane-preserving VOQ baseline

Run the first custom-router configuration with:

```sh
make run-voq
```

`configs/lane_voq_flop_4p16s.cfg` models one router with eight port groups and
four lanes per group. Endpoint `port*4+lane` generates traffic to a different
port on the same lane. Each input port has four initially advertised credits
per lane and 16 receiver-owned shared tokens, for 32 ideal flop-array payload
entries. An arrival consumes a shared token when its lane credit is returned
immediately and increments that lane's shared-token debt. Departures from a
lane replenish the shared pool until that lane's debt reaches zero; only later
departures return lane credits upstream. Individual entries are not tagged as
private-backed or shared-backed.

This is the ideal 4-read/4-write reference. It does not yet model SRAM banks,
bank conflicts, the pool-first repayment alternative, or the complete
topology.

### Directed two-lane CSV trace

```sh
make run-trace
```

This activates only input port 0 lanes 0 and 1. They target output port 1 on
their corresponding lanes at an offered rate of 0.5 packet/lane/cycle. The
packet statistics are saved in `results/lane_voq_trace_2lane.log`, and the
per-cycle S0/S1/S2/S3 events are saved in
`results/lane_voq_trace_2lane.csv`.

The CSV records router and packet IDs, physical source/destination, decoded
port and lane, total input-port occupancy, free shared tokens, per-lane shared
debt, and whether an event returned a lane credit or replenished the pool.

### Credit return policies

The custom router accepts:

```text
voq_credit_policy = strict_pool;
voq_credit_policy = lane_first;
```

`strict_pool` repays a lane's shared-token debt before returning any withheld
lane credit. `lane_first` returns a withheld lane credit first and repays shared
debt only when that lane has no withheld credit. Both policies conserve the
same physical capacity; they differ in whether newly freed capacity is kept in
the receiver pool or eagerly placed back into the upstream credit loop.

Run the full-load balanced comparison with:

```sh
make run-credit-sweep
```

The sweep covers five seeds, private depths 1/2/4, shared depths 16/32, and
one/two iSLIP iterations for both policies. Results are written to
`results/credit_policy_sweep.csv`. Full-load single-router sweeps use
`voq_ideal_output = 1` to remove the stock BookSim terminal's fixed-credit
ejection bottleneck; topology experiments must use real downstream credits.

The equivalent all-inputs-to-one-output-port hotspot sweep is:

```sh
make run-credit-sweep-t3
```

Its results are written to `results/credit_policy_sweep_t3.csv`.

To compare five published credits per lane at equal total capacities (`5+12`
versus `4+16`, and `5+28` versus `4+32`), run:

```sh
make run-credit-sweep-t4-p5
```

Results are written to `results/credit_policy_sweep_t4_p5.csv`.

### Landing-flop bypass

`voq_bypass = 1` is the default. An S0 arrival whose local input/output VOQ is
empty may request its output directly. Simultaneous bypass requests use a
separate per-lane P-by-P matching allocator. A winning packet does not consume
a payload slot or shared token and returns its landing-buffer credit
at the S1-equivalent boundary; a loser is enqueued normally. An output already sending an S2
payload read that cycle is not eligible for bypass.

For the normal queued path, the payload slot and any deferred lane/shared
credit are released when the payload read completes in S2. S3 only transmits
the already-read payload.

Compare bypass disabled/enabled for strict-pool and lane-first repayment over
T1 through T4, private lane credits 2/3/4, five seeds, latency traffic at 0.03
packet/source/cycle and full-load throughput traffic with:

```sh
make run-bypass-sweep
```

Results are written to `results/bypass_comparison.csv`.

For a bypass-enabled full-load comparison using four private credits per lane,
32/48 total entries per input port, strict/lane-first repayment, one/two iSLIP
iterations, and five seeds, run:

```sh
make run-full-load-matrix
```

This writes throughput, output utilization, and network latency (not source
queueing/packet latency) to `results/full_load_matrix.csv`.

## Deterministic regression tests

Run the allocator and cycle-exact router checks with:

```sh
make test
```

The suite checks a crafted one-versus-two-iteration iSLIP matrix, round-robin
fairness, queued S0/S1/S2/S3 timing, S2 credit release, bypass timing and
contention, lane preservation, strict/lane-first debt ordering, capacity/token
conservation, and exact full-rate T1 throughput. Test traces are retained under
`results/tests/` for inspection.

## Four-bank 1R1W payload model

The banked modes use explicit `{private/shared, bank}` tags on returned credits
and injected requests. `sram_fixed` maps lane `l` exclusively to bank `l`.
`sram_shared` protects four home entries per bank and reserves remaining slots
with either `voq_bank_policy = rr` or `pressure`. Two allocator iterations run
on residual unmatched inputs, outputs, and banks.

The adversarial lookaside proof is:

```sh
python3 tests/lookaside_exhaustive.py
```

It proves safe total waiting bounds of 12 for Q32 and 18 for Q48, including the
four landing flops. Run deterministic bank tests with `make test-bank`, and the
five-seed T4 flop/fixed/shared comparison with `make run-banked-sweep`.

For the fixed-lane, conflict-free SRAM depth comparison across T1--T4, Q48 and
Q64, strict/lane-first credits, one/two allocator iterations, and five seeds:

```sh
make run-fixed-depth-sweep
```

Results are written to `results/fixed_bank_depth_sweep.csv`. In this mode each
lane exclusively owns its bank; the capacity beyond four advertised credits is
lane-local and cannot be borrowed by another lane.

The cleaner fixed-bank configuration advertises the entire physical bank and
uses no pool: 8/12/16 credits per lane for Q32/Q48/Q64. Run it with:

```sh
make run-fixed-exact-credit-sweep
```

Results are written to `results/fixed_exact_credit_depth_sweep.csv`.

## Two-VC sharing within a fixed lane bank

The locked Q32 organization uses four independent eight-entry SRAM banks, one
per lane. With `voq_vc_sharing = 1`, each lane has separate request and response
VOQs. The transmitter sees the complete lane depth as credits, partitions a
programmed reservation per VC, and puts the remainder in a common pool. Sending
uses the pool first. A returned credit carries only its VC: it refills that VC's
reservation if deficient, otherwise it refills the common pool. No pool/private
tag crosses the interface. A local round-robin VC choice presents one request
to the existing physical 8x8 two-iteration iSLIP allocator; the VCs are not
modeled as sixteen physical inputs.

Run directed conservation, isolation, and physical-output tests with:

```sh
make test-vc
```

Run the five-seed Q32/Q48/Q64, reservation 1/2/4, one/two-iSLIP-iteration
T3/T4 comparison with:

```sh
make run-vc-sharing-sweep
```

Raw Q32/Q48/Q64 results are in `results/vc_sharing_depth_sweep.csv`; five-seed
means are in `results/vc_sharing_depth_summary.csv`.

`voq_allocator = max_size` selects an exact maximum-cardinality bipartite
matching for each lane and cycle, with rotating input/output tie-breaking for
fairness. The sweep compares it against one- and two-iteration iSLIP using the
same readiness, credit, SRAM, bypass, and output constraints.

`voq_read_latency` controls the pipelined queued SRAM-read delay from the S1
match. Values 1/2/3 trace queued completions as S2/S3/S4 and sends as S3/S4/S5;
bypass remains on its original fast path. The locked Q48 two-VC, R1, two-iSLIP
comparison is reproduced with `make run-read-latency-sweep`.

## Configuration experiments

BookSim experiments are ordinary text configuration files. Copy the baseline
configuration, change one parameter, and run BookSim directly:

```sh
./booksim2/src/booksim configs/my_experiment.cfg
```

Important baseline parameters are:

| Parameter | Meaning |
| --- | --- |
| `k` | Ports on the single-stage fly router |
| `num_vcs` | Virtual channels per input channel |
| `vc_buf_size` | Flit entries in each VC |
| `alloc_iters` | iSLIP matching iterations per allocation |
| `packet_size` | Flits in each packet |
| `injection_rate` | Packets offered per source per cycle |
| `traffic` | Source-to-destination traffic pattern |

The next performance experiment is an injection-rate sweep that produces a
latency-versus-offered-load curve for each private/shared capacity policy.
## Sixteen-LLCH complete topology

The `noc16` topology implements the 4x4 L1 mesh and perimeter LLCH organization
specified in `configs/noc.cfg`. It contains 16 five-port/four-lane L1 routers,
16 six-port/four-lane L2 routers, 64 five-port/one-lane L3 routers, and 64
separate L3/L2 lane shims. The shim hashes L3 traffic onto one L2 lane and
round-robins four L2 lanes onto the one-lane L3 side at one transfer/cycle.

Stable endpoint node ranges are:

```text
0..63     PE
64..127   TDMA
128..191  TSRAM
192..255  CSRAM
256..319  CDMA lanes
320..383  LLCH lanes
```

Run correctness tests with `make test-noc16`. This validates graph counts and
reciprocity, heterogeneous L3 construction, the exact near path, deterministic
X-then-Y routes to every LLCH while covering all four lanes, full drain, and
four-to-one shim throughput/fairness.

Run the first balanced PE-to-LLCH baseline with `make run-noc16-initial`.
The summary is written to `results/noc16_initial_summary.csv`. Interval CSVs
contain router/shim arrivals, departures, occupancy, shim contention/credit
stalls, lane-level link activity, and endpoint injection/ejection. BookSim's
accepted rate is averaged over all 384 nodes; multiply it by 384 for total
delivered packets/cycle.

The current topology model represents the command-owned 256-byte transfer as
one BookSim flit. Beat-accurate two-cycle CMD-to-DAT following, LLCH/HBM service
timing, and HBM-stack pairing remain later layers.

### Per-logical-port telemetry and NoC16 load sweep

NoC16 telemetry now emits `kind=port` rows for each L1, L2, and L3 logical
output port, aggregated across lanes and VCs. Rows include arrivals, departures,
instantaneous output-directed occupancy, request/grant opportunities, allocator
loss, downstream-credit stalls, queue-wait sums/samples, and router-residence
sums/samples.

Run exact port timing and conservation checks with `make test-noc16`. Run the
five-seed offered-load curve with `make run-noc16-phase3`; results are written to
`results/noc16_phase3/runs.csv` and `results/noc16_phase3/by_rate.csv`.

The L1 grant stage can optionally use static topology-derived weighted round
robin while retaining ordinary round robin in the input accept stage:

```text
voq_grant_policy = weighted;
```

Weights are generated from one equal flow from every L1 cluster to every LLCH
over the existing X-then-Y routes. A request with no weight in that reference
workload receives weight one, so weighting never disables a route. L2/L3 grants
remain ordinary round robin. Run the matched five-seed RR/weighted comparison
with `make run-noc16-grant-comparison`; its combined summaries are under
`results/noc16_grant_comparison`.

The `noc12` topology implements the 3x3 interstitial L1 mesh, 16 surrounding
L2 cluster routers, 64 L3/shim paths, and 12 perimeter LLCHs recorded in
`configs/noc.cfg`. L2 routers can connect to up to four neighboring L1 routers
and participate in transit. Routing is deterministic minimum-hop with a
horizontal-reduction preference when minimum paths tie. Run its graph, route,
delivery, telemetry, and policy tests with `make test-noc12`.

Run the matched NoC12 RR/weighted sweep with:

```text
make run-noc12-grant-comparison
```

NoC12 weights apply to output grants in both L1 and transit-capable L2 routers;
input accepts, L3 routers, and shims remain ordinary RR. Results are under
`results/noc12_grant_comparison`. The sweep also regenerates
`results/noc12_vs_noc16_by_rate.csv`.
