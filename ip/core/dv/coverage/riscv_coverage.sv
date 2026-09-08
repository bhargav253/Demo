// SPDX-License-Identifier: Apache-2.0
// Observation bins at the external bus, not retirement or ISA coverage.
// Requests are gated by accept in this CPU. Observe accept-low cycles directly;
// request-high plus accept-low would be an unreachable ready/valid assumption.
module riscv_coverage (
  input logic clk_i,
  input logic rst_ni,
  input logic mem_i_valid_i,
  input logic [6:0] opcode_i,
  input logic mem_i_accept_i,
  input logic mem_d_rd_o,
  input logic [3:0] mem_d_wr_o,
  input logic mem_d_accept_i
);
  FetchLoad_C: cover property (@(posedge clk_i) rst_ni && mem_i_valid_i && opcode_i == 7'h03);
  FetchStore_C: cover property (@(posedge clk_i) rst_ni && mem_i_valid_i && opcode_i == 7'h23);
  FetchBranch_C: cover property (@(posedge clk_i) rst_ni && mem_i_valid_i && opcode_i == 7'h63);
  FetchJal_C: cover property (@(posedge clk_i) rst_ni && mem_i_valid_i && opcode_i == 7'h6f);
  FetchJalr_C: cover property (@(posedge clk_i) rst_ni && mem_i_valid_i && opcode_i == 7'h67);
  FetchRegisterAlu_C: cover property (@(posedge clk_i) rst_ni && mem_i_valid_i && opcode_i == 7'h33);
  FetchImmediateAlu_C: cover property (@(posedge clk_i) rst_ni && mem_i_valid_i && opcode_i == 7'h13);
  InstructionBackpressure_C: cover property (@(posedge clk_i) rst_ni && !mem_i_accept_i);
  DataBackpressure_C: cover property (@(posedge clk_i) rst_ni && !mem_d_accept_i);
  LoadAccepted_C: cover property (@(posedge clk_i) rst_ni && mem_d_rd_o && mem_d_accept_i);
  StoreAccepted_C: cover property (@(posedge clk_i) rst_ni && (|mem_d_wr_o) && mem_d_accept_i);
endmodule

bind riscv_core riscv_coverage u_coverage (
  .clk_i, .rst_ni, .mem_i_valid_i, .opcode_i(mem_i_inst_i[6:0]),
  .mem_i_accept_i, .mem_d_rd_o, .mem_d_wr_o, .mem_d_accept_i
);
