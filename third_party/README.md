# External dependency identities

`sources.lock.json` pins ACT4 and generation-only tool versions/download hashes.
The ACT4 checkout's committed uv.lock and Gemfile.lock pin its transitive packages.
Downloaded archives are checked before extraction. These are dependency identities,
not copies of locally maintained Axon FuseSoC/Edalize sources.

`tools/env/riscv_testgen.py` owns the optional external setup procedure. Normal
HDL builds use `tools/env/bootstrap.py`; they never install ACT4/Sail or GCC.
The current generation tool binaries target Linux x86-64; other hosts need a
reviewed compatible environment and should not silently change the tool lock.

The customized BookSim source is intentionally retained under models/noc/booksim2
with its upstream base recorded in models/noc/BOOKSIM_REVISION.
