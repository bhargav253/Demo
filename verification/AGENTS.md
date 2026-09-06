# Shared verification integration

Read the suite README and explicit configuration before generating tests.
Do not infer full ISA compliance from a selected subset. Preserve exclusions and
reference-model semantics. Custom PE extensions need an independent specification
and oracle; standard I/M tests do not check them.
Run generators in explicit private external workspaces. Installed dependencies
are pinned by third_party/sources.lock.json. Do not hand-edit upstream generated
assembly. Use successful generation receipts for explicit binary publication.
Verify binary/configuration hashes and run the relevant suite after publication.
