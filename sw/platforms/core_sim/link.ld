/* SPDX-License-Identifier: Apache-2.0 */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0x80000000, LENGTH = 1M }
SECTIONS {
  .text : { *(.text.init) *(.text*) } > ram
  .rodata : { *(.rodata*) *(.srodata*) } > ram
  .data : { *(.data*) *(.sdata*) } > ram
  .bss : { __bss_start = .; *(.bss*) *(.sbss*) *(COMMON); __bss_end = .; } > ram
  __stack_top = ORIGIN(ram) + LENGTH(ram);
}
