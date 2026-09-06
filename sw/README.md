# Firmware source

`platforms/core_sim/link.ld` and `tests/core_smoke.S` are the current bare-metal
bring-up firmware. Startup is embedded in that assembly test. No general C
runtime, orchestrator firmware, PE driver, or tensor compiler exists yet.

With a RISC-V compiler available, from the repository root:

```bash
mkdir -p build/firmware/core_smoke
riscv-none-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles \
  -Wl,--no-relax -T sw/platforms/core_sim/link.ld sw/tests/core_smoke.S \
  -o build/firmware/core_smoke/smoke.elf
python3 tools/verification/run_firmware.py build/firmware/core_smoke/smoke.elf
```

The existing prebuilt smoke test needs no cross-compiler:

```bash
python3 tools/verification/run_firmware.py --manifest prebuilt/firmware/core_smoke/manifest.json
```

As platforms develop, place their startup/linker support under platforms/;
share runtime code, drivers and kernels only when that source actually exists.
A separate firmware role does not imply a separate compiler or CPU RTL copy.
