# Source ownership and platform structure

The monorepo retains the recipes and contracts needed to reproduce a result.
Installed tools and temporary generator output are not tracked source.

| Location | Owns |
| --- | --- |
| ip/ | Reusable RTL, FuseSoC graphs and block-local DV |
| models/ | Architectural/performance models, including customized BookSim |
| platforms/ | Named integration manifests connecting hardware and software |
| sw/ | Firmware source, platform support, future drivers/kernels |
| verification/ | Shared suite integration, profiles and explicit scope |
| prebuilt/ | Selected executable test deliverables and provenance |
| third_party/ | Dependency identities and installation/source recipes |
| tools/ | Shared setup, generation, execution and reporting |
| build/, artifacts/ | Ignored builds and unique evidence |

The implemented platform is `core_sim`. Its manifest links to authoritative
memory documentation/implementation, linker and test configs; it does not
repeat memory addresses in another independent schema. The current linkers and
C++ model are manually maintained under that documented contract. Automatic
memory-map generation is future work, not an implemented source-of-truth claim.

Orchestrator and PE tile are future platforms. They may reuse one CPU RTL
implementation with different memories/peripherals and firmware. Create CPU
variants only when implementation behavior differs. Custom instruction semantics,
accelerator command descriptors, arithmetic rules and completion guarantees need
explicit specifications before their software and DV are added.

`models/noc` is a standalone BookSim model; RTL simulation stays with IP DV.
The old `sim/noc` path is retired. The NoC model's in-tree compilation and ignored
results directory are preserved as a legacy workflow; no model behavior changed.

Root and scoped AGENTS.md files describe navigation and required checks.
Architecture facts belong in specifications and machine-readable configs.
Every firmware result should identify platform, suite, source/tool versions,
input hashes, command/seed, and log/wave location. The current I/M suite is not
full privileged certification; retain its documented omissions.
