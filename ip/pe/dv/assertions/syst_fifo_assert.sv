// SPDX-License-Identifier: Apache-2.0
`include "prim_assert.sv"
module syst_fifo_assert #(
  parameter int unsigned Capacity = 8,
  parameter int unsigned CountWidth = $clog2(Capacity+1),
  parameter bit InputFifo = 1'b1
) (
  input logic clk_i,
  input logic rst_ni,
  input logic [CountWidth-1:0] count_i,
  input logic [2:0] push_count_i,
  input logic [2:0] pop_count_i
);
  `ASSERT(CountBounds_A, int'(count_i) <= Capacity)
  `ASSERT(NoUnderflow_A, int'(pop_count_i) <= int'(count_i))
  `ASSERT(NoOverflow_A, int'(count_i)+int'(push_count_i)-int'(pop_count_i) <= Capacity)
  `ASSERT(LegalCounts_A, InputFifo ? (push_count_i inside {0,4} && pop_count_i <= 2) :
                                  (push_count_i <= 2 && pop_count_i inside {0,4}))
endmodule

bind syst_inf syst_fifo_assert #(.Capacity(NumEntries), .CountWidth(CountWidth))
  u_fifo_assert (.clk_i, .rst_ni, .count_i(count_q),
                 .push_count_i(push_i ? 3'd4 : 3'd0), .pop_count_i({1'b0,pop_i}));
bind syst_outf syst_fifo_assert #(.Capacity(NumEntries), .CountWidth(CountWidth), .InputFifo(0))
  u_fifo_assert (.clk_i, .rst_ni, .count_i(count_q),
                 .push_count_i({1'b0,push_i}), .pop_count_i(pop_i ? 3'd4 : 3'd0));
