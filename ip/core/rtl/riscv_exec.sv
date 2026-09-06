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
module riscv_exec (
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
  input  logic [31:0] reset_vector_i,
  output logic        branch_request_o,
  output logic [31:0] branch_pc_o,
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
  logic [ 4:0] rd_x_q;
  logic        reset_q;

  logic [ 3:0] alu_func_q;
  logic [31:0] alu_input_a_q;
  logic [31:0] alu_input_b_q;

  //-------------------------------------------------------------
  // Instances
  //-------------------------------------------------------------
  riscv_alu u_alu (
    .alu_op_i(alu_func_q),
    .alu_a_i (alu_input_a_q),
    .alu_b_i (alu_input_b_q),
    .alu_p_o (writeback_value_o)
  );

  //-------------------------------------------------------------
  // Opcode decode
  //-------------------------------------------------------------
  logic [31:0] imm20_r;
  logic [31:0] imm12_r;
  logic [31:0] bimm_r;
  logic [31:0] jimm20_r;
  logic [ 4:0] shamt_r;


  always_comb begin
    imm20_r = {opcode_opcode_i[31:12], 12'b0};
    imm12_r = {{20{opcode_opcode_i[31]}}, opcode_opcode_i[31:20]};
    bimm_r = {
      {19{opcode_opcode_i[31]}},
      opcode_opcode_i[31],
      opcode_opcode_i[7],
      opcode_opcode_i[30:25],
      opcode_opcode_i[11:8],
      1'b0
    };
    jimm20_r = {
      {12{opcode_opcode_i[31]}},
      opcode_opcode_i[19:12],
      opcode_opcode_i[20],
      opcode_opcode_i[30:25],
      opcode_opcode_i[24:21],
      1'b0
    };

    shamt_r = opcode_opcode_i[24:20];
  end

  //-------------------------------------------------------------
  // Execute - ALU operations
  //-------------------------------------------------------------
  logic [ 3:0] alu_func_d;
  logic [31:0] alu_input_a_d;
  logic [31:0] alu_input_b_d;
  logic        write_rd_r;

  always_comb begin
    alu_func_d    = AluNone;
    alu_input_a_d = 32'b0;
    alu_input_b_d = 32'b0;
    write_rd_r    = 1'b0;

    if (opcode_instr_i[EnumInstAdd]) // add
    begin
      alu_func_d    = AluAdd;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = opcode_rb_operand_i;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstAnd]) // and
    begin
      alu_func_d    = AluAnd;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = opcode_rb_operand_i;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstOr]) // or
    begin
      alu_func_d    = AluOr;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = opcode_rb_operand_i;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstSll]) // sll
    begin
      alu_func_d    = AluShiftl;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = opcode_rb_operand_i;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstSra]) // sra
    begin
      alu_func_d    = AluShiftrArith;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = opcode_rb_operand_i;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstSrl]) // srl
    begin
      alu_func_d    = AluShiftr;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = opcode_rb_operand_i;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstSub]) // sub
    begin
      alu_func_d    = AluSub;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = opcode_rb_operand_i;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstXor]) // xor
    begin
      alu_func_d    = AluXor;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = opcode_rb_operand_i;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstSlt]) // slt
    begin
      alu_func_d    = AluLessThanSigned;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = opcode_rb_operand_i;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstSltu]) // sltu
    begin
      alu_func_d    = AluLessThan;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = opcode_rb_operand_i;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstAddi]) // addi
    begin
      alu_func_d    = AluAdd;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = imm12_r;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstAndi]) // andi
    begin
      alu_func_d    = AluAnd;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = imm12_r;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstSlti]) // slti
    begin
      alu_func_d    = AluLessThanSigned;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = imm12_r;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstSltiu]) // sltiu
    begin
      alu_func_d    = AluLessThan;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = imm12_r;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstOri]) // ori
    begin
      alu_func_d    = AluOr;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = imm12_r;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstXori]) // xori
    begin
      alu_func_d    = AluXor;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = imm12_r;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstSlli]) // slli
    begin
      alu_func_d    = AluShiftl;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = {27'b0, shamt_r};
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstSrli]) // srli
    begin
      alu_func_d    = AluShiftr;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = {27'b0, shamt_r};
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstSrai]) // srai
    begin
      alu_func_d    = AluShiftrArith;
      alu_input_a_d = opcode_ra_operand_i;
      alu_input_b_d = {27'b0, shamt_r};
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstLui]) // lui
    begin
      alu_input_a_d = imm20_r;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstAuipc]) // auipc
    begin
      alu_func_d    = AluAdd;
      alu_input_a_d = opcode_pc_i;
      alu_input_b_d = imm20_r;
      write_rd_r    = 1'b1;
    end
    else if (opcode_instr_i[EnumInstJal] || opcode_instr_i[EnumInstJalr]) // jal, jalr
    begin
      alu_func_d    = AluAdd;
      alu_input_a_d = opcode_pc_i;
      alu_input_b_d = 32'd4;
      write_rd_r    = 1'b1;
    end
  end

  //-----------------------------------------------------------------
  // less_than_signed: Less than operator (signed)
  // Inputs: x = left operand, y = right operand
  // Return: (int)x < (int)y
  //-----------------------------------------------------------------
  function [0:0] less_than_signed;
    input [31:0] x;
    input [31:0] y;
    logic [31:0] v;
    begin
      v = (x - y);
      if (x[31] != y[31]) less_than_signed = x[31];
      else less_than_signed = v[31];
    end
  endfunction

  //-----------------------------------------------------------------
  // greater_than_signed: Greater than operator (signed)
  // Inputs: x = left operand, y = right operand
  // Return: (int)x > (int)y
  //-----------------------------------------------------------------
  function [0:0] greater_than_signed;
    input [31:0] x;
    input [31:0] y;
    logic [31:0] v;
    begin
      v = (y - x);
      if (x[31] != y[31]) greater_than_signed = y[31];
      else greater_than_signed = v[31];
    end
  endfunction

  //-------------------------------------------------------------
  // Execute - Branch operations
  //-------------------------------------------------------------
  logic        branch_r;
  logic [31:0] branch_target_r;

  always_comb begin
    branch_r        = 1'b0;

    // Default branch_r target is relative to current PC
    branch_target_r = opcode_pc_i + bimm_r;

    if (reset_q) begin
      branch_r        = 1'b1;
      branch_target_r = reset_vector_i;
    end
    else if (opcode_instr_i[EnumInstJal]) // jal
    begin
      branch_r        = 1'b1;
      branch_target_r = opcode_pc_i + jimm20_r;
    end
    else if (opcode_instr_i[EnumInstJalr]) // jalr
    begin
      branch_r           = 1'b1;
      branch_target_r    = opcode_ra_operand_i + imm12_r;
      branch_target_r[0] = 1'b0;
    end else if (opcode_instr_i[EnumInstBeq])  // beq
      branch_r = (opcode_ra_operand_i == opcode_rb_operand_i);
    else if (opcode_instr_i[EnumInstBne])  // bne
      branch_r = (opcode_ra_operand_i != opcode_rb_operand_i);
    else if (opcode_instr_i[EnumInstBlt])  // blt
      branch_r = less_than_signed(opcode_ra_operand_i, opcode_rb_operand_i);
    else if (opcode_instr_i[EnumInstBge])  // bge
      branch_r = greater_than_signed(
        opcode_ra_operand_i, opcode_rb_operand_i
      ) | (opcode_ra_operand_i == opcode_rb_operand_i);
    else if (opcode_instr_i[EnumInstBltu])  // bltu
      branch_r = (opcode_ra_operand_i < opcode_rb_operand_i);
    else if (opcode_instr_i[EnumInstBgeu])  // bgeu
      branch_r = (opcode_ra_operand_i >= opcode_rb_operand_i);
  end

  assign branch_request_o = branch_r && (opcode_valid_i || reset_q);
  assign branch_pc_o      = branch_target_r;

  //-------------------------------------------------------------
  // Sequential
  //-------------------------------------------------------------
  always_ff @(posedge clk_i)
    if (!rst_ni) begin
      rd_x_q        <= 5'b0;
      reset_q       <= 1'b1;
      alu_func_q    <= AluNone;
      alu_input_a_q <= 32'b0;
      alu_input_b_q <= 32'b0;
    end else begin
      reset_q       <= 1'b0;

      alu_func_q    <= alu_func_d;
      alu_input_a_q <= alu_input_a_d;
      alu_input_b_q <= alu_input_b_d;

      if (opcode_valid_i && write_rd_r) rd_x_q <= opcode_rd_idx_i;
      else rd_x_q <= 5'b0;
    end

  //-------------------------------------------------------------
  // Outputs
  //-------------------------------------------------------------
  assign writeback_idx_o    = rd_x_q;
  assign writeback_squash_o = 1'b0;
  assign stall_o            = 1'b0;  // Not used

endmodule
