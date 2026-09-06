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
module riscv_lsu (
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
  input  logic [31:0] mem_data_rd_i,
  input  logic        mem_accept_i,
  input  logic        mem_ack_i,
  input  logic        mem_error_i,
  input  logic [10:0] mem_resp_tag_i,
  output logic [31:0] mem_addr_o,
  output logic [31:0] mem_data_wr_o,
  output logic        mem_rd_o,
  output logic [ 3:0] mem_wr_o,
  output logic        mem_cacheable_o,
  output logic [10:0] mem_req_tag_o,
  output logic        mem_invalidate_o,
  output logic        mem_flush_o,
  output logic [ 4:0] writeback_idx_o,
  output logic        writeback_squash_o,
  output logic [31:0] writeback_value_o,
  output logic        fault_store_o,
  output logic        fault_load_o,
  output logic [31:0] fault_addr_o,
  output logic        stall_o
);



  //-----------------------------------------------------------------
  // Includes
  //-----------------------------------------------------------------
  import riscv_defs_pkg::*;

  //-------------------------------------------------------------
  // Registers / Wires
  //-------------------------------------------------------------
  logic [31:0] mem_addr_q;
  logic [31:0] mem_data_wr_q;
  logic        mem_rd_q;
  logic [ 3:0] mem_wr_q;
  logic        mem_cacheable_q;
  logic [10:0] mem_req_tag_q;
  logic        mem_invalidate_q;
  logic        mem_flush_q;

  //-------------------------------------------------------------
  // Opcode decode
  //-------------------------------------------------------------
  logic        load_inst_w;
  assign load_inst_w = (opcode_instr_i[EnumInstLb]  ||
                    opcode_instr_i[EnumInstLh]  ||
                    opcode_instr_i[EnumInstLw]  ||
                    opcode_instr_i[EnumInstLbu] ||
                    opcode_instr_i[EnumInstLhu] ||
                    opcode_instr_i[EnumInstLwu]);
  logic load_signed_inst_w;
  assign load_signed_inst_w = (opcode_instr_i[EnumInstLb]  ||
                           opcode_instr_i[EnumInstLh]  ||
                           opcode_instr_i[EnumInstLw]);


  logic [31:0] mem_addr_d;
  always_comb begin
    if (opcode_valid_i && opcode_instr_i[EnumInstCsrrw]) mem_addr_d = opcode_ra_operand_i;
    else if (opcode_valid_i && load_inst_w)
      mem_addr_d = opcode_ra_operand_i + {{20{opcode_opcode_i[31]}}, opcode_opcode_i[31:20]};
    else
      mem_addr_d = opcode_ra_operand_i + {{20{opcode_opcode_i[31]}}, opcode_opcode_i[31:25], opcode_opcode_i[11:7]};
  end
  logic dcache_flush_w;
  assign dcache_flush_w = opcode_instr_i[EnumInstCsrrw] && (opcode_opcode_i[31:20] == CsrDflush);

  logic dcache_invalidate_w;
  assign dcache_invalidate_w = opcode_instr_i[EnumInstCsrrw] && (opcode_opcode_i[31:20] == CsrDinvalidate);
  logic mem_stall;
  assign mem_stall = (mem_rd_q | (|mem_wr_q)) & !mem_accept_i;

  //-------------------------------------------------------------
  // Sequential
  //-------------------------------------------------------------
  always_ff @(posedge clk_i)
    if (!rst_ni) begin
      mem_addr_q       <= 32'b0;
      mem_data_wr_q    <= 32'b0;
      mem_rd_q         <= 1'b0;
      mem_wr_q         <= 4'b0;
      mem_req_tag_q    <= 11'b0;
      mem_cacheable_q  <= 1'b0;
      mem_invalidate_q <= 1'b0;
      mem_flush_q      <= 1'b0;
    end
     else if (!((mem_invalidate_o || mem_flush_o || mem_rd_o || mem_wr_o != 4'b0) && !mem_accept_i)) begin

      if (!mem_stall) begin
        mem_addr_q       <= 32'b0;
        mem_data_wr_q    <= 32'b0;
        mem_rd_q         <= 1'b0;
        mem_wr_q         <= 4'b0;
        mem_cacheable_q  <= 1'b0;
        mem_req_tag_q    <= 11'b0;
        mem_invalidate_q <= 1'b0;
        mem_flush_q      <= 1'b0;
      end

      // Tag associated with load
      if (opcode_valid_i & !mem_stall) begin
        mem_req_tag_q[4:0] <= opcode_rd_idx_i;
        mem_req_tag_q[6:5] <= mem_addr_d[1:0];
        mem_req_tag_q[7]   <= opcode_instr_i[EnumInstLb] || opcode_instr_i[EnumInstLbu];
        mem_req_tag_q[8]   <= opcode_instr_i[EnumInstLh] || opcode_instr_i[EnumInstLhu];
        mem_req_tag_q[9]   <= opcode_instr_i[EnumInstLw] || opcode_instr_i[EnumInstLwu];
        mem_req_tag_q[10]  <= load_signed_inst_w;
      end

      mem_rd_q <= mem_stall ? mem_rd_q : (opcode_valid_i && load_inst_w);

      if (!mem_stall & opcode_valid_i && opcode_instr_i[EnumInstSw]) begin
        mem_data_wr_q <= opcode_rb_operand_i;
        mem_wr_q      <= 4'hF;
      end else if (!mem_stall & opcode_valid_i && opcode_instr_i[EnumInstSh]) begin
        case (mem_addr_d[1:0])
          2'h2: begin
            mem_data_wr_q <= {opcode_rb_operand_i[15:0], 16'h0000};
            mem_wr_q      <= 4'b1100;
          end
          default: begin
            mem_data_wr_q <= {16'h0000, opcode_rb_operand_i[15:0]};
            mem_wr_q      <= 4'b0011;
          end
        endcase
      end else if (!mem_stall & opcode_valid_i && opcode_instr_i[EnumInstSb]) begin
        case (mem_addr_d[1:0])
          2'h3: begin
            mem_data_wr_q <= {opcode_rb_operand_i[7:0], 24'h000000};
            mem_wr_q      <= 4'b1000;
          end
          2'h2: begin
            mem_data_wr_q <= {{8'h00, opcode_rb_operand_i[7:0]}, 16'h0000};
            mem_wr_q      <= 4'b0100;
          end
          2'h1: begin
            mem_data_wr_q <= {{16'h0000, opcode_rb_operand_i[7:0]}, 8'h00};
            mem_wr_q      <= 4'b0010;
          end
          2'h0: begin
            mem_data_wr_q <= {24'h000000, opcode_rb_operand_i[7:0]};
            mem_wr_q      <= 4'b0001;
          end
          default: ;
        endcase
      end else mem_wr_q <= mem_stall ? mem_wr_q : 4'b0;

      mem_cacheable_q  <= !mem_stall & opcode_valid_i ? !mem_addr_d[31] : mem_cacheable_q;

      mem_invalidate_q <= mem_stall ? mem_invalidate_q : opcode_valid_i & dcache_invalidate_w;
      mem_flush_q      <= mem_stall ? mem_flush_q : opcode_valid_i & dcache_flush_w;

      // Mask address bits
      mem_addr_q       <= mem_stall ? mem_addr_q : {mem_addr_d[31:2], 2'b0};
    end

  assign mem_addr_o = mem_addr_q;
  assign mem_data_wr_o = mem_data_wr_q;
  assign mem_rd_o = mem_rd_q & mem_accept_i;
  assign mem_wr_o = mem_wr_q & {4{mem_accept_i}};
  assign mem_cacheable_o = mem_cacheable_q;
  assign mem_req_tag_o = mem_req_tag_q;
  assign mem_invalidate_o = mem_invalidate_q;
  assign mem_flush_o = mem_flush_q;

  // Stall upstream if cache is busy
  assign stall_o          = ((mem_invalidate_o || mem_flush_o || mem_rd_q || mem_wr_q != 4'b0) && !mem_accept_i);
  //-------------------------------------------------------------
  // Error handling
  //-------------------------------------------------------------
  // NOTE: Current implementation does not track addresses...
  assign fault_addr_o = 32'b0;
  assign fault_load_o = mem_ack_i ? (mem_resp_tag_i[9:7] != 3'b0 && mem_error_i) : 1'b0;
  assign fault_store_o = mem_ack_i ? (mem_resp_tag_i[9:7] == 3'b0 && mem_error_i) : 1'b0;

  //-------------------------------------------------------------
  // Load response
  //-------------------------------------------------------------
  logic [ 1:0] addr_lsb_r;
  logic        load_byte_r;
  logic        load_half_r;
  logic        load_word_r;
  logic        load_signed_r;
  logic [ 4:0] wb_idx_r;
  logic [31:0] wb_result_r;

  always_comb begin
    wb_result_r   = 32'b0;

    // Tag associated with load
    wb_idx_r      = mem_resp_tag_i[4:0];
    addr_lsb_r    = mem_resp_tag_i[6:5];
    load_byte_r   = mem_resp_tag_i[7];
    load_half_r   = mem_resp_tag_i[8];
    load_word_r   = mem_resp_tag_i[9];
    load_signed_r = mem_resp_tag_i[10];

    // Handle responses
    if (mem_ack_i && (load_byte_r || load_half_r || load_word_r)) begin
      if (load_byte_r) begin
        case (addr_lsb_r[1:0])
          2'h3: wb_result_r = {24'b0, mem_data_rd_i[31:24]};
          2'h2: wb_result_r = {24'b0, mem_data_rd_i[23:16]};
          2'h1: wb_result_r = {24'b0, mem_data_rd_i[15:8]};
          2'h0: wb_result_r = {24'b0, mem_data_rd_i[7:0]};
        endcase

        if (load_signed_r && wb_result_r[7]) wb_result_r = {24'hFFFFFF, wb_result_r[7:0]};
      end else if (load_half_r) begin
        if (addr_lsb_r[1]) wb_result_r = {16'b0, mem_data_rd_i[31:16]};
        else wb_result_r = {16'b0, mem_data_rd_i[15:0]};

        if (load_signed_r && wb_result_r[15]) wb_result_r = {16'hFFFF, wb_result_r[15:0]};
      end else wb_result_r = mem_data_rd_i;
    end else wb_idx_r = 5'b0;
  end

  assign writeback_idx_o = wb_idx_r;
  assign writeback_value_o = wb_result_r;
  assign writeback_squash_o = 1'b0;

endmodule
