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

package riscv_defs_pkg;
  localparam logic [3:0] AluNone = 4'b0000;
  localparam logic [3:0] AluShiftl = 4'b0001;
  localparam logic [3:0] AluShiftr = 4'b0010;
  localparam logic [3:0] AluShiftrArith = 4'b0011;
  localparam logic [3:0] AluAdd = 4'b0100;
  localparam logic [3:0] AluSub = 4'b0110;
  localparam logic [3:0] AluAnd = 4'b0111;
  localparam logic [3:0] AluOr = 4'b1000;
  localparam logic [3:0] AluXor = 4'b1001;
  localparam logic [3:0] AluLessThan = 4'b1010;
  localparam logic [3:0] AluLessThanSigned = 4'b1011;
  localparam int unsigned EnumInstAndi = 0;
  localparam int unsigned EnumInstAddi = 1;
  localparam int unsigned EnumInstSlti = 2;
  localparam int unsigned EnumInstSltiu = 3;
  localparam int unsigned EnumInstOri = 4;
  localparam int unsigned EnumInstXori = 5;
  localparam int unsigned EnumInstSlli = 6;
  localparam int unsigned EnumInstSrli = 7;
  localparam int unsigned EnumInstSrai = 8;
  localparam int unsigned EnumInstLui = 9;
  localparam int unsigned EnumInstAuipc = 10;
  localparam int unsigned EnumInstAdd = 11;
  localparam int unsigned EnumInstSub = 12;
  localparam int unsigned EnumInstSlt = 13;
  localparam int unsigned EnumInstSltu = 14;
  localparam int unsigned EnumInstXor = 15;
  localparam int unsigned EnumInstOr = 16;
  localparam int unsigned EnumInstAnd = 17;
  localparam int unsigned EnumInstSll = 18;
  localparam int unsigned EnumInstSrl = 19;
  localparam int unsigned EnumInstSra = 20;
  localparam int unsigned EnumInstJal = 21;
  localparam int unsigned EnumInstJalr = 22;
  localparam int unsigned EnumInstBeq = 23;
  localparam int unsigned EnumInstBne = 24;
  localparam int unsigned EnumInstBlt = 25;
  localparam int unsigned EnumInstBge = 26;
  localparam int unsigned EnumInstBltu = 27;
  localparam int unsigned EnumInstBgeu = 28;
  localparam int unsigned EnumInstLb = 29;
  localparam int unsigned EnumInstLh = 30;
  localparam int unsigned EnumInstLw = 31;
  localparam int unsigned EnumInstLbu = 32;
  localparam int unsigned EnumInstLhu = 33;
  localparam int unsigned EnumInstLwu = 34;
  localparam int unsigned EnumInstSb = 35;
  localparam int unsigned EnumInstSh = 36;
  localparam int unsigned EnumInstSw = 37;
  localparam int unsigned EnumInstEcall = 38;
  localparam int unsigned EnumInstEbreak = 39;
  localparam int unsigned EnumInstEret = 40;
  localparam int unsigned EnumInstCsrrw = 41;
  localparam int unsigned EnumInstCsrrs = 42;
  localparam int unsigned EnumInstCsrrc = 43;
  localparam int unsigned EnumInstCsrrwi = 44;
  localparam int unsigned EnumInstCsrrsi = 45;
  localparam int unsigned EnumInstCsrrci = 46;
  localparam int unsigned EnumInstMul = 47;
  localparam int unsigned EnumInstMulh = 48;
  localparam int unsigned EnumInstMulhsu = 49;
  localparam int unsigned EnumInstMulhu = 50;
  localparam int unsigned EnumInstDiv = 51;
  localparam int unsigned EnumInstDivu = 52;
  localparam int unsigned EnumInstRem = 53;
  localparam int unsigned EnumInstRemu = 54;
  localparam int unsigned EnumInstFault = 55;
  localparam logic [31:0] InstAndi = 32'h7013;
  localparam logic [31:0] InstAndiMask = 32'h707f;
  localparam logic [31:0] InstAddi = 32'h13;
  localparam logic [31:0] InstAddiMask = 32'h707f;
  localparam logic [31:0] InstSlti = 32'h2013;
  localparam logic [31:0] InstSltiMask = 32'h707f;
  localparam logic [31:0] InstSltiu = 32'h3013;
  localparam logic [31:0] InstSltiuMask = 32'h707f;
  localparam logic [31:0] InstOri = 32'h6013;
  localparam logic [31:0] InstOriMask = 32'h707f;
  localparam logic [31:0] InstXori = 32'h4013;
  localparam logic [31:0] InstXoriMask = 32'h707f;
  localparam logic [31:0] InstSlli = 32'h1013;
  localparam logic [31:0] InstSlliMask = 32'hfc00707f;
  localparam logic [31:0] InstSrli = 32'h5013;
  localparam logic [31:0] InstSrliMask = 32'hfc00707f;
  localparam logic [31:0] InstSrai = 32'h40005013;
  localparam logic [31:0] InstSraiMask = 32'hfc00707f;
  localparam logic [31:0] InstLui = 32'h37;
  localparam logic [31:0] InstLuiMask = 32'h7f;
  localparam logic [31:0] InstAuipc = 32'h17;
  localparam logic [31:0] InstAuipcMask = 32'h7f;
  localparam logic [31:0] InstAdd = 32'h33;
  localparam logic [31:0] InstAddMask = 32'hfe00707f;
  localparam logic [31:0] InstSub = 32'h40000033;
  localparam logic [31:0] InstSubMask = 32'hfe00707f;
  localparam logic [31:0] InstSlt = 32'h2033;
  localparam logic [31:0] InstSltMask = 32'hfe00707f;
  localparam logic [31:0] InstSltu = 32'h3033;
  localparam logic [31:0] InstSltuMask = 32'hfe00707f;
  localparam logic [31:0] InstXor = 32'h4033;
  localparam logic [31:0] InstXorMask = 32'hfe00707f;
  localparam logic [31:0] InstOr = 32'h6033;
  localparam logic [31:0] InstOrMask = 32'hfe00707f;
  localparam logic [31:0] InstAnd = 32'h7033;
  localparam logic [31:0] InstAndMask = 32'hfe00707f;
  localparam logic [31:0] InstSll = 32'h1033;
  localparam logic [31:0] InstSllMask = 32'hfe00707f;
  localparam logic [31:0] InstSrl = 32'h5033;
  localparam logic [31:0] InstSrlMask = 32'hfe00707f;
  localparam logic [31:0] InstSra = 32'h40005033;
  localparam logic [31:0] InstSraMask = 32'hfe00707f;
  localparam logic [31:0] InstJal = 32'h6f;
  localparam logic [31:0] InstJalMask = 32'h7f;
  localparam logic [31:0] InstJalr = 32'h67;
  localparam logic [31:0] InstJalrMask = 32'h707f;
  localparam logic [31:0] InstBeq = 32'h63;
  localparam logic [31:0] InstBeqMask = 32'h707f;
  localparam logic [31:0] InstBne = 32'h1063;
  localparam logic [31:0] InstBneMask = 32'h707f;
  localparam logic [31:0] InstBlt = 32'h4063;
  localparam logic [31:0] InstBltMask = 32'h707f;
  localparam logic [31:0] InstBge = 32'h5063;
  localparam logic [31:0] InstBgeMask = 32'h707f;
  localparam logic [31:0] InstBltu = 32'h6063;
  localparam logic [31:0] InstBltuMask = 32'h707f;
  localparam logic [31:0] InstBgeu = 32'h7063;
  localparam logic [31:0] InstBgeuMask = 32'h707f;
  localparam logic [31:0] InstLb = 32'h3;
  localparam logic [31:0] InstLbMask = 32'h707f;
  localparam logic [31:0] InstLh = 32'h1003;
  localparam logic [31:0] InstLhMask = 32'h707f;
  localparam logic [31:0] InstLw = 32'h2003;
  localparam logic [31:0] InstLwMask = 32'h707f;
  localparam logic [31:0] InstLbu = 32'h4003;
  localparam logic [31:0] InstLbuMask = 32'h707f;
  localparam logic [31:0] InstLhu = 32'h5003;
  localparam logic [31:0] InstLhuMask = 32'h707f;
  localparam logic [31:0] InstLwu = 32'h6003;
  localparam logic [31:0] InstLwuMask = 32'h707f;
  localparam logic [31:0] InstSb = 32'h23;
  localparam logic [31:0] InstSbMask = 32'h707f;
  localparam logic [31:0] InstSh = 32'h1023;
  localparam logic [31:0] InstShMask = 32'h707f;
  localparam logic [31:0] InstSw = 32'h2023;
  localparam logic [31:0] InstSwMask = 32'h707f;
  localparam logic [31:0] InstEcall = 32'h73;
  localparam logic [31:0] InstEcallMask = 32'hffffffff;
  localparam logic [31:0] InstEbreak = 32'h100073;
  localparam logic [31:0] InstEbreakMask = 32'hffffffff;
  localparam logic [31:0] InstMret = 32'h10200073;
  localparam logic [31:0] InstMretMask = 32'hdfffffff;
  localparam int unsigned InstMretR = 29;
  localparam logic [31:0] InstCsrrw = 32'h1073;
  localparam logic [31:0] InstCsrrwMask = 32'h707f;
  localparam logic [31:0] InstCsrrs = 32'h2073;
  localparam logic [31:0] InstCsrrsMask = 32'h707f;
  localparam logic [31:0] InstCsrrc = 32'h3073;
  localparam logic [31:0] InstCsrrcMask = 32'h707f;
  localparam logic [31:0] InstCsrrwi = 32'h5073;
  localparam logic [31:0] InstCsrrwiMask = 32'h707f;
  localparam logic [31:0] InstCsrrsi = 32'h6073;
  localparam logic [31:0] InstCsrrsiMask = 32'h707f;
  localparam logic [31:0] InstCsrrci = 32'h7073;
  localparam logic [31:0] InstCsrrciMask = 32'h707f;
  localparam logic [31:0] InstMul = 32'h2000033;
  localparam logic [31:0] InstMulMask = 32'hfe00707f;
  localparam logic [31:0] InstMulh = 32'h2001033;
  localparam logic [31:0] InstMulhMask = 32'hfe00707f;
  localparam logic [31:0] InstMulhsu = 32'h2002033;
  localparam logic [31:0] InstMulhsuMask = 32'hfe00707f;
  localparam logic [31:0] InstMulhu = 32'h2003033;
  localparam logic [31:0] InstMulhuMask = 32'hfe00707f;
  localparam logic [31:0] InstDiv = 32'h2004033;
  localparam logic [31:0] InstDivMask = 32'hfe00707f;
  localparam logic [31:0] InstDivu = 32'h2005033;
  localparam logic [31:0] InstDivuMask = 32'hfe00707f;
  localparam logic [31:0] InstRem = 32'h2006033;
  localparam logic [31:0] InstRemMask = 32'hfe00707f;
  localparam logic [31:0] InstRemu = 32'h2007033;
  localparam logic [31:0] InstRemuMask = 32'hfe00707f;
  localparam logic [31:0] InstFault = 32'h53;
  localparam logic [31:0] InstFaultMask = 32'hfe00007f;
  localparam logic [1:0] PrivUser = 2'd0;
  localparam logic [1:0] PrivSuper = 2'd1;
  localparam logic [1:0] PrivMachine = 2'd3;
  localparam int unsigned IrqSSoft = 1;
  localparam int unsigned IrqMSoft = 3;
  localparam int unsigned IrqSTimer = 5;
  localparam int unsigned IrqMTimer = 7;
  localparam int unsigned IrqSExt = 9;
  localparam int unsigned IrqMExt = 11;
  localparam int unsigned IrqMask = ((1 << IrqMExt)   | (1 << IrqSExt)   |                       (1 << IrqMTimer) | (1 << IrqSTimer) |                       (1 << IrqMSoft)  | (1 << IrqSSoft));
  localparam int unsigned SrIpMtipR = IrqMTimer;
  localparam int unsigned SrIpMeipR = IrqMExt;
  localparam logic [11:0] CsrMstatus = 12'h300;
  localparam logic [31:0] CsrMstatusMask = 32'hFFFFFFFF;
  localparam logic [11:0] CsrMisa = 12'h301;
  localparam logic [31:0] MisaRv32 = 32'h40000000;
  localparam logic [31:0] MisaRvi = 32'h00000100;
  localparam logic [31:0] MisaRvm = 32'h00001000;
  localparam logic [11:0] CsrMedeleg = 12'h302;
  localparam logic [11:0] CsrMie = 12'h304;
  localparam int unsigned CsrMieMask = IrqMask;
  localparam logic [11:0] CsrMtvec = 12'h305;
  localparam logic [31:0] CsrMtvecMask = 32'hFFFFFFFF;
  localparam logic [11:0] CsrMscratch = 12'h340;
  localparam logic [31:0] CsrMscratchMask = 32'hFFFFFFFF;
  localparam logic [11:0] CsrMepc = 12'h341;
  localparam logic [31:0] CsrMepcMask = 32'hFFFFFFFF;
  localparam logic [11:0] CsrMcause = 12'h342;
  localparam logic [31:0] CsrMcauseMask = 32'h8000000F;
  localparam logic [11:0] CsrMip = 12'h344;
  localparam int unsigned CsrMipMask = IrqMask;
  localparam logic [11:0] CsrMtime = 12'hc01;
  localparam logic [31:0] CsrMtimeMask = 32'hFFFFFFFF;
  localparam logic [11:0] CsrMhartid = 12'hF14;
  localparam logic [11:0] CsrDflush = 12'h3a0;
  localparam logic [11:0] CsrDinvalidate = 12'h3a2;
  localparam int unsigned SrSieR = 1;
  localparam int unsigned SrMieR = 3;
  localparam int unsigned SrSpieR = 5;
  localparam int unsigned SrMpieR = 7;
  localparam int unsigned SrSppR = 8;
  localparam int unsigned SrMppMsb = 12;
  localparam int unsigned SrMppLsb = 11;
  localparam logic [1:0] SrMppU = PrivUser;
  localparam int unsigned McauseInt = 31;
  localparam int unsigned McauseMisalignedFetch = ((0 << McauseInt) | 0);
  localparam int unsigned McauseFaultFetch = ((0 << McauseInt) | 1);
  localparam int unsigned McauseIllegalInstruction = ((0 << McauseInt) | 2);
  localparam int unsigned McauseBreakpoint = ((0 << McauseInt) | 3);
  localparam int unsigned McauseMisalignedLoad = ((0 << McauseInt) | 4);
  localparam int unsigned McauseFaultLoad = ((0 << McauseInt) | 5);
  localparam int unsigned McauseMisalignedStore = ((0 << McauseInt) | 6);
  localparam int unsigned McauseFaultStore = ((0 << McauseInt) | 7);
  localparam int unsigned McauseEcallU = ((0 << McauseInt) | 8);
  localparam int unsigned McauseEcallS = ((0 << McauseInt) | 9);
  localparam int unsigned McauseEcallH = ((0 << McauseInt) | 10);
  localparam int unsigned McauseEcallM = ((0 << McauseInt) | 11);
  localparam int unsigned McausePageFaultInst = ((0 << McauseInt) | 12);
  localparam int unsigned McausePageFaultLoad = ((0 << McauseInt) | 13);
  localparam int unsigned McausePageFaultStore = ((0 << McauseInt) | 15);
  localparam int unsigned McauseInterrupt = (1 << McauseInt);
endpackage
