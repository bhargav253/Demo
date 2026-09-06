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
module riscv_csr (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        intr_i,
  input  logic        opcode_valid_i,
  input  logic [55:0] opcode_instr_i,
  input  logic [31:0] opcode_opcode_i,
  input  logic [31:0] opcode_pc_i,
  input  logic [ 4:0] opcode_rd_idx_i,
  input  logic [ 4:0] opcode_ra_idx_i,
  input  logic [ 4:0] opcode_rb_idx_i,
  input  logic [31:0] opcode_ra_operand_i,
  input  logic [31:0] opcode_rb_operand_i,
  input  logic        branch_exec_request_i,
  input  logic [31:0] branch_exec_pc_i,
  input  logic [31:0] cpu_id_i,
  input  logic        fault_store_i,
  input  logic        fault_load_i,
  input  logic [31:0] fault_addr_i,
  output logic [ 4:0] writeback_idx_o,
  output logic        writeback_squash_o,
  output logic [31:0] writeback_value_o,
  output logic        stall_o,
  output logic        branch_csr_request_o,
  output logic [31:0] branch_csr_pc_o
);



  //-----------------------------------------------------------------
  // Includes
  //-----------------------------------------------------------------
  import riscv_defs_pkg::*;

  //-----------------------------------------------------------------
  // Registers / Wires
  //-----------------------------------------------------------------
  logic [31:0] csr_mepc_q;
  logic [31:0] csr_mcause_q;
  logic [31:0] csr_sr_q;
  logic [31:0] csr_mtvec_q;
  logic [31:0] csr_mip_q;
  logic [31:0] csr_mie_q;
  logic [31:0] csr_mtime_q;
  logic [31:0] csr_mtimecmp_q;
  logic [ 1:0] csr_mpriv_q;
  logic [31:0] csr_mscratch_q;

  // CSR - Supervisor
  logic [31:0] csr_sepc_q;
  logic [31:0] csr_stvec_q;
  logic [31:0] csr_scause_q;
  logic [31:0] csr_stval_q;
  logic [31:0] csr_satp_q;
  logic [31:0] csr_sscratch_q;

  //-----------------------------------------------------------------
  // Exception source
  //-----------------------------------------------------------------
  logic [31:0] exc_src_w;

  assign exc_src_w[McauseMisalignedFetch] = 1'b0;
  assign exc_src_w[McauseFaultFetch] = opcode_valid_i & opcode_instr_i[EnumInstFault];
  assign exc_src_w[McauseIllegalInstruction] = 1'b0;  // TODO
  assign exc_src_w[McauseBreakpoint] = opcode_valid_i & opcode_instr_i[EnumInstEbreak];
  assign exc_src_w[McauseMisalignedLoad] = 1'b0;
  assign exc_src_w[McauseFaultLoad] = fault_load_i;
  assign exc_src_w[McauseMisalignedStore] = 1'b0;
  assign exc_src_w[McauseFaultStore] = fault_store_i;
  assign exc_src_w[McauseEcallU]             = opcode_valid_i & opcode_instr_i[EnumInstEcall] & (csr_mpriv_q == PrivUser);
  assign exc_src_w[McauseEcallS]             = opcode_valid_i & opcode_instr_i[EnumInstEcall] & (csr_mpriv_q == PrivSuper);
  assign exc_src_w[McauseEcallH] = 1'b0;
  assign exc_src_w[McauseEcallM]             = opcode_valid_i & opcode_instr_i[EnumInstEcall] & (csr_mpriv_q == PrivMachine);
  assign exc_src_w[McausePageFaultInst] = 1'b0;
  assign exc_src_w[McausePageFaultLoad] = 1'b0;
  assign exc_src_w[McausePageFaultLoad+1] = 1'b0;
  assign exc_src_w[McausePageFaultStore] = 1'b0;
  assign exc_src_w[31:16] = 16'b0;

  //-----------------------------------------------------------------
  // CSR handling
  //-----------------------------------------------------------------
  logic [11:0] imm12_r;
  logic        set_r;
  logic        clr_r;

  logic [31:0] csr_mepc_d;
  logic [31:0] csr_mcause_d;
  logic [31:0] csr_sr_d;
  logic [31:0] csr_mtvec_d;
  logic [31:0] csr_mip_d;
  logic [31:0] csr_mie_d;
  logic [31:0] csr_mtime_d;
  logic [31:0] csr_mtimecmp_d;
  logic [ 1:0] csr_mpriv_d;
  logic [31:0] csr_mscratch_d;

  // CSR - Supervisor
  logic [31:0] csr_sepc_d;
  logic [31:0] csr_stvec_d;
  logic [31:0] csr_scause_d;
  logic [31:0] csr_stval_d;
  logic [31:0] csr_satp_d;
  logic [31:0] csr_sscratch_d;

  // No medeleg register - use hardcoded version
  logic [31:0] csr_medeleg_w;
  assign csr_medeleg_w[McauseMisalignedFetch]    = 1'b1;
  assign csr_medeleg_w[McauseFaultFetch]         = 1'b0;
  assign csr_medeleg_w[McauseIllegalInstruction] = 1'b0;
  assign csr_medeleg_w[McauseBreakpoint]         = 1'b0;
  assign csr_medeleg_w[McauseMisalignedLoad]     = 1'b0;
  assign csr_medeleg_w[McauseFaultLoad]          = 1'b0;
  assign csr_medeleg_w[McauseMisalignedStore]    = 1'b0;
  assign csr_medeleg_w[McauseFaultStore]         = 1'b0;
  assign csr_medeleg_w[McauseEcallU]             = 1'b1;
  assign csr_medeleg_w[McauseEcallS]             = 1'b0;
  assign csr_medeleg_w[McauseEcallH]             = 1'b0;
  assign csr_medeleg_w[McauseEcallM]             = 1'b0;
  assign csr_medeleg_w[McausePageFaultInst]      = 1'b1;
  assign csr_medeleg_w[McausePageFaultLoad]      = 1'b1;
  assign csr_medeleg_w[McausePageFaultLoad+1]    = 1'b0;
  assign csr_medeleg_w[McausePageFaultStore]     = 1'b1;
  assign csr_medeleg_w[31:16]                    = 16'b0;

  logic        take_intr_r;

  logic [31:0] data_r;
  logic [31:0] result_r;
  logic        valid_unit_inst_w;
  assign valid_unit_inst_w = opcode_valid_i &
                         (opcode_instr_i[EnumInstCsrrw] |
                         opcode_instr_i[EnumInstCsrrs]  |
                         opcode_instr_i[EnumInstCsrrc]  |
                         opcode_instr_i[EnumInstCsrrwi] |
                         opcode_instr_i[EnumInstCsrrsi] |
                         opcode_instr_i[EnumInstCsrrci] |
                         opcode_instr_i[EnumInstEcall]  |
                         opcode_instr_i[EnumInstEbreak] |
                         opcode_instr_i[EnumInstEret]   |
                         opcode_instr_i[EnumInstFault]);

  always_comb begin
    imm12_r = opcode_opcode_i[31:20];

    set_r           = opcode_instr_i[EnumInstCsrrw] | opcode_instr_i[EnumInstCsrrs] |
                      opcode_instr_i[EnumInstCsrrwi] | opcode_instr_i[EnumInstCsrrsi];
    clr_r           = opcode_instr_i[EnumInstCsrrw] | opcode_instr_i[EnumInstCsrrc] |
                      opcode_instr_i[EnumInstCsrrwi] | opcode_instr_i[EnumInstCsrrci];

    take_intr_r = 1'b0;
    csr_mepc_d = csr_mepc_q;
    csr_sr_d = csr_sr_q;
    csr_mcause_d = csr_mcause_q;
    csr_mtvec_d = csr_mtvec_q;
    csr_mip_d = csr_mip_q;
    csr_mie_d = csr_mie_q;
    csr_mtime_d = csr_mtime_q;
    csr_mtimecmp_d = csr_mtimecmp_q;
    csr_mpriv_d = csr_mpriv_q;
    csr_mscratch_d = csr_mscratch_q;
    csr_sepc_d = csr_sepc_q;
    csr_stvec_d = csr_stvec_q;
    csr_scause_d = csr_scause_q;
    csr_stval_d = csr_stval_q;
    csr_satp_d = csr_satp_q;
    csr_sscratch_d = csr_sscratch_q;

    result_r = 32'b0;
    data_r = 32'b0;

    csr_mtime_d = csr_mtime_q + 32'd1;

    // Timer should generate a interrupt?
    if (csr_mtime_d == csr_mtimecmp_d) csr_mip_d[SrIpMtipR] = 1'b1;

    // External interrupts
    if (intr_i) csr_mip_d[SrIpMeipR] = 1'b1;

    take_intr_r = ((((csr_mip_d & csr_mie_d) & CsrMipMask) != 32'd0) && csr_sr_d[SrMieR]);

    // Fetch/Load/Store fault
    if (exc_src_w[McauseFaultFetch] || exc_src_w[McauseFaultLoad] || exc_src_w[McauseFaultStore])
      take_intr_r = 1'b1;

    // We will be taking an interrupt, record the reason
    if (take_intr_r) begin
      // Exception delegated to supervisor mode
      if (csr_mpriv_q <= PrivSuper) begin
        // Save interrupt / supervisor state
        csr_sr_d[SrSpieR] = csr_sr_d[SrSieR];
        csr_sr_d[SrSppR]  = (csr_mpriv_q == PrivSuper);

        // Disable interrupts and enter supervisor mode
        csr_sr_d[SrSieR]  = 1'b0;

        // Raise priviledge to supervisor level
        csr_mpriv_d       = PrivSuper;

        // Previous instruction was EBREAK, ERET, ECALL
        // Target inst not executed, so return here later
        if (branch_csr_request_o) csr_sepc_d = branch_csr_pc_o;
        // Taking interrupt instead of executing instruction handled by this functional unit?
        // Target inst not executed, so return here later
        else if (valid_unit_inst_w) csr_sepc_d = opcode_pc_i;
        // Branch request executed in exec (not squashed)
        else if (branch_exec_request_i) csr_sepc_d = branch_exec_pc_i;
        // Valid instruction, executed by another unit
        else if (opcode_valid_i) csr_sepc_d = opcode_pc_i + 32'd4;
        // Valid instruction not ready, re-run it later
        else
          csr_sepc_d = opcode_pc_i;

        if (exc_src_w[McauseFaultFetch]) csr_scause_d = McauseFaultFetch;
        else if (exc_src_w[McauseFaultLoad]) csr_scause_d = McauseFaultLoad;
        else if (exc_src_w[McauseFaultStore]) csr_scause_d = McauseFaultStore;
        // NOTE: Lowest interrupt number wins
        else if (((csr_mip_d & csr_mie_q) & (1 << IrqSSoft)) != 32'd0)
          csr_scause_d = McauseInterrupt + IrqSSoft;
        else if (((csr_mip_d & csr_mie_q) & (1 << IrqSTimer)) != 32'd0)
          csr_scause_d = McauseInterrupt + IrqSTimer;
        else if (((csr_mip_d & csr_mie_q) & (1 << IrqSExt)) != 32'd0)
          csr_scause_d = McauseInterrupt + IrqSExt;

        // Not set...
        csr_stval_d = 32'b0;
      end else begin
        // Save interrupt / supervisor state
        csr_sr_d[SrMpieR]           = csr_sr_d[SrMieR];
        csr_sr_d[SrMppMsb:SrMppLsb] = csr_mpriv_q;

        // Disable interrupts and enter supervisor mode
        csr_sr_d[SrMieR]            = 1'b0;

        // Raise priviledge to machine level
        csr_mpriv_d                 = PrivMachine;

        // Previous instruction was EBREAK, ERET, ECALL
        // Target inst not executed, so return here later
        if (branch_csr_request_o) csr_mepc_d = branch_csr_pc_o;
        // Taking interrupt instead of executing instruction handled by this functional unit?
        // Target inst not executed, so return here later
        else if (valid_unit_inst_w) csr_mepc_d = opcode_pc_i;
        // Branch request executed in exec (not squashed)
        else if (branch_exec_request_i) csr_mepc_d = branch_exec_pc_i;
        // Valid instruction, executed by another unit
        else if (opcode_valid_i) csr_mepc_d = opcode_pc_i + 32'd4;
        // Valid instruction not ready, re-run it later
        else
          csr_mepc_d = opcode_pc_i;

        if (exc_src_w[McauseFaultFetch]) csr_mcause_d = McauseFaultFetch;
        else if (exc_src_w[McauseFaultLoad]) csr_mcause_d = McauseFaultLoad;
        else if (exc_src_w[McauseFaultStore]) csr_mcause_d = McauseFaultStore;
        // NOTE: Lowest interrupt number wins
        else if (((csr_mip_d & csr_mie_q) & (1 << IrqMSoft)) != 32'd0)
          csr_mcause_d = McauseInterrupt + IrqMSoft;
        else if (((csr_mip_d & csr_mie_q) & (1 << IrqMTimer)) != 32'd0)
          csr_mcause_d = McauseInterrupt + IrqMTimer;
        else if (((csr_mip_d & csr_mie_q) & (1 << IrqMExt)) != 32'd0)
          csr_mcause_d = McauseInterrupt + IrqMExt;
      end
    end  // CSR modify instruction
    else if (opcode_valid_i && (set_r || clr_r)) begin
      data_r = (opcode_instr_i[EnumInstCsrrwi] | opcode_instr_i[EnumInstCsrrsi] | opcode_instr_i[EnumInstCsrrci]) ?
                           {27'b0, opcode_ra_idx_i} : opcode_ra_operand_i;

      case (imm12_r[11:0])
        CsrMscratch: begin
          data_r   = data_r & CsrMscratchMask;
          result_r = csr_mscratch_q & CsrMscratchMask;

          if (set_r && clr_r) csr_mscratch_d = data_r;
          else if (set_r) csr_mscratch_d = csr_mscratch_d | data_r;
          else if (clr_r) csr_mscratch_d = csr_mscratch_d & ~data_r;
        end
        CsrMepc: begin
          data_r   = data_r & CsrMepcMask;
          result_r = csr_mepc_q & CsrMepcMask;

          if (set_r && clr_r) csr_mepc_d = data_r;
          else if (set_r) csr_mepc_d = csr_mepc_d | data_r;
          else if (clr_r) csr_mepc_d = csr_mepc_d & ~data_r;
        end
        CsrMtvec: begin
          data_r   = data_r & CsrMtvecMask;
          result_r = csr_mtvec_q & CsrMtvecMask;

          if (set_r && clr_r) csr_mtvec_d = data_r;
          else if (set_r) csr_mtvec_d = csr_mtvec_d | data_r;
          else if (clr_r) csr_mtvec_d = csr_mtvec_d & ~data_r;
        end
        CsrMcause: begin
          data_r   = data_r & CsrMcauseMask;
          result_r = csr_mcause_q & CsrMcauseMask;

          if (set_r && clr_r) csr_mcause_d = data_r;
          else if (set_r) csr_mcause_d = csr_mcause_d | data_r;
          else if (clr_r) csr_mcause_d = csr_mcause_d & ~data_r;
        end
        CsrMstatus: begin
          data_r   = data_r & CsrMstatusMask;
          result_r = csr_sr_q & CsrMstatusMask;

          if (set_r && clr_r) csr_sr_d = data_r;
          else if (set_r) csr_sr_d = csr_sr_d | data_r;
          else if (clr_r) csr_sr_d = csr_sr_d & ~data_r;
        end
        CsrMip: begin
          data_r   = data_r & CsrMipMask;
          result_r = csr_mip_d & CsrMipMask;  // Local version
          if (set_r && clr_r) csr_mip_d = data_r;
          else if (set_r) csr_mip_d = csr_mip_d | data_r;
          else if (clr_r) csr_mip_d = csr_mip_d & ~data_r;
        end
        CsrMie: begin
          data_r   = data_r & CsrMieMask;
          result_r = csr_mie_q & CsrMieMask;

          if (set_r && clr_r) csr_mie_d = data_r;
          else if (set_r) csr_mie_d = csr_mie_d | data_r;
          else if (clr_r) csr_mie_d = csr_mie_d & ~data_r;
        end
        CsrMtime: begin
          data_r   = data_r & CsrMtimeMask;
          result_r = csr_mtime_q & CsrMtimeMask;  // Return flopped state

          // Non-std behaviour - write to CSR_TIME gives next interrupt threshold
          if (set_r && data_r != 32'b0) begin
            csr_mtimecmp_d = data_r;

            // Clear interrupt pending
            csr_mip_d[SrIpMtipR] = 1'b0;
          end
        end
        CsrMhartid: begin
          result_r = cpu_id_i;
        end
        CsrMisa: begin
          result_r = MisaRv32 | MisaRvi | MisaRvm;
        end
        CsrMedeleg: begin
          result_r = csr_medeleg_w;
        end
        default: ;
      endcase
    end  // System Call / Breakpoint
    else if (opcode_valid_i && (opcode_instr_i[EnumInstEcall] | opcode_instr_i[EnumInstEbreak]))
    begin
      // Exception delegated to supervisor mode
      if ((csr_mpriv_q <= PrivSuper) && (|(exc_src_w & csr_medeleg_w))) begin
        // Save interrupt / supervisor state
        csr_sr_d[SrSpieR] = csr_sr_q[SrSieR];
        csr_sr_d[SrSppR]  = (csr_mpriv_q == PrivSuper);

        // Disable interrupts and enter supervisor mode
        csr_sr_d[SrSieR]  = 1'b0;

        // Raise priviledge to supervisor level
        csr_mpriv_d       = PrivSuper;

        // Save PC of next instruction (not yet executed)
        csr_sepc_d        = opcode_pc_i;

        // Exception source
        if (opcode_instr_i[EnumInstEbreak]) csr_scause_d = McauseBreakpoint;
        else csr_scause_d = McauseEcallU + {30'b0, csr_mpriv_q};

        // Supervisor Trap Value is cleared for these exceptions
        csr_stval_d = 32'b0;
      end else begin
        // Save interrupt / supervisor state
        csr_sr_d[SrMpieR]           = csr_sr_d[SrMieR];
        csr_sr_d[SrMppMsb:SrMppLsb] = csr_mpriv_q;

        // Disable interrupts and enter supervisor mode
        csr_sr_d[SrMieR]            = 1'b0;

        // Raise priviledge to machine level
        csr_mpriv_d                 = PrivMachine;

        // Save PC of next instruction (not yet executed)
        csr_mepc_d                  = opcode_pc_i;

        // Exception source
        if (opcode_instr_i[EnumInstEbreak]) csr_mcause_d = McauseBreakpoint;
        else csr_mcause_d = McauseEcallU + {30'b0, csr_mpriv_q};
      end
    end  // Return from interrupt
    else if (opcode_valid_i && opcode_instr_i[EnumInstEret]) begin
      // MRET (return from machine)
      if (opcode_opcode_i[InstMretR]) begin
        // Set privilege level to previous MPP
        csr_mpriv_d                 = csr_sr_d[SrMppMsb:SrMppLsb];

        // Interrupt enable pop
        csr_sr_d[SrMieR]            = csr_sr_d[SrMpieR];
        csr_sr_d[SrMpieR]           = 1'b1;

        // Set next MPP to user mode
        csr_sr_d[SrMppMsb:SrMppLsb] = SrMppU;
      end  // SRET (return from supervisor)
      else begin
        // Set privilege level to previous privilege level
        csr_mpriv_d       = csr_sr_d[SrSppR] ? PrivSuper : PrivUser;

        // Interrupt enable pop
        csr_sr_d[SrSieR]  = csr_sr_d[SrSpieR];
        csr_sr_d[SrSpieR] = 1'b1;

        // Set next SPP to user mode
        csr_sr_d[SrSppR]  = 1'b0;
      end
    end
  end

  //-----------------------------------------------------------------
  // Sequential
  //-----------------------------------------------------------------
  logic        writeback_en_q;
  logic [ 4:0] writeback_idx_q;
  logic [31:0] writeback_value_q;
  logic        writeback_squash_q;

  always_ff @(posedge clk_i)
    if (!rst_ni) begin
      csr_mepc_q         <= 32'b0;
      csr_sr_q           <= 32'b0;
      csr_mcause_q       <= 32'b0;
      csr_mtvec_q        <= 32'b0;
      csr_mip_q          <= 32'b0;
      csr_mie_q          <= 32'b0;
      csr_mtime_q        <= 32'b0;
      csr_mtimecmp_q     <= 32'b0;
      csr_mpriv_q        <= PrivMachine;
      csr_mscratch_q     <= 32'b0;
      csr_sepc_q         <= 32'b0;
      csr_stvec_q        <= 32'b0;
      csr_scause_q       <= 32'b0;
      csr_stval_q        <= 32'b0;
      csr_satp_q         <= 32'b0;
      csr_sscratch_q     <= 32'b0;
      writeback_en_q     <= 1'b0;
      writeback_idx_q    <= 5'b0;
      writeback_value_q  <= 32'b0;
      writeback_squash_q <= 1'b0;
    end else begin
      csr_mepc_q     <= csr_mepc_d;
      csr_sr_q       <= csr_sr_d;
      csr_mcause_q   <= csr_mcause_d;
      csr_mtvec_q    <= csr_mtvec_d;
      csr_mip_q      <= csr_mip_d;
      csr_mie_q      <= csr_mie_d;
      csr_mtime_q    <= csr_mtime_d;
      csr_mtimecmp_q <= csr_mtimecmp_d;
      csr_mpriv_q    <= PrivMachine;
      csr_mscratch_q <= csr_mscratch_d;
      csr_sepc_q     <= csr_sepc_d;
      csr_stvec_q    <= csr_stvec_d;
      csr_scause_q   <= csr_scause_d;
      csr_stval_q    <= csr_stval_d;
      csr_satp_q     <= csr_satp_d;
      csr_sscratch_q <= csr_sscratch_d;

      if (opcode_valid_i && ~stall_o) begin
        writeback_en_q    <= (set_r || clr_r);
        writeback_idx_q   <= opcode_rd_idx_i;
        writeback_value_q <= result_r;
      end else begin
        writeback_en_q <= 1'b0;
      end

      // Scoreboard will have been allocated so de-allocate if an allocated
      // instruction was aborted
      writeback_squash_q <= (valid_unit_inst_w & take_intr_r);


    end

  assign writeback_idx_o    = {5{writeback_en_q | writeback_squash_q}} & writeback_idx_q;
  assign writeback_value_o  = writeback_value_q;
  assign writeback_squash_o = writeback_squash_q;

  assign stall_o            = 1'b0;

  //-----------------------------------------------------------------
  // Execute - Branch operations
  //-----------------------------------------------------------------
  logic        branch_d;
  logic [31:0] branch_target_d;

  always_comb begin
    branch_d        = 1'b0;
    branch_target_d = 32'b0;

    if (take_intr_r) begin
      branch_d = 1'b1;

      if (csr_mpriv_q <= PrivSuper) branch_target_d = csr_stvec_q;
      else branch_target_d = csr_mtvec_q;
    end else if (opcode_instr_i[EnumInstEcall]) begin
      branch_d = opcode_valid_i;

      // Exception delegated to supervisor mode
      if ((csr_mpriv_q <= PrivSuper) && (|(exc_src_w & csr_medeleg_w)))
        branch_target_d = csr_stvec_q;
      else branch_target_d = csr_mtvec_q;
    end else if (opcode_instr_i[EnumInstEbreak]) begin
      branch_d = opcode_valid_i;

      // Exception delegated to supervisor mode
      if ((csr_mpriv_q <= PrivSuper) && (|(exc_src_w & csr_medeleg_w)))
        branch_target_d = csr_stvec_q;
      else branch_target_d = csr_mtvec_q;
    end else if (opcode_instr_i[EnumInstEret]) begin
      branch_d = opcode_valid_i;

      // SRET (return from super)
      if (!opcode_opcode_i[InstMretR]) branch_target_d = csr_sepc_q;
      else branch_target_d = csr_mepc_q;
    end

  end

  logic        branch_q;
  logic [31:0] branch_target_q;

  always_ff @(posedge clk_i)
    if (!rst_ni) begin
      branch_target_q <= 32'b0;
      branch_q        <= 1'b0;
    end else begin
      branch_target_q <= branch_target_d;
      branch_q        <= branch_d;
    end

  assign branch_csr_request_o = branch_q;
  assign branch_csr_pc_o      = branch_target_q;



endmodule
