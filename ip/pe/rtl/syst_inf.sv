// SPDX-License-Identifier: Apache-2.0
//
// Width-converting FIFO: push four elements and pop one or two elements.

module syst_inf #(
  parameter int unsigned DataWidth = 4,
  parameter int unsigned Depth     = 2,
  localparam int unsigned NumEntries = Depth * 4,
  localparam int unsigned CountWidth = $clog2(NumEntries + 1),
  localparam int unsigned ReadPtrWidth = $clog2(NumEntries),
  localparam int unsigned WritePtrWidth = $clog2(Depth)
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,
  input  logic                          push_i,
  input  logic [3:0][DataWidth-1:0]     data_i,
  input  logic [1:0]                    pop_i,
  output logic [1:0][DataWidth-1:0]     data_o,
  output logic [1:0]                    data_valid_o
);

  typedef logic [Depth-1:0][3:0][DataWidth-1:0] write_format_t;
  typedef logic [NumEntries-1:0][DataWidth-1:0] read_format_t;

  write_format_t                  data_q;
  read_format_t                   read_data;
  logic [CountWidth-1:0]          count_q;
  logic [ReadPtrWidth-1:0]        read_ptr_q;
  logic [WritePtrWidth-1:0]       write_ptr_q;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      read_ptr_q <= '0;
    end else if (pop_i == 2'b10) begin
      if (read_ptr_q == ReadPtrWidth'(NumEntries - 1)) begin
        read_ptr_q <= ReadPtrWidth'(1);
      end else if (read_ptr_q == ReadPtrWidth'(NumEntries - 2)) begin
        read_ptr_q <= '0;
      end else begin
        read_ptr_q <= read_ptr_q + ReadPtrWidth'(2);
      end
    end else if (pop_i == 2'b01) begin
      read_ptr_q <= (read_ptr_q == ReadPtrWidth'(NumEntries - 1))
                    ? '0 : read_ptr_q + ReadPtrWidth'(1);
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      write_ptr_q <= '0;
    end else if (push_i) begin
      write_ptr_q <= (write_ptr_q == WritePtrWidth'(Depth - 1))
                     ? '0 : write_ptr_q + WritePtrWidth'(1);
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      data_q <= '0;
    end else if (push_i) begin
      data_q[write_ptr_q] <= data_i;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      count_q <= '0;
    end else if (push_i && (|pop_i)) begin
      count_q <= count_q - CountWidth'(pop_i) + CountWidth'(4);
    end else if (push_i) begin
      count_q <= count_q + CountWidth'(4);
    end else if (|pop_i) begin
      count_q <= count_q - CountWidth'(pop_i);
    end
  end

  assign read_data = read_format_t'(data_q);

  always_comb begin
    if (pop_i == 2'b10) begin
      data_o = (read_ptr_q == ReadPtrWidth'(NumEntries - 1))
               ? {read_data[0], read_data[read_ptr_q]}
               : {read_data[read_ptr_q+1'b1], read_data[read_ptr_q]};
    end else if (pop_i == 2'b01) begin
      data_o = {read_data[read_ptr_q], read_data[read_ptr_q]};
    end else begin
      data_o = '0;
    end
  end

  always_comb begin
    if (count_q > CountWidth'(1)) begin
      data_valid_o = 2'b10;
    end else if (count_q == CountWidth'(1)) begin
      data_valid_o = 2'b01;
    end else begin
      data_valid_o = '0;
    end
  end

endmodule
