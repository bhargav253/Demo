// SPDX-License-Identifier: Apache-2.0
#ifndef AXON_RVMODEL_MACROS_H
#define AXON_RVMODEL_MACROS_H
// The legacy DUT starts in M-mode. Do not execute an unsupported privilege switch.
#define RVMODEL_BOOT_TO_MMODE
#define RVMODEL_HALT_PASS li t0, 0x10000000; li t1, 1; sw t1, 0(t0); 1: j 1b;
#define RVMODEL_HALT_FAIL li t0, 0x10000000; li t1, 3; sw t1, 0(t0); 1: j 1b;
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) \
  li _R2, 0x10000004; \
  991: lbu _R1, 0(_STR_PTR); beqz _R1, 992f; \
  sb _R1, 0(_R2); addi _STR_PTR, _STR_PTR, 1; j 991b; 992:
// This platform is restricted to the I/M suite; interrupt tests are excluded.
#define RVMODEL_DATA_SECTION
#define RVMODEL_INTERRUPT_LATENCY 0
#define RVMODEL_TIMER_INT_SOON_DELAY 0
#define RVMODEL_SET_MEXT_INT(_R1, _R2)
#define RVMODEL_CLR_MEXT_INT(_R1, _R2)
#define RVMODEL_SET_MSW_INT(_R1, _R2)
#define RVMODEL_CLR_MSW_INT(_R1, _R2)
#define RVMODEL_SET_SEXT_INT(_R1, _R2)
#define RVMODEL_CLR_SEXT_INT(_R1, _R2)
#define RVMODEL_SET_SSW_INT(_R1, _R2)
#define RVMODEL_CLR_SSW_INT(_R1, _R2)
#endif
