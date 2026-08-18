# NoC Telemetry Viewer Prototype

This viewer supports synthetic topology review and real NoC16 per-router and
per-logical-output-port telemetry.

The deterministic layouts and sample telemetry are checked in with the viewer.
The private generator used during development is kept with the ignored NoC
study notes rather than exposed as part of the runtime tool.

To launch the viewer:

```bash
./serve.sh
```

Open <http://127.0.0.1:8000/scripts/noc_viewer/>.

The NoC16 sample loads automatically. Use `Bundled topology` to switch seamlessly
between NoC16, NoC12, and NoC16C. Alternatively, open
`index.html` directly and choose these files with the two file inputs:

```text
sample/noc16_layout_v2.json
sample/noc16_synthetic_telemetry.csv
```

The equivalent NoC12 files are `sample/noc12_layout.json` and
`sample/noc12_synthetic_telemetry.csv`. The NoC12 display uses a 4x4 L2 cluster
grid, nine interstitial L1 routers, diagonal L1/L2 links, straight cardinal L1
mesh links, and 12 perimeter LLCHs. Its IDs match the executable NoC12 BookSim
network. NoC16 south links retain their elbow route
because a straight line would pass through the local L2/shim/L3 drawing.

The bundled selector contains self-contained synthetic examples for NoC12,
NoC16, and NoC16C. Simulation results are intentionally private and are not
referenced by the checked-in viewer. To inspect a real run, select the matching
layout and load its telemetry with the `Telemetry CSV` file control. NoC16C's
layout has 592 logical ports matching the executable topology.

The sample deliberately creates a hotspot around L1_07, L1_11, and L2_14. All
values, including average latency, are synthetic and are not BookSim results.

Current scope:

- Physical 4x4 cluster placement and perimeter LLCH placement.
- Nested L1, L2, four shims, and four L3 nodes per cluster.
- Metric and component-level selection.
- First/previous/play/next/last cycle navigation.
- Node detail panel.
- Logical-port heat maps and clickable port detail.
- Automatic heat-map color scale.
- Optional fixed color maximum for direct comparisons between datasets/cycles.
- Cursor-centered mouse-wheel zoom, button zoom, click-drag pan, and Fit reset.
- L1 mesh links anchored at logical ports; south links use elbow routing around
  the local L2/shim/L3 drawing for clarity.

Synthetic port rows use the router ID plus `port` as their identity. They carry
request/grant counts, allocator losses, credit stalls, queue-wait sums/samples,
and residence-time sums/samples. Select a `Port ...` metric to display them.

Navigation:

- Scroll the mouse wheel over the topology to zoom around the cursor.
- Drag empty space or the topology to pan.
- Use `+`, `-`, and `Fit` in the toolbar for keyboard/mouse-friendly controls.
- Zoom is limited to 8x to keep navigation manageable.

Deferred work:

- Dynamic per-link and per-lane values.
- History plots, route highlighting, and run comparison.
