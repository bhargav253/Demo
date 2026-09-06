# Firmware development

Read README.md and the selected platforms/<name> support before modifying code.
Use the corresponding root platforms/<name>/platform.json for RTL/verification
links. Architecture and memory contracts are authoritative; do not guess register
addresses or duplicate opcode definitions independently of their specification.

Build firmware into build/ or an external workspace. Normal compilation must not
replace prebuilt/. Run the resulting ELF through tools/verification/run_firmware.py.
Changing linker, startup or command interfaces needs matching integration tests.
The current core_smoke is an assembly-only runtime; do not assume libc, an OS,
interrupt support or a generic C startup has already been implemented.
