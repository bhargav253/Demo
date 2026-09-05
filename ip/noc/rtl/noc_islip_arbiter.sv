// SPDX-License-Identifier: Apache-2.0
//
// One scheduling iteration of an iSLIP input/output arbiter.
// req_i[input][output] and match_o[input][output] use the same orientation.

`include "prim_assert.sv"

module noc_islip_arbiter #(
  parameter int unsigned NumPorts = 4
) (
  input  logic                               clk_i,
  input  logic                               rst_ni,
  input  logic [NumPorts-1:0][NumPorts-1:0] req_i,
  output logic [NumPorts-1:0][NumPorts-1:0] match_o
);

  logic [NumPorts-1:0][NumPorts-1:0] grant;
  logic [NumPorts-1:0][NumPorts-1:0] grant_mask_q;
  logic [NumPorts-1:0][NumPorts-1:0] grant_mask_next;
  logic [NumPorts-1:0][NumPorts-1:0] accept_mask_q;
  logic [NumPorts-1:0][NumPorts-1:0] accept_mask_next;

  `ASSERT_INIT(NumPortsPositive_A, NumPorts > 0)

  for (genvar output_idx = 0; output_idx < NumPorts; output_idx++) begin : gen_grant
    logic [NumPorts-1:0] output_req;

    always_comb begin
      for (int input_idx = 0; input_idx < NumPorts; input_idx++) begin
        output_req[input_idx] = req_i[input_idx][output_idx];
      end
    end

    prim_arbiter_rr_select #(
      .NumReq ( NumPorts )
    ) u_grant_select (
      .req_i       ( output_req                  ),
      .mask_i      ( grant_mask_q[output_idx]    ),
      .gnt_o       ( grant[output_idx]           ),
      .mask_next_o ( grant_mask_next[output_idx] )
    );
  end

   for (genvar input_idx = 0; input_idx < NumPorts; input_idx++) begin : gen_accept
      logic [NumPorts-1:0] input_grants;

      always_comb begin
         for (int output_idx = 0; output_idx < NumPorts; output_idx++) begin
            input_grants[output_idx] = grant[output_idx][input_idx];
         end
      end

    prim_arbiter_rr_select #(
      .NumReq ( NumPorts )
    ) u_accept_select (
      .req_i       ( input_grants                ),
      .mask_i      ( accept_mask_q[input_idx]    ),
      .gnt_o       ( match_o[input_idx]          ),
      .mask_next_o ( accept_mask_next[input_idx] )
    );
  end

   always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
         grant_mask_q  <= '0;
         accept_mask_q <= '0;
      end else begin
         for (int input_idx = 0; input_idx < NumPorts; input_idx++) begin
            for (int output_idx = 0; output_idx < NumPorts; output_idx++) begin
               if (match_o[input_idx][output_idx]) begin
                  grant_mask_q[output_idx] <= grant_mask_next[output_idx];
                  accept_mask_q[input_idx] <= accept_mask_next[input_idx];
               end
            end
         end
      end
   end

endmodule
