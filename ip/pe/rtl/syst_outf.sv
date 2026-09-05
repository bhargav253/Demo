// SPDX-License-Identifier: Apache-2.0
//
// Width-converting FIFO: push one or two elements and pop four elements.

module syst_outf #(
  parameter int unsigned DataWidth = 4,
  parameter int unsigned Depth     = 2,
  localparam int unsigned NumEntries = Depth * 4,
  localparam int unsigned CountWidth = $clog2(NumEntries + 1),
  localparam int unsigned ReadPtrWidth = $clog2(Depth),
  localparam int unsigned WritePtrWidth = $clog2(NumEntries)
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,
  input  logic [1:0]                    push_i,
  input  logic [1:0][DataWidth-1:0]     data_i,
  input  logic                          pop_i,
  output logic [3:0][DataWidth-1:0]     data_o,
  output logic                          data_valid_o
);

  typedef logic [Depth-1:0][3:0][DataWidth-1:0] read_format_t;
  typedef logic [NumEntries-1:0][DataWidth-1:0] write_format_t;

  read_format_t                  read_data;
  write_format_t                 data_q;
  logic [CountWidth-1:0]         count_q;
  logic [ReadPtrWidth-1:0]       read_ptr_q;
  logic [WritePtrWidth-1:0]      write_ptr_q;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      write_ptr_q <= '0;
    end else if (push_i == 2'b10) begin
      if (write_ptr_q == WritePtrWidth'(NumEntries - 1)) begin
        write_ptr_q <= WritePtrWidth'(1);
      end else if (write_ptr_q == WritePtrWidth'(NumEntries - 2)) begin
        write_ptr_q <= '0;
      end else begin
        write_ptr_q <= write_ptr_q + WritePtrWidth'(2);
      end
    end else if (push_i == 2'b01) begin
      write_ptr_q <= (write_ptr_q == WritePtrWidth'(NumEntries - 1))
                     ? '0 : write_ptr_q + WritePtrWidth'(1);
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      read_ptr_q <= '0;
    end else if (pop_i) begin
      read_ptr_q <= (read_ptr_q == ReadPtrWidth'(Depth - 1))
                    ? '0 : read_ptr_q + ReadPtrWidth'(1);
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      data_q <= '0;
    end else if (push_i == 2'b10) begin
      data_q[write_ptr_q] <= data_i[0];
      if (write_ptr_q == WritePtrWidth'(NumEntries - 1)) begin
        data_q[0] <= data_i[1];
      end else begin
        data_q[write_ptr_q+1'b1] <= data_i[1];
      end
    end else if (push_i == 2'b01) begin
      data_q[write_ptr_q] <= data_i[0];
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      count_q <= '0;
    end else if ((|push_i) && pop_i) begin
      count_q <= count_q + CountWidth'(push_i) - CountWidth'(4);
    end else if (|push_i) begin
      count_q <= count_q + CountWidth'(push_i);
    end else if (pop_i) begin
      count_q <= count_q - CountWidth'(4);
    end
  end

  assign read_data    = read_format_t'(data_q);
  assign data_o       = read_data[read_ptr_q];
  assign data_valid_o = count_q >= CountWidth'(4);

endmodule
