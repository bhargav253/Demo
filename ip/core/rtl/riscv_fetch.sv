// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------
//                         RISC-V Core
//                            V0.9
//                     Ultra-Embedded.com
//                     Copyright 2014-2018
//
//                   admin@ultra-embedded.com
//
//                       License: BSD
//-----------------------------------------------------------------
//
// Copyright (c) 2014-2018, Ultra-Embedded.com
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
//   - Redistributions of source code must retain the above copyright
//     notice, this list of conditions and the following disclaimer.
//   - Redistributions in binary form must reproduce the above copyright
//     notice, this list of conditions and the following disclaimer
//     in the documentation and/or other materials provided with the
//     distribution.
//   - Neither the name of the author nor the names of its contributors
//     may be used to endorse or promote products derived from this
//     software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
// LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
// THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
// SUCH DAMAGE.
//-----------------------------------------------------------------
module riscv_fetch (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        fetch_branch_i,
  input  logic [31:0] fetch_branch_pc_i,
  input  logic        fetch_accept_i,
  input  logic        icache_accept_i,
  input  logic        icache_valid_i,
  input  logic        icache_error_i,
  input  logic [31:0] icache_inst_i,
  input  logic [31:0] icache_inst_pc_i,
  output logic        fetch_valid_o,
  output logic [31:0] fetch_instr_o,
  output logic [31:0] fetch_pc_o,
  output logic        icache_rd_o,
  output logic        icache_flush_o,
  output logic        icache_invalidate_o,
  output logic [31:0] icache_pc_o
);



  //-----------------------------------------------------------------
  // Includes
  //-----------------------------------------------------------------
  import riscv_defs_pkg::*;

  //-------------------------------------------------------------
  // Registers / Wires
  //-------------------------------------------------------------
  logic        active_q;
  logic [31:0] fetch_pc_q;

  logic [31:0] branch_pc_q;
  logic        branch_valid_q;

  logic        icache_fetch_q;

  logic [63:0] skid_buffer_q;
  logic        skid_valid_q;
  logic        icache_busy_w;
  assign icache_busy_w = icache_fetch_q && !icache_valid_i;
  logic stall_w;
  assign stall_w = !fetch_accept_i || icache_busy_w || !icache_accept_i;
  logic branch_w;
  assign branch_w = branch_valid_q || fetch_branch_i;
  logic [31:0] branch_pc_w;
  assign branch_pc_w = (branch_valid_q & !fetch_branch_i) ? branch_pc_q : fetch_branch_pc_i;

  //-------------------------------------------------------------
  // Sequential
  //-------------------------------------------------------------
  always_ff @(posedge clk_i)
    if (!rst_ni) begin
      fetch_pc_q     <= 32'b0;

      branch_pc_q    <= 32'b0;
      branch_valid_q <= 1'b0;

      icache_fetch_q <= 1'b0;

      skid_buffer_q  <= 64'b0;
      skid_valid_q   <= 1'b0;
      active_q       <= 1'b0;
    end else begin
      // Branch request skid buffer
      if (stall_w || !active_q) begin
        branch_valid_q <= branch_w;
        branch_pc_q    <= branch_pc_w;
      end else begin
        branch_valid_q <= 1'b0;
        branch_pc_q    <= 32'b0;
      end

      if (branch_w) active_q <= 1'b1;

      // NPC
      if (!stall_w) fetch_pc_q <= icache_pc_o + 32'd4;

      // Instruction output back-pressured - hold in skid buffer
      if (fetch_valid_o && !fetch_accept_i) begin
        skid_valid_q  <= 1'b1;
        skid_buffer_q <= {fetch_pc_o, fetch_instr_o};
      end else begin
        skid_valid_q  <= 1'b0;
        skid_buffer_q <= 64'b0;
      end

      // ICACHE fetch tracking
      if (icache_rd_o && icache_accept_i) icache_fetch_q <= 1'b1;
      else if (icache_valid_i) icache_fetch_q <= 1'b0;

    end

  //-------------------------------------------------------------
  // Outputs
  //-------------------------------------------------------------
  assign icache_rd_o         = active_q & !stall_w;
  assign icache_pc_o         = branch_w ? branch_pc_w : fetch_pc_q;
  assign icache_flush_o      = 1'b0;
  assign icache_invalidate_o = 1'b0;

  // On fault, insert known invalid opcode into the pipeline
  logic [31:0] instruction_w;
  assign instruction_w = icache_error_i ? InstFault : icache_inst_i;

  assign fetch_valid_o = (icache_valid_i || skid_valid_q) & !branch_w;
  assign fetch_pc_o    = skid_valid_q ? skid_buffer_q[63:32] : icache_inst_pc_i;
  assign fetch_instr_o = skid_valid_q ? skid_buffer_q[31:0]  : instruction_w;



endmodule
