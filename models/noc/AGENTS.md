# NoC architectural model

Read README.md and BOOKSIM_REVISION. This is the locally customized BookSim
architecture model, not the RTL implementation under ip/noc.
The source paths and scripts are relative to this directory.

For model changes, run the relevant Make targets from README.md; `make test`
checks the base router. Topology changes additionally require the corresponding
`test-noc12`, `test-noc16`, or `test-noc16c` target. Preserve deterministic seeds
and model assumptions. Do not interpret model statistics as RTL coverage.
Do not replace the customized booksim2 tree with a fresh upstream checkout.
The inherited flow builds in booksim2/src and retains ignored results/ output;
this is a documented legacy exception to the newer build/artifact layout.
