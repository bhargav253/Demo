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
module riscv_alu (
  input  logic [ 3:0] alu_op_i,
  input  logic [31:0] alu_a_i,
  input  logic [31:0] alu_b_i,
  output logic [31:0] alu_p_o
);



  //-----------------------------------------------------------------
  // Includes
  //-----------------------------------------------------------------
  import riscv_defs_pkg::*;

  //-----------------------------------------------------------------
  // Registers
  //-----------------------------------------------------------------
  logic [ 31:0] result_r;

  logic [31:16] shift_right_fill_r;
  logic [ 31:0] shift_right_1_r;
  logic [ 31:0] shift_right_2_r;
  logic [ 31:0] shift_right_4_r;
  logic [ 31:0] shift_right_8_r;

  logic [ 31:0] shift_left_1_r;
  logic [ 31:0] shift_left_2_r;
  logic [ 31:0] shift_left_4_r;
  logic [ 31:0] shift_left_8_r;
  logic [ 31:0] sub_res_w;
  assign sub_res_w = alu_a_i - alu_b_i;

  //-----------------------------------------------------------------
  // ALU
  //-----------------------------------------------------------------
  always_comb begin

    shift_right_fill_r = '0;
    shift_right_1_r = '0;
    shift_right_2_r = '0;
    shift_right_4_r = '0;
    shift_right_8_r = '0;

    shift_left_1_r = '0;
    shift_left_2_r = '0;
    shift_left_4_r = '0;
    shift_left_8_r = '0;


    case (alu_op_i)
      //----------------------------------------------
      // Shift Left
      //----------------------------------------------
      AluShiftl: begin
        if (alu_b_i[0] == 1'b1) shift_left_1_r = {alu_a_i[30:0], 1'b0};
        else shift_left_1_r = alu_a_i;

        if (alu_b_i[1] == 1'b1) shift_left_2_r = {shift_left_1_r[29:0], 2'b00};
        else shift_left_2_r = shift_left_1_r;

        if (alu_b_i[2] == 1'b1) shift_left_4_r = {shift_left_2_r[27:0], 4'b0000};
        else shift_left_4_r = shift_left_2_r;

        if (alu_b_i[3] == 1'b1) shift_left_8_r = {shift_left_4_r[23:0], 8'b00000000};
        else shift_left_8_r = shift_left_4_r;

        if (alu_b_i[4] == 1'b1) result_r = {shift_left_8_r[15:0], 16'b0000000000000000};
        else result_r = shift_left_8_r;
      end
      //----------------------------------------------
      // Shift Right
      //----------------------------------------------
      AluShiftr, AluShiftrArith: begin
        // Arithmetic shift? Fill with 1's if MSB set
        if (alu_a_i[31] == 1'b1 && alu_op_i == AluShiftrArith)
          shift_right_fill_r = 16'b1111111111111111;
        else shift_right_fill_r = 16'b0000000000000000;

        if (alu_b_i[0] == 1'b1) shift_right_1_r = {shift_right_fill_r[31], alu_a_i[31:1]};
        else shift_right_1_r = alu_a_i;

        if (alu_b_i[1] == 1'b1)
          shift_right_2_r = {shift_right_fill_r[31:30], shift_right_1_r[31:2]};
        else shift_right_2_r = shift_right_1_r;

        if (alu_b_i[2] == 1'b1)
          shift_right_4_r = {shift_right_fill_r[31:28], shift_right_2_r[31:4]};
        else shift_right_4_r = shift_right_2_r;

        if (alu_b_i[3] == 1'b1)
          shift_right_8_r = {shift_right_fill_r[31:24], shift_right_4_r[31:8]};
        else shift_right_8_r = shift_right_4_r;

        if (alu_b_i[4] == 1'b1) result_r = {shift_right_fill_r[31:16], shift_right_8_r[31:16]};
        else result_r = shift_right_8_r;
      end
      //----------------------------------------------
      // Arithmetic
      //----------------------------------------------
      AluAdd: begin
        result_r = (alu_a_i + alu_b_i);
      end
      AluSub: begin
        result_r = sub_res_w;
      end
      //----------------------------------------------
      // Logical
      //----------------------------------------------
      AluAnd: begin
        result_r = (alu_a_i & alu_b_i);
      end
      AluOr: begin
        result_r = (alu_a_i | alu_b_i);
      end
      AluXor: begin
        result_r = (alu_a_i ^ alu_b_i);
      end
      //----------------------------------------------
      // Comparision
      //----------------------------------------------
      AluLessThan: begin
        result_r = (alu_a_i < alu_b_i) ? 32'h1 : 32'h0;
      end
      AluLessThanSigned: begin
        if (alu_a_i[31] != alu_b_i[31]) result_r = alu_a_i[31] ? 32'h1 : 32'h0;
        else result_r = sub_res_w[31] ? 32'h1 : 32'h0;
      end
      default: begin
        result_r = alu_a_i;
      end
    endcase
  end

  assign alu_p_o = result_r;


endmodule
