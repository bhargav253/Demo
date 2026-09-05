// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Leading one detector based on parallel prefix computation
// See also: prim_arbiter_ppc

module prim_leading_one_ppc #(
  parameter int unsigned NumReq = 8,
  localparam int IdxW      = prim_util_pkg::vbits(NumReq)
) (
  input  logic [NumReq-1:0] in_i,
  output logic [NumReq-1:0] leading_one_o,
  output logic [NumReq-1:0] ppc_out_o,
  output logic [IdxW-1:0]   idx_o
);
  logic [NumReq-1:0] ppc_out;

  // PPC
  // Even though this source looks O(n), synthesis tools can optimize the
  // prefix expression into a logarithmic implementation.
  for (genvar i = 0; i < NumReq; i++) begin : gen_prefix
    assign ppc_out[i] = |in_i[i:0];
  end

  // Leading-One detector
  assign leading_one_o = ppc_out ^ {ppc_out[NumReq-2:0], 1'b0};
  assign ppc_out_o     = ppc_out;

  always_comb begin
    idx_o = '0;
    for (int unsigned i = 0 ; i < NumReq ; i++) begin
      if (leading_one_o[i]) begin
        idx_o = i[IdxW-1:0];
      end
    end
  end

endmodule
