// SPDX-License-Identifier: Apache-2.0
//
// Two-entry ready/valid pipeline slice.

`include "prim_assert.sv"

module prim_slice #(
  parameter int unsigned Width = 8
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [Width-1:0] in_data_i,
  input  logic             in_valid_i,
  output logic             in_ready_o,
  output logic [Width-1:0] out_data_o,
  output logic             out_valid_o,
  input  logic             out_ready_i
);

  logic [1:0] valid_d, valid_q;
  logic       [1:0][Width-1:0] data_d, data_q;
  logic       push, pop;

  assign in_ready_o  = !valid_q[1];
  assign out_data_o  = data_q[0];
  assign out_valid_o = valid_q[0];
  assign push = in_valid_i && in_ready_o;
  assign pop  = out_valid_o && out_ready_i;

  always_comb begin
    valid_d = valid_q;
    data_d  = data_q;

    unique case ({push, pop})
      2'b10: begin
        if (!valid_q[0]) begin
          valid_d[0] = 1'b1;
          data_d[0]  = in_data_i;
        end else begin
          valid_d[1] = 1'b1;
          data_d[1]  = in_data_i;
        end
      end
      2'b01: begin
        valid_d[0] = valid_q[1];
        data_d[0]  = data_q[1];
        valid_d[1] = 1'b0;
      end
      2'b11: begin
        if (valid_q[1]) begin
          data_d[0]  = data_q[1];
          valid_d[1] = 1'b1;
          data_d[1]  = in_data_i;
        end else begin
          valid_d[0] = 1'b1;
          data_d[0]  = in_data_i;
        end
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      valid_q <= '0;
      data_q  <= '0;
    end else begin
      valid_q <= valid_d;
      data_q  <= data_d;
    end
  end

  `ASSERT_INIT(WidthValid_A, Width > 0)
  `ASSERT(EntriesContiguous_A, valid_q[1] |-> valid_q[0])
  `ASSERT(DataStableWhenStalled_A,
          out_valid_o && !out_ready_i |=> out_valid_o && $stable(out_data_o))

endmodule : prim_slice
