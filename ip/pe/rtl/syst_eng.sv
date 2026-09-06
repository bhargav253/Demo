// SPDX-License-Identifier: Apache-2.0
//
// One buffered 2x2 systolic matrix-multiply engine.

module syst_eng #(
  parameter int unsigned DataWidth = 4,
  localparam int unsigned AccWidth = (2 * DataWidth) + 1
) (
  input  logic                               clk_i,
  input  logic                               rst_ni,
  input  logic [3:0][DataWidth-1:0]          a_i,
  input  logic [3:0][DataWidth-1:0]          b_i,
  input  logic                               push_i,
  output logic [3:0][AccWidth-1:0]           result_o,
  output logic                               result_valid_o,
  input  logic                               pop_i
);

  typedef enum logic [1:0] {
    Cycle0,
    Cycle1,
    Cycle2
  } state_t;

  logic [3:0][DataWidth-1:0] a_in;
  logic [3:0][DataWidth-1:0] a_out;
  logic [3:0][DataWidth-1:0] b_in;
  logic [3:0][DataWidth-1:0] b_out;
  logic [3:0][AccWidth-1:0]  acc_in;
  logic [3:0][AccWidth-1:0]  acc_out;
  logic [3:0]                a_slot_in;
  logic [3:0]                a_slot_out;
  logic [3:0]                b_slot_in;
  logic [3:0]                b_slot_out;
  logic [3:0]                a_valid_in;
  logic [3:0]                a_valid_out;
  logic [3:0]                b_valid_in;
  logic [3:0]                b_valid_out;
  logic [3:0]                acc_valid_in;
  logic [3:0]                acc_valid_out;

  logic [1:0][DataWidth-1:0] a_fifo_data;
  logic [1:0][DataWidth-1:0] b_fifo_data;
  logic [1:0][AccWidth-1:0]  result_fifo_data;
  logic [1:0]                a_fifo_pop;
  logic [1:0]                b_fifo_pop;
  logic [1:0]                result_fifo_push;
  logic [1:0]                b_fifo_valid;

  state_t state_q;
  state_t state_d;
  logic   slot_q;
  logic   slot_d;
  logic [1:0] element_slot;
  logic [1:0] element_valid;
  logic [1:0] element_pop;
  logic [1:0] element_slot_d1_q;
  logic [1:0] element_valid_d1_q;
  logic [1:0] element_pop_d1_q;
  logic [1:0] element_slot_d2_q;
  logic [1:0] element_valid_d2_q;
  logic [1:0] element_pop_d2_q;

  syst_inf #(
    .DataWidth ( DataWidth ),
    .Depth     ( 3         )
  ) u_b_fifo (
    .clk_i        ( clk_i        ),
    .rst_ni       ( rst_ni       ),
    .push_i       ( push_i       ),
    .data_i       ( b_i          ),
    .pop_i        ( b_fifo_pop   ),
    .data_o       ( b_fifo_data  ),
    .data_valid_o ( b_fifo_valid )
  );

  syst_inf #(
    .DataWidth ( DataWidth ),
    .Depth     ( 3         )
  ) u_a_fifo (
    .clk_i        ( clk_i       ),
    .rst_ni       ( rst_ni      ),
    .push_i       ( push_i      ),
    .data_i       ( a_i         ),
    .pop_i        ( a_fifo_pop  ),
    .data_o       ( a_fifo_data ),
    .data_valid_o (              )
  );

  syst_outf #(
    .DataWidth ( AccWidth ),
    .Depth     ( 2        )
  ) u_result_fifo (
    .clk_i        ( clk_i             ),
    .rst_ni       ( rst_ni            ),
    .push_i       ( result_fifo_push  ),
    .data_i       ( result_fifo_data  ),
    .pop_i        ( pop_i             ),
    .data_o       ( result_o          ),
    .data_valid_o ( result_valid_o    )
  );

  always_comb begin
    state_d       = state_q;
    element_pop   = '0;
    element_slot  = '0;
    element_valid = '0;
    slot_d        = slot_q;

    unique case (state_q)
      Cycle0: begin
        if (|b_fifo_valid) begin
          element_pop   = 2'd1;
          element_slot  = {slot_q, slot_q};
          element_valid = 2'b10;
          state_d       = Cycle1;
        end
      end
      Cycle1: begin
        element_pop   = 2'd2;
        element_slot  = {slot_q, slot_q};
        element_valid = 2'b11;
        state_d       = Cycle2;
      end
      Cycle2: begin
        element_pop  = (b_fifo_valid == 2'b10) ? 2'd2 : 2'd1;
        element_slot = {~slot_q, slot_q};
        element_valid = (b_fifo_valid == 2'b10) ? 2'b11 : 2'b01;
        slot_d       = ~slot_q;
        state_d      = (b_fifo_valid == 2'b10) ? Cycle1 : Cycle0;
      end
      default: state_d = Cycle0;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= Cycle0;
      slot_q  <= '0;
    end else begin
      state_q <= state_d;
      slot_q  <= slot_d;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      element_slot_d1_q  <= '0;
      element_slot_d2_q  <= '0;
      element_valid_d1_q <= '0;
      element_valid_d2_q <= '0;
      element_pop_d1_q   <= '0;
      element_pop_d2_q   <= '0;
    end else begin
      element_slot_d1_q  <= element_slot;
      element_slot_d2_q  <= element_slot_d1_q;
      element_valid_d1_q <= element_valid;
      element_valid_d2_q <= element_valid_d1_q;
      element_pop_d1_q   <= element_pop;
      element_pop_d2_q   <= element_pop_d1_q;
    end
  end

  assign b_fifo_pop = element_pop;
  assign b_in[0] = b_fifo_data[1];
  assign b_in[1] = b_fifo_data[0];
  assign b_slot_in[1:0] = element_slot;
  assign b_valid_in[1:0] = element_valid;

  assign a_fifo_pop = element_pop_d2_q;
  assign a_in[0] = a_fifo_data[1];
  assign a_in[2] = a_fifo_data[0];
  assign a_slot_in[0] = element_slot_d2_q[1];
  assign a_slot_in[2] = element_slot_d2_q[0];
  assign a_valid_in[0] = element_valid_d2_q[1];
  assign a_valid_in[2] = element_valid_d2_q[0];

  assign result_fifo_data = (acc_valid_out[3:2] == 2'b11)
                            ? {acc_out[2], acc_out[3]}
                            : (acc_valid_out[3] ? {acc_out[3], acc_out[3]}
                                               : {acc_out[2], acc_out[2]});
  assign result_fifo_push = (acc_valid_out[3:2] == 2'b11)
                            ? 2'b10 : ((|acc_valid_out[3:2]) ? 2'b01 : '0);

  assign a_in[1]       = a_out[0];
  assign a_slot_in[1]  = a_slot_out[0];
  assign a_valid_in[1] = a_valid_out[0];
  assign b_in[2]       = b_out[0];
  assign b_slot_in[2]  = b_slot_out[0];
  assign b_valid_in[2] = b_valid_out[0];
  assign acc_in[2]     = acc_out[0];
  assign acc_valid_in[2] = acc_valid_out[0];

  assign a_in[3]       = a_out[2];
  assign a_slot_in[3]  = a_slot_out[2];
  assign a_valid_in[3] = a_valid_out[2];
  assign b_in[3]       = b_out[1];
  assign b_slot_in[3]  = b_slot_out[1];
  assign b_valid_in[3] = b_valid_out[1];
  assign acc_in[3]     = acc_out[1];
  assign acc_valid_in[3] = acc_valid_out[1];

  assign acc_in[1:0]       = '0;
  assign acc_valid_in[1:0] = '0;

  for (genvar element = 0; element < 4; element++) begin : gen_mac
    syst_mac #(
      .DataWidth ( DataWidth )
    ) u_mac (
      .clk_i       ( clk_i                 ),
      .rst_ni      ( rst_ni                ),
      .a_i         ( a_in[element]         ),
      .a_slot_i    ( a_slot_in[element]    ),
      .a_valid_i   ( a_valid_in[element]   ),
      .a_o         ( a_out[element]        ),
      .a_slot_o    ( a_slot_out[element]   ),
      .a_valid_o   ( a_valid_out[element]  ),
      .b_i         ( b_in[element]         ),
      .b_slot_i    ( b_slot_in[element]    ),
      .b_valid_i   ( b_valid_in[element]   ),
      .b_o         ( b_out[element]        ),
      .b_slot_o    ( b_slot_out[element]   ),
      .b_valid_o   ( b_valid_out[element]  ),
      .acc_i       ( acc_in[element]       ),
      .acc_valid_i ( acc_valid_in[element] ),
      .acc_o       ( acc_out[element]      ),
      .acc_valid_o ( acc_valid_out[element])
    );
  end

endmodule
