// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Generic synchronous fifo for use in a variety of devices.

`include "prim_assert.sv"

module prim_fifo_sync #(
  parameter int unsigned Width       = 16,
  parameter bit Pass                 = 1'b1, // if == 1 allow requests to pass through empty FIFO
  parameter int unsigned Depth       = 4,
  parameter bit OutputZeroIfEmpty    = 1'b1, // if == 1 always output 0 when FIFO is empty
  parameter bit NeverClears          = 1'b0, // if set, the clr_i port is never high
  // derived parameter
  localparam int          DepthW     = prim_util_pkg::vbits(Depth+1)
) (
  input  logic              clk_i,
  input  logic              rst_ni,
  // synchronous clear / flush port
  input  logic              clr_i,
  // write port
  input  logic              wvalid_i,
  output logic              wready_o,
  input  logic [Width-1:0]  wdata_i,
  // read port
  output logic              rvalid_o,
  input  logic              rready_i,
  output logic [Width-1:0]  rdata_o,
  // occupancy
  output logic              full_o,
  output logic [DepthW-1:0] depth_o
);


  // FIFO is in complete passthrough mode
  if (Depth == 0) begin : gen_passthru_fifo
    `ASSERT_INIT(paramCheckPass, Pass == 1)

    assign depth_o = 1'b0; //output is meaningless

    // device facing
    assign rvalid_o = wvalid_i;
    assign rdata_o = wdata_i;

    // host facing
    assign wready_o = rready_i;
    assign full_o = 1'b1;

    // this avoids lint warnings
    logic             unused_clr;
    assign unused_clr = clr_i;

  // FIFO has space for a single element (and doesn't need proper counters)
  end else if (Depth == 1) begin : gen_singleton_fifo

    // full_q is true if the (singleton) queue has data
    logic             full_d, full_q;

    assign full_o = full_q;
    assign depth_o = full_q;
    assign wready_o = ~full_q;

    // We can always read from the storage if it contains something, so rvalid_o is true if full_q
    // is true. Enabling pass-through mode also allows data to flow through if wvalid_i is true.
    assign rvalid_o = full_q || (Pass && wvalid_i);

    // For there to be data on the next cycle, there must either be new data coming in (so !rvalid_o
    // && wvalid_i) or we must be keeping the current data (so rvalid_o && !rready_i). Using
    // rvalid_o instead of full_q ensures we get the right behaviour with pass-through.
    //
    // In either case, any stored data will be forgotten if clr_i is true.
    assign full_d = (rvalid_o ? !rready_i : wvalid_i) && !clr_i;

    always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
        full_q <= 1'b0;
      end else begin
        full_q <= full_d;
      end
    end

    logic [Width-1:0] storage;
    always_ff @(posedge clk_i) begin
      if (wvalid_i && wready_o) storage <= wdata_i;
    end

    logic [Width-1:0] rdata_int;
    assign rdata_int = (full_q || Pass == 1'b0) ? storage : wdata_i;

    assign rdata_o = (OutputZeroIfEmpty && !rvalid_o) ? Width'(0) : rdata_int;

  // Normal FIFO construction
  end else begin : gen_normal_fifo

    localparam int unsigned PtrW = prim_util_pkg::vbits(Depth);

    logic [PtrW-1:0]  fifo_wptr, fifo_rptr;
    logic             fifo_incr_wptr, fifo_incr_rptr, fifo_empty;

    // module under reset flag
    logic             under_rst;
    always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
        under_rst <= 1'b1;
      end else if (under_rst) begin
        under_rst <= ~under_rst;
      end
    end

    logic             empty;

    // full and not ready for write are two different concepts.
    // The latter can be '0' when under reset, while the former is an indication that no more
    // entries can be written.
    assign wready_o = ~full_o & ~under_rst;

    prim_fifo_sync_cnt #(
      .Depth(Depth),
      .NeverClears(NeverClears)
    ) u_fifo_cnt (
      .clk_i,
      .rst_ni,
      .clr_i,
      .incr_wptr_i(fifo_incr_wptr),
      .incr_rptr_i(fifo_incr_rptr),
      .wptr_o(fifo_wptr),
      .rptr_o(fifo_rptr),
      .full_o,
      .empty_o(fifo_empty),
      .depth_o
    );
    assign fifo_incr_wptr = wvalid_i & wready_o;
    assign fifo_incr_rptr = rvalid_o & rready_i & ~under_rst;

    logic             [Depth-1:0][Width-1:0] storage;
    logic [Width-1:0] storage_rdata;

    assign storage_rdata = storage[fifo_rptr];

    always_ff @(posedge clk_i)
      if (fifo_incr_wptr) begin
        storage[fifo_wptr] <= wdata_i;
      end

    logic [Width-1:0] rdata_int;
    if (Pass == 1'b1) begin : gen_pass
      assign rdata_int = (fifo_empty && wvalid_i) ? wdata_i : storage_rdata;
      assign empty = fifo_empty & ~wvalid_i;
      assign rvalid_o = ~empty & ~under_rst;
    end else begin : gen_nopass
      assign rdata_int = storage_rdata;
      assign empty = fifo_empty;
      assign rvalid_o = ~empty;
    end

    if (OutputZeroIfEmpty == 1'b1) begin : gen_output_zero
      assign rdata_o = empty ? Width'(0) : rdata_int;
    end else begin : gen_no_output_zero
      assign rdata_o = rdata_int;
    end

    `ASSERT(DepthWithinLimit_A, !empty |-> depth_o <= DepthW'(Depth))
    `ASSERT(ValidAfterReset_A, rvalid_o |-> !under_rst)
  end // block: gen_normal_fifo


  if (NeverClears) begin : gen_never_clears
    `ASSERT(NeverClears_A, !clr_i)
  end

  //////////////////////
  // Known Assertions //
  //////////////////////

  `ASSERT_KNOWN_IF(DataKnown_A, rdata_o, rvalid_o)
  `ASSERT_KNOWN(DepthKnown_A, depth_o)
  `ASSERT_KNOWN(RvalidKnown_A, rvalid_o)
  `ASSERT_KNOWN(WreadyKnown_A, wready_o)

endmodule : prim_fifo_sync
