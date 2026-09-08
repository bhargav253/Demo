// SPDX-License-Identifier: Apache-2.0
module syst_fifo_tb;
  logic clk_i = 0;
  logic rst_ni = 0;
  logic in_push_i = 0, out_pop_i = 0;
  logic [1:0] in_pop_i = 0, out_push_i = 0;
  logic [3:0][7:0] in_data_i, out_data_o;
  logic [1:0][7:0] in_data_o, out_data_i;
  logic [1:0] in_valid_o;
  logic out_valid_o;
  byte unsigned in_queue[$], out_queue[$];
  int unsigned checks, seed, rng, cycles;
  string test_name, wave_file;
  syst_inf #(.DataWidth(8), .Depth(3)) u_input_fifo (
    .clk_i, .rst_ni, .push_i(in_push_i), .pop_i(in_pop_i),
    .data_i(in_data_i), .data_o(in_data_o), .data_valid_o(in_valid_o)
  );
  syst_outf #(.DataWidth(8), .Depth(2)) u_output_fifo (
    .clk_i, .rst_ni, .push_i(out_push_i), .pop_i(out_pop_i),
    .data_i(out_data_i), .data_o(out_data_o), .data_valid_o(out_valid_o)
  );
  initial forever #5ns clk_i = ~clk_i;
  function automatic int unsigned next_random();
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
  endfunction
  task automatic step(input bit ipush, input int unsigned ipop, opush, input bit opop);
    byte unsigned expected;
    @(negedge clk_i);
    if (in_valid_o !== (in_queue.size() > 1 ? 2'd2 : 2'(in_queue.size())))
      $fatal(1, "Input FIFO valid mismatch");
    if (out_valid_o !== (out_queue.size() >= 4)) $fatal(1, "Output FIFO valid mismatch");
    in_push_i = ipush;
    in_pop_i = 2'(ipop);
    out_push_i = 2'(opush);
    out_pop_i = opop;
    for (int n = 0; n < 4; n++) in_data_i[n] = 8'(next_random());
    for (int n = 0; n < 2; n++) out_data_i[n] = 8'(next_random());
    #1ns;
    for (int unsigned n = 0; n < ipop; n++) begin
      expected = in_queue.pop_front();
      if (in_data_o[n] !== expected) $fatal(1, "Input FIFO ordering check %0d", checks);
    end
    if (opop) for (int n = 0; n < 4; n++) begin
      expected = out_queue.pop_front();
      if (out_data_o[n] !== expected) $fatal(1, "Output FIFO ordering check %0d", checks);
    end
    if (ipush) for (int n = 0; n < 4; n++) in_queue.push_back(in_data_i[n]);
    for (int unsigned n = 0; n < opush; n++) out_queue.push_back(out_data_i[n]);
    checks++;
  endtask
  task automatic reset_fifos();
    @(negedge clk_i);
    rst_ni = 0;
    in_push_i = 0;
    in_pop_i = 0;
    out_push_i = 0;
    out_pop_i = 0;
    in_queue.delete();
    out_queue.delete();
    repeat (2) @(negedge clk_i);
    rst_ni = 1;
  endtask
  initial begin
    int unsigned ipop, opush;
    bit ipush, opop;
    seed = 1;
    cycles = 200;
    test_name = "directed";
    void'($value$plusargs("TEST=%s", test_name));
    void'($value$plusargs("SEED=%d", seed));
    void'($value$plusargs("CYCLES=%d", cycles));
    if ($value$plusargs("AXON_WAVE_FILE=%s", wave_file)) begin
      $dumpfile(wave_file);
      $dumpvars(0, syst_fifo_tb);
    end
    rng = seed == 0 ? 1 : seed;
    $display("TEST=%s SEED=%0d", test_name, seed);
    reset_fifos();
    if (test_name == "negative_underflow") begin
      @(negedge clk_i);
      in_pop_i = 1;
      repeat (2) @(negedge clk_i);
      $fatal(1, "ERROR: underflow assertion did not fire");
    end
    if (test_name != "directed" && test_name != "random" && test_name != "smoke")
      $fatal(1, "Unknown FIFO test %s", test_name);
    // Fill each FIFO exactly to capacity.
    step(1,0,2,0); step(1,0,2,0); step(1,0,2,0); step(0,0,2,0);
    // Simultaneous reads/writes, odd pointer positions and wrapping.
    step(0,1,2,1); step(0,1,2,0); step(0,2,1,1);
    step(1,2,1,0); step(0,2,0,0); step(0,2,0,0);
    reset_fifos();
    for (int unsigned n = 0; n < cycles; n++) begin
      ipop = next_random()%3;
      if (ipop > unsigned'(in_queue.size())) ipop = unsigned'(in_queue.size());
      ipush = (next_random()%2 != 0) && (in_queue.size()-int'(ipop) <= 8);
      opop = (out_queue.size() >= 4) && (next_random()%2 != 0);
      opush = next_random()%3;
      if (out_queue.size()+int'(opush)-(opop ? 4 : 0) > 8) opush = 0;
      step(ipush,ipop,opush,opop);
    end
    reset_fifos();
    step(0,0,0,0);
    $display("PASS: %0d FIFO checks", checks);
    $finish;
  end
endmodule
