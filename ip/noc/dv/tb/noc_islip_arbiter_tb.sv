// SPDX-License-Identifier: Apache-2.0

module noc_islip_arbiter_tb;

  localparam int unsigned NumPorts = 4;
  localparam time ClockPeriod = 10ns;

  logic                               clk_i;
  logic                               rst_ni;
  logic [NumPorts-1:0][NumPorts-1:0] req_i;
  logic [NumPorts-1:0][NumPorts-1:0] match_o;

  int unsigned grant_priority[NumPorts];
  int unsigned accept_priority[NumPorts];
  int unsigned checks;
  int unsigned random_cycles;
  int unsigned seed;
  string       test_name;

  noc_islip_arbiter #(
    .NumPorts ( NumPorts )
  ) u_dut (
    .clk_i,
    .rst_ni,
    .req_i,
    .match_o
  );

  initial begin
    clk_i = 1'b0;
    forever #(ClockPeriod / 2) clk_i = ~clk_i;
  end

  task automatic reset_reference_model();
    for (int unsigned port = 0; port < NumPorts; port++) begin
      grant_priority[port]  = 0;
      accept_priority[port] = 0;
    end
  endtask

  task automatic calculate_expected(
    input  logic [NumPorts-1:0][NumPorts-1:0] request,
    output logic [NumPorts-1:0][NumPorts-1:0] expected
  );
    logic [NumPorts-1:0][NumPorts-1:0] grant;

    grant    = '0;
    expected = '0;

    // Each output grants the first request at or after its current priority,
    // wrapping at NumPorts. This is intentionally independent of the DUT mask.
    for (int unsigned output_idx = 0; output_idx < NumPorts; output_idx++) begin
      bit selected;
      selected = 1'b0;
      for (int unsigned offset = 0; offset < NumPorts; offset++) begin
        int unsigned input_idx;
        input_idx = (grant_priority[output_idx] + offset) % NumPorts;
        if (!selected && request[input_idx][output_idx]) begin
          grant[output_idx][input_idx] = 1'b1;
          selected = 1'b1;
        end
      end
    end

    // Each input accepts at most one of its grants using its own priority.
    for (int unsigned input_idx = 0; input_idx < NumPorts; input_idx++) begin
      bit selected;
      selected = 1'b0;
      for (int unsigned offset = 0; offset < NumPorts; offset++) begin
        int unsigned output_idx;
        output_idx = (accept_priority[input_idx] + offset) % NumPorts;
        if (!selected && grant[output_idx][input_idx]) begin
          expected[input_idx][output_idx] = 1'b1;
          selected = 1'b1;
        end
      end
    end
  endtask

  task automatic commit_reference_model(
    input logic [NumPorts-1:0][NumPorts-1:0] expected
  );
    for (int unsigned input_idx = 0; input_idx < NumPorts; input_idx++) begin
      for (int unsigned output_idx = 0; output_idx < NumPorts; output_idx++) begin
        if (expected[input_idx][output_idx]) begin
          grant_priority[output_idx]  = (input_idx + 1) % NumPorts;
          accept_priority[input_idx] = (output_idx + 1) % NumPorts;
        end
      end
    end
  endtask

  task automatic check_invariants(
    input logic [NumPorts-1:0][NumPorts-1:0] request,
    input string                                description
  );
    for (int unsigned input_idx = 0; input_idx < NumPorts; input_idx++) begin
      int unsigned input_matches;
      input_matches = 0;
      for (int unsigned output_idx = 0; output_idx < NumPorts; output_idx++) begin
        if (match_o[input_idx][output_idx]) begin
          input_matches++;
          if (!request[input_idx][output_idx]) begin
            $fatal(1, "Unrequested match in %s", description);
          end
        end
      end
      if (input_matches > 1) begin
        $fatal(1, "Input %0d matched more than once in %s", input_idx, description);
      end
    end

    for (int unsigned output_idx = 0; output_idx < NumPorts; output_idx++) begin
      int unsigned output_matches;
      output_matches = 0;
      for (int unsigned input_idx = 0; input_idx < NumPorts; input_idx++) begin
        if (match_o[input_idx][output_idx]) output_matches++;
      end
      if (output_matches > 1) begin
        $fatal(1, "Output %0d matched more than once in %s", output_idx, description);
      end
    end
  endtask

  task automatic step(
    input logic [NumPorts-1:0][NumPorts-1:0] request,
    input string                                description
  );
    logic [NumPorts-1:0][NumPorts-1:0] expected;

    @(negedge clk_i);
    req_i = request;
    #1ns;
    calculate_expected(request, expected);
    checks++;
    check_invariants(request, description);
    if (match_o !== expected) begin
      $display("FAIL: %s", description);
      $display("  request  = %b", request);
      $display("  expected = %b", expected);
      $display("  actual   = %b", match_o);
      $fatal(1, "iSLIP mismatch at check %0d", checks);
    end

    @(posedge clk_i);
    #1ns;
    commit_reference_model(expected);
  endtask

  task automatic apply_reset();
    @(negedge clk_i);
    req_i  = '0;
    rst_ni = 1'b0;
    repeat (2) @(posedge clk_i);
    #1ns;
    reset_reference_model();
    @(negedge clk_i);
    rst_ni = 1'b1;
  endtask

  task automatic run_smoke();
    logic [NumPorts-1:0][NumPorts-1:0] request;

    request = '0;
    step(request, "idle request matrix");

    request       = '0;
    request[2][1] = 1'b1;
    step(request, "single request");

    request       = '0;
    request[0][0] = 1'b1;
    request[3][2] = 1'b1;
    step(request, "independent requests");

    request       = '0;
    request[0][3] = 1'b1;
    request[1][3] = 1'b1;
    step(request, "first contending request");
    step(request, "contention advances priority");
  endtask

  task automatic run_directed();
    logic [NumPorts-1:0][NumPorts-1:0] request;

    request = '0;
    step(request, "directed idle");

    request       = '0;
    request[1][2] = 1'b1;
    step(request, "directed single request");

    request       = '0;
    request[0][0] = 1'b1;
    request[1][1] = 1'b1;
    request[2][2] = 1'b1;
    request[3][3] = 1'b1;
    step(request, "directed independent diagonal");

    request = '0;
    for (int unsigned input_idx = 0; input_idx < NumPorts; input_idx++) begin
      request[input_idx][0] = 1'b1;
    end
    for (int unsigned cycle = 0; cycle < NumPorts + 1; cycle++) begin
      step(request, "directed output contention and wraparound");
    end

    request = '0;
    for (int unsigned output_idx = 0; output_idx < NumPorts; output_idx++) begin
      request[2][output_idx] = 1'b1;
    end
    for (int unsigned cycle = 0; cycle < NumPorts + 1; cycle++) begin
      step(request, "directed input contention and wraparound");
    end

    request = '1;
    for (int unsigned cycle = 0; cycle < 2 * NumPorts; cycle++) begin
      step(request, "directed all-to-all contention");
    end

    apply_reset();
    request = '1;
    step(request, "directed priority after reset");
  endtask

  function automatic logic [31:0] next_random(input logic [31:0] state);
    logic [31:0] value;
    value = state;
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    return value;
  endfunction

  task automatic run_random();
    logic [31:0] random_state;
    logic [NumPorts-1:0][NumPorts-1:0] request;

    random_state = (seed == 0) ? 32'h6d2b_79f5 : seed;
    for (int unsigned cycle = 0; cycle < random_cycles; cycle++) begin
      request = '0;
      for (int unsigned input_idx = 0; input_idx < NumPorts; input_idx++) begin
        for (int unsigned output_idx = 0; output_idx < NumPorts; output_idx++) begin
          random_state = next_random(random_state);
          request[input_idx][output_idx] = random_state[0];
        end
      end
      step(request, "random request matrix");
    end
  endtask

  initial begin : run_test
    bit test_found;
    bit seed_found;
    bit cycles_found;

    req_i  = '0;
    rst_ni = 1'b0;
    checks = 0;

    test_found = $value$plusargs("TEST=%s", test_name);
    seed_found = $value$plusargs("SEED=%d", seed);
    cycles_found = $value$plusargs("CYCLES=%d", random_cycles);
    if (!test_found) test_name = "smoke";
    if (!seed_found) seed = 1;
    if (!cycles_found) random_cycles = 200;

    $display("Axon iSLIP unit test");
    $display("TEST=%s SEED=%0d CYCLES=%0d", test_name, seed, random_cycles);

    reset_reference_model();
    apply_reset();

    if (test_name == "smoke") begin
      run_smoke();
    end else if (test_name == "directed") begin
      run_directed();
    end else if (test_name == "random") begin
      run_random();
    end else begin
      $fatal(1, "Unknown TEST=%s", test_name);
    end

    $display("%s PASS: %0d checks", test_name, checks);
    $finish;
  end

  initial begin : timeout
    #1ms;
    $fatal(1, "Testbench timeout");
  end

endmodule
