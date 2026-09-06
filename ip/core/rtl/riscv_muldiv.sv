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
module riscv_muldiv (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        opcode_valid_i,
  input  logic [55:0] opcode_instr_i,
  input  logic [31:0] opcode_opcode_i,
  input  logic [31:0] opcode_pc_i,
  input  logic [ 4:0] opcode_rd_idx_i,
  input  logic [ 4:0] opcode_ra_idx_i,
  input  logic [ 4:0] opcode_rb_idx_i,
  input  logic [31:0] opcode_ra_operand_i,
  input  logic [31:0] opcode_rb_operand_i,
  output logic [ 4:0] writeback_idx_o,
  output logic        writeback_squash_o,
  output logic [31:0] writeback_value_o,
  output logic        stall_o
);



  //-----------------------------------------------------------------
  // Includes
  //-----------------------------------------------------------------
  import riscv_defs_pkg::*;

  //-------------------------------------------------------------
  // Registers / Wires
  //-------------------------------------------------------------

  logic [ 4:0] rd_q;
  logic [31:0] wb_result_q;
  logic [ 4:0] wb_rd_q;

  //-------------------------------------------------------------
  // Multiplier
  //-------------------------------------------------------------
  logic [64:0] mult_result_w;
  logic [32:0] operand_b;
  logic [32:0] operand_a;
  logic [31:0] result_r;
  logic [31:0] mult_result_q;
  logic        mult_busy_q;
  logic        mult_inst_w;
  assign mult_inst_w = opcode_instr_i[EnumInstMul]     ||
                      opcode_instr_i[EnumInstMulh]    ||
                      opcode_instr_i[EnumInstMulhsu]  ||
                      opcode_instr_i[EnumInstMulhu];


  // Multiplier takes 1 full cycle, with the result appearing on
  // writeback the cycle after...
  always_ff @(posedge clk_i)
    if (!rst_ni) mult_busy_q <= 1'b0;
    else if (opcode_valid_i & !stall_o) mult_busy_q <= mult_inst_w;
    else mult_busy_q <= 1'b0;

  always_comb begin
    if (opcode_instr_i[EnumInstMulhsu])
      operand_a = {opcode_ra_operand_i[31], opcode_ra_operand_i[31:0]};
    else if (opcode_instr_i[EnumInstMulh])
      operand_a = {opcode_ra_operand_i[31], opcode_ra_operand_i[31:0]};
    else  // ENUM_INST_MULHU || ENUM_INST_MUL
      operand_a = {1'b0, opcode_ra_operand_i[31:0]};
  end

  always_comb begin
    if (opcode_instr_i[EnumInstMulhsu]) operand_b = {1'b0, opcode_rb_operand_i[31:0]};
    else if (opcode_instr_i[EnumInstMulh])
      operand_b = {opcode_rb_operand_i[31], opcode_rb_operand_i[31:0]};
    else  // ENUM_INST_MULHU || ENUM_INST_MUL
      operand_b = {1'b0, opcode_rb_operand_i[31:0]};
  end

  assign mult_result_w = {{32{operand_a[32]}}, operand_a} * {{32{operand_b[32]}}, operand_b};

  always_comb begin
    result_r = mult_result_w[31:0];

    case (1'b1)
      opcode_instr_i[EnumInstMulh], opcode_instr_i[EnumInstMulhu], opcode_instr_i[EnumInstMulhsu]:
      result_r = mult_result_w[63:32];
      opcode_instr_i[EnumInstMul]: result_r = mult_result_w[31:0];
    endcase
  end

  always_ff @(posedge clk_i)
    if (!rst_ni) mult_result_q <= 32'b0;
    else mult_result_q <= result_r;

  //-------------------------------------------------------------
  // Divider
  //-------------------------------------------------------------
  logic div_rem_inst_w;
  assign div_rem_inst_w = opcode_instr_i[EnumInstDiv]  ||
                          opcode_instr_i[EnumInstDivu] ||
                          opcode_instr_i[EnumInstRem]  ||
                          opcode_instr_i[EnumInstRemu];
  logic signed_operation_w;
  assign signed_operation_w = opcode_instr_i[EnumInstDiv] || opcode_instr_i[EnumInstRem];
  logic div_operation_w;
  assign div_operation_w = opcode_instr_i[EnumInstDiv] || opcode_instr_i[EnumInstDivu];

  logic [31:0] dividend_q;
  logic [62:0] divisor_q;
  logic [31:0] quotient_q;
  logic [31:0] q_mask_q;
  logic        div_inst_q;
  logic        div_busy_q;
  logic        invert_res_q;
  logic        div_start_w;
  assign div_start_w = opcode_valid_i & div_rem_inst_w & !stall_o;
  logic div_complete_w;
  assign div_complete_w = !(|q_mask_q) & div_busy_q;

  always_ff @(posedge clk_i)
    if (!rst_ni) begin
      div_busy_q   <= 1'b0;
      dividend_q   <= 32'b0;
      divisor_q    <= 63'b0;
      invert_res_q <= 1'b0;
      quotient_q   <= 32'b0;
      q_mask_q     <= 32'b0;
      div_inst_q   <= 1'b0;
    end else if (div_start_w) begin
      div_busy_q <= 1'b1;
      div_inst_q <= div_operation_w;

      if (signed_operation_w && opcode_ra_operand_i[31]) dividend_q <= -opcode_ra_operand_i;
      else dividend_q <= opcode_ra_operand_i;

      if (signed_operation_w && opcode_rb_operand_i[31]) divisor_q <= {-opcode_rb_operand_i, 31'b0};
      else divisor_q <= {opcode_rb_operand_i, 31'b0};

      invert_res_q  <= (opcode_instr_i[EnumInstDiv] && (opcode_ra_operand_i[31] != opcode_rb_operand_i[31]) && |opcode_rb_operand_i) ||
                     (opcode_instr_i[EnumInstRem] && opcode_ra_operand_i[31]);

      quotient_q <= 32'b0;
      q_mask_q <= 32'h80000000;
    end else if (div_complete_w) begin
      div_busy_q <= 1'b0;
    end else if (div_busy_q) begin
      if (divisor_q <= {31'b0, dividend_q}) begin
        dividend_q <= dividend_q - divisor_q[31:0];
        quotient_q <= quotient_q | q_mask_q;
      end

      divisor_q <= {1'b0, divisor_q[62:1]};
      q_mask_q  <= {1'b0, q_mask_q[31:1]};
    end

  logic [31:0] div_result_r;
  always_comb begin
    div_result_r = 32'b0;

    if (div_inst_q) div_result_r = invert_res_q ? -quotient_q : quotient_q;
    else div_result_r = invert_res_q ? -dividend_q : dividend_q;
  end

  //-------------------------------------------------------------
  // Shared logic
  //-------------------------------------------------------------

  // Stall if divider logic is busy and new multiplier or divider op
  assign stall_o = (div_busy_q & (mult_inst_w | div_rem_inst_w)) || (mult_busy_q & div_rem_inst_w);


  always_ff @(posedge clk_i)
    if (!rst_ni) rd_q <= 5'b0;
    else if (opcode_valid_i && (div_rem_inst_w | mult_inst_w) && !stall_o) rd_q <= opcode_rd_idx_i;
    else if (!div_busy_q) rd_q <= 5'b0;

  always_ff @(posedge clk_i)
    if (!rst_ni) wb_rd_q <= 5'b0;
    else if (mult_busy_q) wb_rd_q <= rd_q;
    else if (div_complete_w) wb_rd_q <= rd_q;
    else wb_rd_q <= 5'b0;

  always_ff @(posedge clk_i)
    if (!rst_ni) wb_result_q <= 32'b0;
    else if (div_complete_w) wb_result_q <= div_result_r;
    else wb_result_q <= mult_result_q;

  assign writeback_value_o  = wb_result_q;
  assign writeback_idx_o    = wb_rd_q;
  assign writeback_squash_o = 1'b0;



endmodule
