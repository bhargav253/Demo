// SPDX-License-Identifier: Apache-2.0
//
// Stateless round-robin selection. The owner supplies the current priority
// mask and decides when to commit mask_next_o. This is useful when selection
// and acceptance are separate protocol phases, as they are in iSLIP.

module prim_arbiter_rr_select #(
  parameter int unsigned NumReq = 4
) (
  input  logic [NumReq-1:0] req_i,
  input  logic [NumReq-1:0] mask_i,
  output logic [NumReq-1:0] gnt_o,
  output logic [NumReq-1:0] mask_next_o
);

  if (NumReq == 1) begin : gen_single_request
    assign gnt_o       = req_i;
    assign mask_next_o = mask_i & '0;
  end else begin : gen_multiple_requests
    logic [NumReq-1:0] masked_req;
    logic [NumReq-1:0] selected_req;
    logic [NumReq-1:0] ppc_out;
    logic [prim_util_pkg::vbits(NumReq)-1:0] unused_idx;

    assign masked_req   = req_i & mask_i;
    assign selected_req = (|masked_req) ? masked_req : req_i;

    prim_leading_one_ppc #(
      .NumReq ( NumReq )
    ) u_leading_one (
      .in_i          ( selected_req ),
      .leading_one_o ( gnt_o        ),
      .ppc_out_o     ( ppc_out      ),
      .idx_o         ( unused_idx   )
    );

    // Move priority to the request immediately above the selected request.
    assign mask_next_o = ppc_out << 1;
  end

endmodule
