// SPDX-License-Identifier: Apache-2.0
module syst_tb;
  localparam int unsigned DataWidth = 4;
  localparam int unsigned AccWidth = 2*DataWidth+1;
  logic clk_i = 0;
  logic rst_ni = 0;
  logic input_valid_i = 0;
  logic [3:0][DataWidth-1:0] a_i, b_i;
  logic [3:0][AccWidth-1:0] c_o;
  logic result_valid_o;
  logic [3:0][AccWidth-1:0] expected_q[$];
  int unsigned submitted, received, cycles, seed, rng;
  string test_name, wave_file;

  syst u_dut (
    .clk_i, .rst_ni, .input_valid_i,
    .a11_i(a_i[0]), .a12_i(a_i[1]), .a21_i(a_i[2]), .a22_i(a_i[3]),
    .b11_i(b_i[0]), .b12_i(b_i[1]), .b21_i(b_i[2]), .b22_i(b_i[3]),
    .c11_o(c_o[0]), .c12_o(c_o[1]), .c21_o(c_o[2]), .c22_o(c_o[3]),
    .result_valid_o
  );
  initial forever #5ns clk_i = ~clk_i;

  function automatic int unsigned next_random();
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
  endfunction

  // All drive/check operations are on falling edges, before DUT consumption.
  task automatic tick(input bit valid, input logic [15:0] a, b);
    logic [3:0][AccWidth-1:0] expected;
    @(negedge clk_i);
    if (rst_ni && result_valid_o) begin
      if (expected_q.size() == 0) $fatal(1, "Unexpected result");
      expected = expected_q.pop_front();
      if (c_o !== expected)
        $fatal(1, "Result %0d: got %p expected %p", received, c_o, expected);
      received++;
    end
    input_valid_i = valid;
    a_i = a;
    b_i = b;
    if (valid) begin
      expected[0] = AccWidth'(a_i[0])*AccWidth'(b_i[0]) + AccWidth'(a_i[1])*AccWidth'(b_i[2]);
      expected[1] = AccWidth'(a_i[0])*AccWidth'(b_i[1]) + AccWidth'(a_i[1])*AccWidth'(b_i[3]);
      expected[2] = AccWidth'(a_i[2])*AccWidth'(b_i[0]) + AccWidth'(a_i[3])*AccWidth'(b_i[2]);
      expected[3] = AccWidth'(a_i[2])*AccWidth'(b_i[1]) + AccWidth'(a_i[3])*AccWidth'(b_i[3]);
      expected_q.push_back(expected);
      submitted++;
    end
  endtask

  task automatic drain();
    repeat (80) tick(0, '0, '0);
    if (expected_q.size() != 0) $fatal(1, "Missing %0d results", expected_q.size());
  endtask

  task automatic reset_dut();
    @(negedge clk_i);
    rst_ni = 0;
    input_valid_i = 0;
    expected_q.delete();
    repeat (3) @(negedge clk_i);
    if (result_valid_o) $fatal(1, "Valid survived reset");
    rst_ni = 1;
  endtask

  initial begin
    if ($value$plusargs("AXON_WAVE_FILE=%s", wave_file)) begin
      $dumpfile(wave_file);
      $dumpvars(0, syst_tb);
    end
    test_name = "smoke";
    seed = 1;
    cycles = 200;
    void'($value$plusargs("TEST=%s", test_name));
    void'($value$plusargs("SEED=%d", seed));
    void'($value$plusargs("CYCLES=%d", cycles));
    rng = seed == 0 ? 1 : seed;
    $display("TEST=%s SEED=%0d CYCLES=%0d", test_name, seed, cycles);
    reset_dut();
    if (test_name != "smoke" && test_name != "directed" && test_name != "random")
      $fatal(1, "Unknown test %s", test_name);
    tick(1, 16'h4321, 16'h8765);
    tick(1, 16'h1234, 16'h5678);
    drain();
    if (test_name != "smoke") begin
      tick(1, '0, '1);
      tick(1, '1, '1);
      drain();
      for (int unsigned n = 0; n < cycles; n++) begin
        tick(1, 16'(next_random()), 16'(next_random()));
        if (test_name == "random") repeat (next_random()%4) tick(0, '0, '0);
      end
      drain();
      tick(1, 16'h1234, 16'h1001);
      reset_dut();
      tick(1, 16'h5678, 16'h1001);
      tick(1, 16'h9abc, 16'h1001);
      drain();
    end
    $display("PASS: submitted=%0d received=%0d (reset cancels pending work)", submitted, received);
    $finish;
  end
endmodule
