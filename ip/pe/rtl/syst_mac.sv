// SPDX-License-Identifier: Apache-2.0
//
// One multiply-accumulate element with double-buffered B operands.

module syst_mac #(
  parameter int unsigned DataWidth = 4,
  localparam int unsigned AccWidth = (2 * DataWidth) + 1
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  logic [DataWidth-1:0] a_i,
  input  logic                 a_slot_i,
  input  logic                 a_valid_i,
  output logic [DataWidth-1:0] a_o,
  output logic                 a_slot_o,
  output logic                 a_valid_o,

  input  logic [DataWidth-1:0] b_i,
  input  logic                 b_slot_i,
  input  logic                 b_valid_i,
  output logic [DataWidth-1:0] b_o,
  output logic                 b_slot_o,
  output logic                 b_valid_o,

  input  logic [AccWidth-1:0]  acc_i,
  input  logic                 acc_valid_i,
  output logic [AccWidth-1:0]  acc_o,
  output logic                 acc_valid_o
);

  logic [1:0][DataWidth-1:0] weight_q;
  logic [(2*DataWidth)-1:0]  product;

  assign product = a_i * weight_q[a_slot_i];

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      a_o       <= '0;
      a_slot_o  <= '0;
      a_valid_o <= '0;
    end else begin
      a_o       <= a_i;
      a_slot_o  <= a_slot_i;
      a_valid_o <= a_valid_i;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      weight_q <= '0;
    end else if (b_valid_i) begin
      weight_q[b_slot_i] <= b_i;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      b_o       <= '0;
      b_slot_o  <= '0;
      b_valid_o <= '0;
    end else begin
      b_o       <= weight_q[b_slot_i];
      b_slot_o  <= b_slot_i;
      b_valid_o <= b_valid_i;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      acc_o       <= '0;
      acc_valid_o <= '0;
    end else begin
      acc_o       <= acc_valid_i ? (acc_i + product) : AccWidth'(product);
      acc_valid_o <= a_valid_i;
    end
  end

endmodule
