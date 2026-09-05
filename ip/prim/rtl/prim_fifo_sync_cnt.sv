// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Read/write pointer and occupancy logic for prim_fifo_sync.

`include "prim_assert.sv"

module prim_fifo_sync_cnt #(
  parameter int unsigned Depth = 4,
  parameter bit NeverClears = 1'b0,
  localparam int unsigned PtrW = prim_util_pkg::vbits(Depth),
  localparam int unsigned DepthW = prim_util_pkg::vbits(Depth + 1)
) (
  input  logic              clk_i,
  input  logic              rst_ni,
  input  logic              clr_i,
  input  logic              incr_wptr_i,
  input  logic              incr_rptr_i,
  output logic [PtrW-1:0]   wptr_o,
  output logic [PtrW-1:0]   rptr_o,
  output logic              full_o,
  output logic              empty_o,
  output logic [DepthW-1:0] depth_o
);

  localparam int unsigned WrapPtrW = PtrW + 1;

  logic [WrapPtrW-1:0] wptr_wrap_cnt_d;
  logic [WrapPtrW-1:0] wptr_wrap_cnt_q;
  logic [WrapPtrW-1:0] rptr_wrap_cnt_d;
  logic [WrapPtrW-1:0] rptr_wrap_cnt_q;
  logic                wptr_wrap;
  logic                rptr_wrap;

  assign wptr_o = wptr_wrap_cnt_q[PtrW-1:0];
  assign rptr_o = rptr_wrap_cnt_q[PtrW-1:0];

  assign wptr_wrap = incr_wptr_i && (wptr_o == PtrW'(Depth - 1));
  assign rptr_wrap = incr_rptr_i && (rptr_o == PtrW'(Depth - 1));

  always_comb begin
    wptr_wrap_cnt_d = wptr_wrap_cnt_q;
    if (wptr_wrap) begin
      wptr_wrap_cnt_d = {~wptr_wrap_cnt_q[WrapPtrW-1], {(WrapPtrW-1){1'b0}}};
    end else if (incr_wptr_i) begin
      wptr_wrap_cnt_d = wptr_wrap_cnt_q + WrapPtrW'(1);
    end

    rptr_wrap_cnt_d = rptr_wrap_cnt_q;
    if (rptr_wrap) begin
      rptr_wrap_cnt_d = {~rptr_wrap_cnt_q[WrapPtrW-1], {(WrapPtrW-1){1'b0}}};
    end else if (incr_rptr_i) begin
      rptr_wrap_cnt_d = rptr_wrap_cnt_q + WrapPtrW'(1);
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      wptr_wrap_cnt_q <= '0;
      rptr_wrap_cnt_q <= '0;
    end else if (clr_i) begin
      wptr_wrap_cnt_q <= '0;
      rptr_wrap_cnt_q <= '0;
    end else begin
      wptr_wrap_cnt_q <= wptr_wrap_cnt_d;
      rptr_wrap_cnt_q <= rptr_wrap_cnt_d;
    end
  end

  assign full_o =
      wptr_wrap_cnt_q == (rptr_wrap_cnt_q ^ {1'b1, {(WrapPtrW-1){1'b0}}});
  assign empty_o = wptr_wrap_cnt_q == rptr_wrap_cnt_q;

  assign depth_o = full_o ? DepthW'(Depth) :
      (wptr_wrap_cnt_q[WrapPtrW-1] == rptr_wrap_cnt_q[WrapPtrW-1]) ?
          DepthW'(wptr_o) - DepthW'(rptr_o) :
          DepthW'(Depth) - DepthW'(rptr_o) + DepthW'(wptr_o);

  `ASSERT_INIT(DepthValid_A, Depth > 1)
  `ASSERT(WriteWhenNotFull_A, incr_wptr_i |-> !full_o)
  `ASSERT(ReadWhenAvailable_A, incr_rptr_i |-> (!empty_o || incr_wptr_i))

  if (NeverClears) begin : gen_never_clears
    `ASSERT(NeverClears_A, !clr_i)
  end

endmodule : prim_fifo_sync_cnt
