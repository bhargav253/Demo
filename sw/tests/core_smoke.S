/* SPDX-License-Identifier: Apache-2.0 */
/* Directed bring-up, not an architectural certification test. */
.section .text.init
.globl _start
_start:
  la sp, __stack_top
  li t0, 7
  li t1, -3
  mul t2, t0, t1
  li t3, -21
  bne t2, t3, fail
  div t2, t3, t0
  bne t2, t1, fail
  rem t2, t3, t0
  bnez t2, fail
  div t2, t0, zero
  li t3, -1
  bne t2, t3, fail
  rem t2, t0, zero
  bne t2, t0, fail
  li t0, 0x80000000
  li t1, -1
  div t2, t0, t1
  bne t2, t0, fail
  rem t2, t0, t1
  bnez t2, fail
  la t0, scratch
  li t1, 0x89abcdef
  sw t1, 0(t0)
  lw t2, 0(t0)
  bne t1, t2, fail
  lb t2, 0(t0)
  li t3, -17
  bne t2, t3, fail
  lbu t2, 0(t0)
  li t3, 239
  bne t2, t3, fail
  lh t2, 2(t0)
  li t3, -30293
  bne t2, t3, fail
  li t1, 0x1234
  sh t1, 2(t0)
  lhu t2, 2(t0)
  bne t1, t2, fail
  li t1, 0x55
  sb t1, 1(t0)
  lbu t2, 1(t0)
  bne t1, t2, fail
  addi zero, zero, 1
  bnez zero, fail
  jal ra, subroutine
  li t3, 42
  bne a0, t3, fail
  li a0, 1
  j exit
subroutine:
  li a0, 42
  ret
fail:
  li a0, 3
exit:
  li t0, 0x10000000
  sw a0, 0(t0)
1: j 1b
.section .bss
.balign 4
scratch: .space 4
