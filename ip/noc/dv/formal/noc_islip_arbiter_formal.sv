// SPDX-License-Identifier: Apache-2.0

module noc_islip_arbiter_formal #(
  parameter int unsigned NumPorts = 4
);

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  logic past_valid = 1'b0;
  (* anyseq *) logic [(NumPorts*NumPorts)-1:0] req_next;
  logic [(NumPorts*NumPorts)-1:0] req_flat = '0;
  logic [NumPorts-1:0][NumPorts-1:0] req_i;
  logic [NumPorts-1:0][NumPorts-1:0] match_o;
  logic [NumPorts-1:0][NumPorts-1:0] grant_mask;
  logic [NumPorts-1:0][NumPorts-1:0] accept_mask;
  logic [NumPorts-1:0][NumPorts-1:0] match_prev = '0;
  logic [NumPorts-1:0][NumPorts-1:0] grant_mask_prev = '0;
  logic [NumPorts-1:0][NumPorts-1:0] accept_mask_prev = '0;
  logic rst_prev = 1'b0;

  assign req_i = req_flat;

  always @($global_clock) begin
    req_flat <= req_next;
  end

  noc_islip_arbiter #(
    .NumPorts ( NumPorts )
  ) u_dut (
    .clk_i   ( clk_i   ),
    .rst_ni  ( rst_ni  ),
    .req_i   ( req_i   ),
    .match_o ( match_o ),
    .grant_mask_o  ( grant_mask  ),
    .accept_mask_o ( accept_mask )
  );

  always @($global_clock) begin
    past_valid       <= 1'b1;
    rst_ni           <= 1'b1;
    rst_prev         <= rst_ni;
    match_prev       <= match_o;
    grant_mask_prev  <= grant_mask;
    accept_mask_prev <= accept_mask;
  end

  for (genvar input_idx = 0; input_idx < NumPorts; input_idx++) begin : gen_input_properties
    always @($global_clock) begin
      assert ((match_o[input_idx] & (match_o[input_idx] - 1'b1)) == '0);
      if (past_valid && rst_ni && rst_prev && (match_prev[input_idx] == '0)) begin
        assert (accept_mask[input_idx] == accept_mask_prev[input_idx]);
      end
    end
  end

  always @($global_clock) begin
    assert ((match_o & ~req_flat) == '0);
  end

  for (genvar output_idx = 0; output_idx < NumPorts; output_idx++) begin : gen_output_properties
    logic [NumPorts-1:0] output_matches;
    logic [NumPorts-1:0] output_matches_prev;
    for (genvar input_idx = 0; input_idx < NumPorts; input_idx++) begin : gen_transpose
      assign output_matches[input_idx]      = match_o[input_idx][output_idx];
      assign output_matches_prev[input_idx] = match_prev[input_idx][output_idx];
    end
    always @($global_clock) begin
      assert ((output_matches & (output_matches - 1'b1)) == '0);
      if (past_valid && rst_ni && rst_prev) begin
        if (output_matches_prev == '0) begin
          assert (grant_mask[output_idx] == grant_mask_prev[output_idx]);
        end
        cover ((output_matches_prev != '0) && (grant_mask[output_idx] == '0) &&
               (grant_mask_prev[output_idx] != '0));
      end
    end
  end

  always @($global_clock) begin
    if (rst_ni) begin
      cover ($countones(req_i) > NumPorts);
      cover ($countones(match_o) > 1);
    end
  end

  always @($global_clock) begin
    if (past_valid) begin
      if (!rst_prev) begin
        assert (grant_mask == '0);
        assert (accept_mask == '0);
      end
    end
  end

endmodule
