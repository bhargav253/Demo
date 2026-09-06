// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`ifndef PRIM_FLOP_MACROS_SV
`define PRIM_FLOP_MACROS_SV

/////////////////////////////////////
// Default Values for Macros below //
/////////////////////////////////////

`define PRIM_FLOP_CLK clk_i
`define PRIM_FLOP_RST rst_ni
`define PRIM_FLOP_RESVAL '0

/////////////////////
// Register Macros //
/////////////////////

// Register with synchronous active-low reset.
`define PRIM_FLOP_A(__d, __q, __resval = `PRIM_FLOP_RESVAL, __clk = `PRIM_FLOP_CLK, __rst_n = `PRIM_FLOP_RST) \
  always_ff @(posedge __clk) begin                   \
    if (!__rst_n) begin                               \
      __q <= __resval;                                \
    end else begin                                    \
      __q <= __d;                                     \
    end                                               \
  end

`endif // PRIM_FLOP_MACROS_SV
