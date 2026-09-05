// SPDX-License-Identifier: Apache-2.0
//
// Dual-buffered 2x2 systolic matrix-multiply prototype.

module syst #(
  parameter int unsigned DataWidth = 4,
  localparam int unsigned AccWidth = (2 * DataWidth) + 1
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic                 input_valid_i,
  input  logic [DataWidth-1:0] a11_i,
  input  logic [DataWidth-1:0] a12_i,
  input  logic [DataWidth-1:0] a21_i,
  input  logic [DataWidth-1:0] a22_i,
  input  logic [DataWidth-1:0] b11_i,
  input  logic [DataWidth-1:0] b12_i,
  input  logic [DataWidth-1:0] b21_i,
  input  logic [DataWidth-1:0] b22_i,
  output logic                 result_valid_o,
  output logic [AccWidth-1:0]  c11_o,
  output logic [AccWidth-1:0]  c12_o,
  output logic [AccWidth-1:0]  c21_o,
  output logic [AccWidth-1:0]  c22_o
);

  logic [1:0][3:0][AccWidth-1:0]  engine_result;
  logic [1:0]                      engine_result_valid;
  logic [3:0][DataWidth-1:0]      engine_a;
  logic [3:0][DataWidth-1:0]      engine_b;
  logic [1:0]                      engine_push;
  logic [1:0]                      engine_pop;
  logic                            push_select_q;
  logic                            pop_select_q;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      push_select_q <= '0;
    end else if (input_valid_i) begin
      push_select_q <= ~push_select_q;
    end
  end

  assign engine_push[0] = !push_select_q && input_valid_i;
  assign engine_push[1] =  push_select_q && input_valid_i;
  assign engine_a = {a22_i, a21_i, a12_i, a11_i};
  assign engine_b = {b12_i, b11_i, b22_i, b21_i};

  assign result_valid_o = engine_result_valid[pop_select_q];

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pop_select_q <= '1;
    end else if (result_valid_o) begin
      pop_select_q <= ~pop_select_q;
    end
  end

  assign c11_o = engine_result[pop_select_q][0];
  assign c12_o = engine_result[pop_select_q][1];
  assign c21_o = engine_result[pop_select_q][2];
  assign c22_o = engine_result[pop_select_q][3];

  assign engine_pop[0] = !pop_select_q && engine_result_valid[0];
  assign engine_pop[1] =  pop_select_q && engine_result_valid[1];

  for (genvar engine = 0; engine < 2; engine++) begin : gen_engine
    syst_eng #(
      .DataWidth ( DataWidth )
    ) u_engine (
      .clk_i          ( clk_i                       ),
      .rst_ni         ( rst_ni                      ),
      .a_i            ( engine_a                    ),
      .b_i            ( engine_b                    ),
      .push_i         ( engine_push[engine]         ),
      .result_o       ( engine_result[engine]       ),
      .result_valid_o ( engine_result_valid[engine] ),
      .pop_i          ( engine_pop[engine]          )
    );
  end

endmodule
