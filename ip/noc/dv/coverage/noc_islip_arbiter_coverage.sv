// SPDX-License-Identifier: Apache-2.0

module noc_islip_arbiter_coverage #(
  parameter int unsigned NumPorts = 4
) (
  input logic                               clk_i,
  input logic                               rst_ni,
  input logic [NumPorts-1:0][NumPorts-1:0] req_i,
  input logic [NumPorts-1:0][NumPorts-1:0] match_o
);

  /* verilator coverage_off */

  logic any_input_contention;
  logic any_output_contention;
  logic multiple_matches;

  always_comb begin
    any_input_contention  = 1'b0;
    any_output_contention = 1'b0;
    multiple_matches      = ($countones(match_o) > 1);

    for (int unsigned input_idx = 0; input_idx < NumPorts; input_idx++) begin
      if ($countones(req_i[input_idx]) > 1) any_input_contention = 1'b1;
    end
    for (int unsigned output_idx = 0; output_idx < NumPorts; output_idx++) begin
      int unsigned request_count;
      request_count = 0;
      for (int unsigned input_idx = 0; input_idx < NumPorts; input_idx++) begin
        request_count += int'(req_i[input_idx][output_idx]);
      end
      if (request_count > 1) any_output_contention = 1'b1;
    end
  end

  /* verilator coverage_on */

  cp_idle: cover property (@(posedge clk_i) rst_ni && (req_i == '0));
  cp_any_match: cover property (@(posedge clk_i) rst_ni && (match_o != '0));
  cp_all_to_all_contention: cover property (
    @(posedge clk_i) rst_ni && (req_i == '1)
  );
  cp_input_contention: cover property (
    @(posedge clk_i) rst_ni && any_input_contention
  );
  cp_output_contention: cover property (
    @(posedge clk_i) rst_ni && any_output_contention
  );
  cp_multiple_independent_matches: cover property (
    @(posedge clk_i) rst_ni && multiple_matches
  );

  for (genvar input_idx = 0; input_idx < NumPorts; input_idx++) begin : gen_input
    cp_input_matched: cover property (
      @(posedge clk_i) rst_ni && (|match_o[input_idx])
    );
    for (genvar output_idx = 0; output_idx < NumPorts; output_idx++) begin : gen_output
      cp_input_output_pair: cover property (
        @(posedge clk_i) rst_ni && match_o[input_idx][output_idx]
      );
    end
  end

  for (genvar output_idx = 0; output_idx < NumPorts; output_idx++) begin : gen_output
    logic output_matched;
    always_comb begin
      output_matched = 1'b0;
      for (int unsigned input_idx = 0; input_idx < NumPorts; input_idx++) begin
        output_matched |= match_o[input_idx][output_idx];
      end
    end
    cp_output_matched: cover property (@(posedge clk_i) rst_ni && output_matched);
  end

endmodule

bind noc_islip_arbiter noc_islip_arbiter_coverage #(
  .NumPorts ( NumPorts )
) u_coverage (
  .clk_i,
  .rst_ni,
  .req_i,
  .match_o
);
