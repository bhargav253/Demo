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
module riscv_decode (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        fetch_valid_i,
  input  logic [31:0] fetch_instr_i,
  input  logic [31:0] fetch_pc_i,
  input  logic        branch_request_i,
  input  logic [31:0] branch_pc_i,
  input  logic        branch_csr_request_i,
  input  logic [31:0] branch_csr_pc_i,
  input  logic [ 4:0] writeback_exec_idx_i,
  input  logic        writeback_exec_squash_i,
  input  logic [31:0] writeback_exec_value_i,
  input  logic [ 4:0] writeback_mem_idx_i,
  input  logic        writeback_mem_squash_i,
  input  logic [31:0] writeback_mem_value_i,
  input  logic [ 4:0] writeback_csr_idx_i,
  input  logic        writeback_csr_squash_i,
  input  logic [31:0] writeback_csr_value_i,
  input  logic [ 4:0] writeback_muldiv_idx_i,
  input  logic        writeback_muldiv_squash_i,
  input  logic [31:0] writeback_muldiv_value_i,
  input  logic        exec_stall_i,
  input  logic        lsu_stall_i,
  input  logic        csr_stall_i,
  input  logic        muldiv_stall_i,
  output logic        fetch_branch_o,
  output logic [31:0] fetch_branch_pc_o,
  output logic        fetch_accept_o,
  output logic        exec_opcode_valid_o,
  output logic        lsu_opcode_valid_o,
  output logic        csr_opcode_valid_o,
  output logic        muldiv_opcode_valid_o,
  output logic [55:0] opcode_instr_o,
  output logic [31:0] opcode_opcode_o,
  output logic [31:0] opcode_pc_o,
  output logic [ 4:0] opcode_rd_idx_o,
  output logic [ 4:0] opcode_ra_idx_o,
  output logic [ 4:0] opcode_rb_idx_o,
  output logic [31:0] opcode_ra_operand_o,
  output logic [31:0] opcode_rb_operand_o
);



  //-----------------------------------------------------------------
  // Includes
  //-----------------------------------------------------------------
  import riscv_defs_pkg::*;

  //-------------------------------------------------------------
  // Registers / Wires
  //-------------------------------------------------------------
  logic        valid_q;
  logic [31:0] pc_q;
  logic [31:0] inst_q;

  logic [31:0] scoreboard_q;
  logic        stall_scoreboard_r;

  logic [31:0] ra_value_w;
  logic [31:0] rb_value_w;

  logic        stall_input_w;
  assign stall_input_w = stall_scoreboard_r || exec_stall_i || lsu_stall_i || csr_stall_i || muldiv_stall_i;

  //-------------------------------------------------------------
  // Instances
  //-------------------------------------------------------------
  logic [4:0] wb_exec_rd_w;
  assign wb_exec_rd_w = writeback_exec_idx_i & {5{~writeback_exec_squash_i}};
  logic [4:0] wb_mem_rd_w;
  assign wb_mem_rd_w = writeback_mem_idx_i & {5{~writeback_mem_squash_i}};
  logic [4:0] wb_csr_rd_w;
  assign wb_csr_rd_w = writeback_csr_idx_i & {5{~writeback_csr_squash_i}};
  logic [4:0] wb_muldiv_rd_w;
  assign wb_muldiv_rd_w = writeback_muldiv_idx_i & {5{~writeback_muldiv_squash_i}};


  logic [ 4:0] wb_rd_r;
  logic [31:0] wb_res_r;

  always_comb begin
    wb_rd_r  = wb_exec_rd_w;
    wb_res_r = writeback_exec_value_i;

  end

  riscv_regfile u_regfile (
    .clk_i (clk_i),
    .rst_ni(rst_ni),

    // Write ports
    .rd0_i(wb_rd_r),
    .rd0_value_i(wb_res_r),
    .rd1_i(wb_mem_rd_w),
    .rd1_value_i(writeback_mem_value_i),
    .rd2_i(wb_csr_rd_w),
    .rd2_value_i(writeback_csr_value_i),
    .rd3_i(wb_muldiv_rd_w),
    .rd3_value_i(writeback_muldiv_value_i),

    // Read ports
    .ra_i(opcode_ra_idx_o),
    .rb_i(opcode_rb_idx_o),
    .ra_value_o(ra_value_w),
    .rb_value_o(rb_value_w)
  );

  //-------------------------------------------------------------
  // Instruction Register
  //-------------------------------------------------------------
  always_ff @(posedge clk_i)
    if (!rst_ni) begin
      valid_q <= 1'b0;
      pc_q    <= 32'b0;
      inst_q  <= 32'b0;
    end  // Branch request
    else if (branch_request_i || branch_csr_request_i) begin
      valid_q <= 1'b0;

      if (branch_csr_request_i) pc_q <= branch_csr_pc_i;
      else  /*if (branch_request_i)*/
        pc_q <= branch_pc_i;

      inst_q <= 32'b0;
    end  // Normal operation - decode not stalled
    else if (!stall_input_w) begin
      valid_q <= fetch_valid_i;

      if (fetch_valid_i) pc_q <= fetch_pc_i;
      // Current instruction accepted, increment PC to unexecuted instruction
      else if (valid_q) pc_q <= pc_q + 32'd4;

      inst_q <= fetch_instr_i;
    end

  //-------------------------------------------------------------
  // Scoreboard Register
  //-------------------------------------------------------------
  logic [31:0] scoreboard_d;
  logic sb_alloc_w;
  assign sb_alloc_w = (opcode_instr_o[EnumInstLb]     ||
                   opcode_instr_o[EnumInstLh]     ||
                   opcode_instr_o[EnumInstLw]     ||
                   opcode_instr_o[EnumInstLbu]    ||
                   opcode_instr_o[EnumInstLhu]    ||
                   opcode_instr_o[EnumInstLwu]    ||
                   opcode_instr_o[EnumInstCsrrw]  ||
                   opcode_instr_o[EnumInstCsrrs]  ||
                   opcode_instr_o[EnumInstCsrrc]  ||
                   opcode_instr_o[EnumInstCsrrwi] ||
                   opcode_instr_o[EnumInstCsrrsi] ||
                   opcode_instr_o[EnumInstCsrrci] ||
                   opcode_instr_o[EnumInstMul]    ||
                   opcode_instr_o[EnumInstMulh]   ||
                   opcode_instr_o[EnumInstMulhsu] ||
                   opcode_instr_o[EnumInstMulhu]  ||
                   opcode_instr_o[EnumInstDiv]    ||
                   opcode_instr_o[EnumInstDivu]   ||
                   opcode_instr_o[EnumInstRem]    ||
                   opcode_instr_o[EnumInstRemu] );


  always_comb begin
    scoreboard_d = scoreboard_q;

    scoreboard_d[writeback_mem_idx_i]    = 1'b0;

    // Allocate register in scoreboard
    if (sb_alloc_w && exec_opcode_valid_o && lsu_opcode_valid_o && csr_opcode_valid_o && muldiv_opcode_valid_o)
    begin
      scoreboard_d[opcode_rd_idx_o] = 1'b1;
    end

    // Release register on Load / CSR completion
    scoreboard_d[writeback_csr_idx_i]    = 1'b0;
    scoreboard_d[writeback_muldiv_idx_i] = 1'b0;
  end

  always_ff @(posedge clk_i)
    if (!rst_ni) scoreboard_q <= 32'b0;
    else scoreboard_q <= {scoreboard_d[31:1], 1'b0};

  //-------------------------------------------------------------
  // Instruction Decode
  //-------------------------------------------------------------
  assign opcode_instr_o[EnumInstAndi]   = ((inst_q & InstAndiMask) == InstAndi);  // andi
  assign opcode_instr_o[EnumInstAddi]   = ((inst_q & InstAddiMask) == InstAddi);  // addi
  assign opcode_instr_o[EnumInstSlti]   = ((inst_q & InstSltiMask) == InstSlti);  // slti
  assign opcode_instr_o[EnumInstSltiu]  = ((inst_q & InstSltiuMask) == InstSltiu);  // sltiu
  assign opcode_instr_o[EnumInstOri]    = ((inst_q & InstOriMask) == InstOri);  // ori
  assign opcode_instr_o[EnumInstXori]   = ((inst_q & InstXoriMask) == InstXori);  // xori
  assign opcode_instr_o[EnumInstSlli]   = ((inst_q & InstSlliMask) == InstSlli);  // slli
  assign opcode_instr_o[EnumInstSrli]   = ((inst_q & InstSrliMask) == InstSrli);  // srli
  assign opcode_instr_o[EnumInstSrai]   = ((inst_q & InstSraiMask) == InstSrai);  // srai
  assign opcode_instr_o[EnumInstLui]    = ((inst_q & InstLuiMask) == InstLui);  // lui
  assign opcode_instr_o[EnumInstAuipc]  = ((inst_q & InstAuipcMask) == InstAuipc);  // auipc
  assign opcode_instr_o[EnumInstAdd]    = ((inst_q & InstAddMask) == InstAdd);  // add
  assign opcode_instr_o[EnumInstSub]    = ((inst_q & InstSubMask) == InstSub);  // sub
  assign opcode_instr_o[EnumInstSlt]    = ((inst_q & InstSltMask) == InstSlt);  // slt
  assign opcode_instr_o[EnumInstSltu]   = ((inst_q & InstSltuMask) == InstSltu);  // sltu
  assign opcode_instr_o[EnumInstXor]    = ((inst_q & InstXorMask) == InstXor);  // xor
  assign opcode_instr_o[EnumInstOr]     = ((inst_q & InstOrMask) == InstOr);  // or
  assign opcode_instr_o[EnumInstAnd]    = ((inst_q & InstAndMask) == InstAnd);  // and
  assign opcode_instr_o[EnumInstSll]    = ((inst_q & InstSllMask) == InstSll);  // sll
  assign opcode_instr_o[EnumInstSrl]    = ((inst_q & InstSrlMask) == InstSrl);  // srl
  assign opcode_instr_o[EnumInstSra]    = ((inst_q & InstSraMask) == InstSra);  // sra
  assign opcode_instr_o[EnumInstJal]    = ((inst_q & InstJalMask) == InstJal);  // jal
  assign opcode_instr_o[EnumInstJalr]   = ((inst_q & InstJalrMask) == InstJalr);  // jalr
  assign opcode_instr_o[EnumInstBeq]    = ((inst_q & InstBeqMask) == InstBeq);  // beq
  assign opcode_instr_o[EnumInstBne]    = ((inst_q & InstBneMask) == InstBne);  // bne
  assign opcode_instr_o[EnumInstBlt]    = ((inst_q & InstBltMask) == InstBlt);  // blt
  assign opcode_instr_o[EnumInstBge]    = ((inst_q & InstBgeMask) == InstBge);  // bge
  assign opcode_instr_o[EnumInstBltu]   = ((inst_q & InstBltuMask) == InstBltu);  // bltu
  assign opcode_instr_o[EnumInstBgeu]   = ((inst_q & InstBgeuMask) == InstBgeu);  // bgeu
  assign opcode_instr_o[EnumInstLb]     = ((inst_q & InstLbMask) == InstLb);  // lb
  assign opcode_instr_o[EnumInstLh]     = ((inst_q & InstLhMask) == InstLh);  // lh
  assign opcode_instr_o[EnumInstLw]     = ((inst_q & InstLwMask) == InstLw);  // lw
  assign opcode_instr_o[EnumInstLbu]    = ((inst_q & InstLbuMask) == InstLbu);  // lbu
  assign opcode_instr_o[EnumInstLhu]    = ((inst_q & InstLhuMask) == InstLhu);  // lhu
  assign opcode_instr_o[EnumInstLwu]    = ((inst_q & InstLwuMask) == InstLwu);  // lwu
  assign opcode_instr_o[EnumInstSb]     = ((inst_q & InstSbMask) == InstSb);  // sb
  assign opcode_instr_o[EnumInstSh]     = ((inst_q & InstShMask) == InstSh);  // sh
  assign opcode_instr_o[EnumInstSw]     = ((inst_q & InstSwMask) == InstSw);  // sw
  assign opcode_instr_o[EnumInstEcall]  = ((inst_q & InstEcallMask) == InstEcall);  // ecall
  assign opcode_instr_o[EnumInstEbreak] = ((inst_q & InstEbreakMask) == InstEbreak);  // ebreak
  assign opcode_instr_o[EnumInstEret]   = ((inst_q & InstMretMask) == InstMret);  // mret / sret
  assign opcode_instr_o[EnumInstCsrrw]  = ((inst_q & InstCsrrwMask) == InstCsrrw);  // csrrw
  assign opcode_instr_o[EnumInstCsrrs]  = ((inst_q & InstCsrrsMask) == InstCsrrs);  // csrrs
  assign opcode_instr_o[EnumInstCsrrc]  = ((inst_q & InstCsrrcMask) == InstCsrrc);  // csrrc
  assign opcode_instr_o[EnumInstCsrrwi] = ((inst_q & InstCsrrwiMask) == InstCsrrwi);  // csrrwi
  assign opcode_instr_o[EnumInstCsrrsi] = ((inst_q & InstCsrrsiMask) == InstCsrrsi);  // csrrsi
  assign opcode_instr_o[EnumInstCsrrci] = ((inst_q & InstCsrrciMask) == InstCsrrci);  // csrrci
  assign opcode_instr_o[EnumInstMul]    = ((inst_q & InstMulMask) == InstMul);  // mul
  assign opcode_instr_o[EnumInstMulh]   = ((inst_q & InstMulhMask) == InstMulh);  // mulh
  assign opcode_instr_o[EnumInstMulhsu] = ((inst_q & InstMulhsuMask) == InstMulhsu);  // mulhsu
  assign opcode_instr_o[EnumInstMulhu]  = ((inst_q & InstMulhuMask) == InstMulhu);  // mulhu
  assign opcode_instr_o[EnumInstDiv]    = ((inst_q & InstDivMask) == InstDiv);  // div
  assign opcode_instr_o[EnumInstDivu]   = ((inst_q & InstDivuMask) == InstDivu);  // divu
  assign opcode_instr_o[EnumInstRem]    = ((inst_q & InstRemMask) == InstRem);  // rem
  assign opcode_instr_o[EnumInstRemu]   = ((inst_q & InstRemuMask) == InstRemu);  // remu
  assign opcode_instr_o[EnumInstFault]  = ((inst_q & InstFaultMask) == InstFault);  // invalid

  // Decode operands
  assign opcode_pc_o                    = pc_q;
  assign opcode_opcode_o                = inst_q;
  assign opcode_ra_idx_o                = inst_q[19:15];
  assign opcode_rb_idx_o                = inst_q[24:20];
  assign opcode_rd_idx_o                = inst_q[11:7];

  //-------------------------------------------------------------
  // Bypass / Forwarding
  //-------------------------------------------------------------
  logic [31:0] opcode_ra_operand_r;
  logic [31:0] opcode_rb_operand_r;

  always_comb begin
    // Bypass: Exec
    if (!writeback_exec_squash_i && writeback_exec_idx_i != 5'd0 && writeback_exec_idx_i == opcode_ra_idx_o)
      opcode_ra_operand_r = writeback_exec_value_i;
    // Bypass: Mem
    else if (!writeback_mem_squash_i && writeback_mem_idx_i != 5'd0 && writeback_mem_idx_i == opcode_ra_idx_o)
      opcode_ra_operand_r = writeback_mem_value_i;
    else opcode_ra_operand_r = ra_value_w;

    // Bypass: Exec
    if (!writeback_exec_squash_i && writeback_exec_idx_i != 5'd0 && writeback_exec_idx_i == opcode_rb_idx_o)
      opcode_rb_operand_r = writeback_exec_value_i;
    // Bypass: Mem
    else if (!writeback_mem_squash_i && writeback_mem_idx_i != 5'd0 && writeback_mem_idx_i == opcode_rb_idx_o)
      opcode_rb_operand_r = writeback_mem_value_i;
    else opcode_rb_operand_r = rb_value_w;
  end

  assign opcode_ra_operand_o = opcode_ra_operand_r;
  assign opcode_rb_operand_o = opcode_rb_operand_r;

  //-------------------------------------------------------------
  // Stall logic
  //-------------------------------------------------------------
  logic        opcode_valid_r;
  logic [31:0] current_scoreboard_r;

  always_comb begin
    opcode_valid_r                            = valid_q & ~branch_csr_request_i;
    stall_scoreboard_r                        = 1'b0;
    current_scoreboard_r                      = scoreboard_q;

    // Mem writeback bypass
    current_scoreboard_r[writeback_mem_idx_i] = 1'b0;

    // Detect dependancy on the LSU/CSR scoreboard
    if (current_scoreboard_r[opcode_ra_idx_o] ||
        current_scoreboard_r[opcode_rb_idx_o] ||
        current_scoreboard_r[opcode_rd_idx_o])
    begin
      stall_scoreboard_r = 1'b1;
      opcode_valid_r     = 1'b0;
    end

  end

  // Opcode valid flags to the various execution units
  assign exec_opcode_valid_o = opcode_valid_r && !lsu_stall_i && !csr_stall_i && !muldiv_stall_i;
  assign lsu_opcode_valid_o = opcode_valid_r && !exec_stall_i && !csr_stall_i && !muldiv_stall_i;
  assign csr_opcode_valid_o = opcode_valid_r && !exec_stall_i && !lsu_stall_i && !muldiv_stall_i;
  assign muldiv_opcode_valid_o = opcode_valid_r && !exec_stall_i && !lsu_stall_i && !csr_stall_i;

  //-------------------------------------------------------------
  // Fetch output
  //-------------------------------------------------------------
  assign fetch_branch_o = branch_request_i | branch_csr_request_i;
  assign fetch_branch_pc_o = branch_csr_request_i ? branch_csr_pc_i : branch_pc_i;
  assign fetch_accept_o    = branch_csr_request_i || (!exec_stall_i && !stall_scoreboard_r && !lsu_stall_i && !csr_stall_i && !muldiv_stall_i);

  //-------------------------------------------------------------
  // Faults
  //-------------------------------------------------------------
  // Bad opcode detection...
  logic fault_invalid_inst_w;
  assign fault_invalid_inst_w = opcode_valid_r ? ~(|opcode_instr_o[EnumInstFault-1:0]) : 1'b0;


endmodule
