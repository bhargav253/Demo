# Architectural and performance models

`noc/` contains the customized BookSim router/network model, configurations,
experiments and model tests formerly stored under `sim/noc/`.

These models evaluate architectural behavior and performance. Model tests do
not establish equivalence to RTL. IP-local RTL testbenches remain under
`ip/<block>/dv`. Reserve `sim/` for shared RTL-simulator integrations when needed;
no placeholder simulator infrastructure is required.

Use `make -C models/noc test` for the existing deterministic router regression.
See `noc/README.md` for tool prerequisites, topology regressions and experiments.
The existing BookSim build/output behavior is retained in this relocation.
