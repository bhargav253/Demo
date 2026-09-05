// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Configurable saturating counter.
//
// Clear has priority over set, followed by increment or decrement. Asserting
// increment and decrement together leaves the counter unchanged. The proposed
// value is always visible on cnt_after_commit_o; commit_i controls whether that
// value is stored.

`include "prim_assert.sv"

module prim_count #(
  parameter int unsigned Width = 2,
  parameter logic [Width-1:0] ResetValue = '0
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             clr_i,
  input  logic             set_i,
  input  logic [Width-1:0] set_cnt_i,
  input  logic             incr_en_i,
  input  logic             decr_en_i,
  input  logic [Width-1:0] step_i,
  input  logic             commit_i,
  output logic [Width-1:0] cnt_o,
  output logic [Width-1:0] cnt_after_commit_o
);

  localparam logic [Width-1:0] MaxValue = '1;

  logic [Width-1:0] cnt_d;
  logic [Width-1:0] cnt_q;
  logic [Width:0]   incremented;

  assign incremented = {1'b0, cnt_q} + {1'b0, step_i};

  always_comb begin
    cnt_d = cnt_q;

    if (clr_i) begin
      cnt_d = ResetValue;
    end else if (set_i) begin
      cnt_d = set_cnt_i;
    end else if (incr_en_i && !decr_en_i) begin
      cnt_d = incremented[Width] ? MaxValue : incremented[Width-1:0];
    end else if (decr_en_i && !incr_en_i) begin
      cnt_d = (cnt_q < step_i) ? '0 : cnt_q - step_i;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      cnt_q <= ResetValue;
    end else if (commit_i) begin
      cnt_q <= cnt_d;
    end
  end

  assign cnt_o = cnt_q;
  assign cnt_after_commit_o = cnt_d;

  `ASSERT_INIT(WidthValid_A, Width > 0)
  `ASSERT_KNOWN(CountKnown_A, cnt_o)

endmodule : prim_count
