/*

*/

module dma_axi_if
  import intf_pkg::*;
  import dma_pkg::*;
#(
  parameter int DmaIdVal = 0
)(/*AUTOARG*/
   // Outputs
   dma_axi_rd_resp_o, dma_axi_wr_resp_o, axi_awreq_o, axi_awvalid_o,
   axi_wreq_o, axi_wvalid_o, axi_bready_o, axi_arreq_o, axi_arvalid_o,
   axi_rready_o, dma_fifo_req_o, axi_pend_txn_o, axi_dma_err_o,
   // Inputs
   clk_i, rst_ni, dma_axi_rd_req_i, dma_axi_wr_req_i, axi_awready_i,
   axi_wready_i, axi_brsp_i, axi_bvalid_i, axi_arready_i, axi_rrsp_i,
   axi_rvalid_i, dma_fifo_resp_i, clear_dma_i, dma_abort_i,
   dma_active_i
   );

  input  logic           clk_i;
  input  logic           rst_ni;
  // From/To Streamers
  input  dma_axi_req_t   dma_axi_rd_req_i;
  output dma_axi_resp_t  dma_axi_rd_resp_o;
  input  dma_axi_req_t   dma_axi_wr_req_i;
  output dma_axi_resp_t  dma_axi_wr_resp_o;
  // Master AXI I/F
  output axi_waddr_t     axi_awreq_o;
  output logic           axi_awvalid_o;
  input  logic           axi_awready_i;
  output axi_wdata_t     axi_wreq_o;
  output logic           axi_wvalid_o;
  input  logic           axi_wready_i;
  input  axi_bresp_t     axi_brsp_i;
  input  logic           axi_bvalid_i;
  output logic           axi_bready_o;
  output axi_raddr_t     axi_arreq_o;
  output logic           axi_arvalid_o;
  input  logic           axi_arready_i;
  input  axi_rdata_t     axi_rrsp_i;
  input  logic           axi_rvalid_i;
  output logic           axi_rready_o;

  // From/To FIFOs interface
  output dma_fifo_req_t  dma_fifo_req_o;
  input  dma_fifo_resp_t dma_fifo_resp_i;
  // From/To DMA FSM
  output logic           axi_pend_txn_o;
  output dma_error_t     axi_dma_err_o;
  input  logic           clear_dma_i;
  input  logic           dma_abort_i;
  input  logic           dma_active_i;

  pend_rd_t     rd_counter_ff, next_rd_counter;
  pend_wr_t     wr_counter_ff, next_wr_counter;
  axi_wr_strb_t rd_txn_last_strb;
  logic         rd_txn_hpn;
  logic         wr_txn_hpn;
  logic         rd_resp_hpn;
  logic         wr_resp_hpn;
  logic         rd_err_hpn;
  logic         wr_err_hpn;
  axi_addr_t    rd_txn_addr;
  axi_addr_t    wr_txn_addr;
  logic         err_lock_ff, next_err_lock;
  logic         wr_data_txn_hpn;
  logic         wr_lock_ff, next_wr_lock;
  logic         wr_new_txn;
  logic         wr_beat_hpn;
  logic         wr_data_req_vld;
  logic         aw_txn_started_ff, next_aw_txn;

  wr_req_t      wr_data_req_in, wr_data_req_out;
  axi_alen_t    beat_counter_ff, next_beat_count;

  dma_error_t   dma_error_ff, next_dma_error;

  function automatic axi_data_t apply_strb(axi_data_t data, axi_wr_strb_t mask);
    axi_data_t out_data;
    for (int i=0; i<$bits(axi_wr_strb_t); i++) begin
      if (mask[i] == 1'b1) begin
        out_data[(8*i)+:8] = data[(8*i)+:8];
      end
      else begin
        out_data[(8*i)+:8] = 8'd0;
      end
    end
    return out_data;
  endfunction

  //***************************************************
  // Queue the txn from the wr streamer to send in the
  // data channel
  //***************************************************
  prim_fifo_sync #(
    .Depth  (`DMA_WR_TXN_BUFF),
    .Width  ($bits(wr_req_t))
  ) u_fifo_wr_data (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .wvalid_i (wr_new_txn),
    .wdata_i  (wr_data_req_in),
    .wready_o (),
    .rvalid_o (wr_data_req_vld)
    .rready_i (wr_data_txn_hpn),
    .rdata_o  (wr_data_req_out),
    .full_o   (),
    .depth_o  (),
    .clr_i    (1'b0)
  );

  //***************************************************
  // Stores the strb mask used in case of unaligned
  // start/end addresses for reads
  //***************************************************
  prim_fifo_sync #(
    .Depth  (`DMA_RD_TXN_BUFF),
    .Width  ($bits(axi_wr_strb_t))
  ) u_fifo_rd_strb (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .wvalid_i (rd_txn_hpn),
    .wdata_i  (dma_axi_rd_req_i.strb),
    .wready_o (),
    .rvalid_o (),
    .rready_i (rd_resp_hpn),
    .rdata_o  (rd_txn_last_strb),
    .full_o   (),
    .depth_o  (),
    .clr_i    (1'b0)
  );

  //***************************************************
  // Stores the address of the txn that were dispatched
  // for further logging in case of error
  //***************************************************
  prim_fifo_sync #(
    .SLOTS  (`DMA_RD_TXN_BUFF),
    .Width  (`DMA_ADDR_WIDTH)
  ) u_fifo_rd_error (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .wvalid_i (rd_txn_hpn),
    .wdata_i  (dma_axi_rd_req_i.addr),
    .wready_o (),
    .rvalid_o (),
    .rready_i (rd_resp_hpn),
    .rdata_o  (rd_txn_addr),
    .full_o   (),
    .depth_o  (),
    .clr_i    (1'b0)
  );

  prim_fifo_sync #(
    .SLOTS  (`DMA_WR_TXN_BUFF),
    .Width  (`DMA_ADDR_WIDTH)
  ) u_fifo_wr_error (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .wvalid_i (wr_txn_hpn),
    .wdata_i  (dma_axi_wr_req_i.addr),
    .wready_o (),
    .rvalid_o (),
    .rdata_o  (wr_txn_addr),
    .rready_i (wr_resp_hpn),
    .full_o   (),
    .depth_o  (),
    .clr_i    (1'b0)
  );

  always_comb begin
    axi_pend_txn_o  = (|rd_counter_ff) || (|wr_counter_ff);
    axi_dma_err_o   = dma_error_ff;
    next_dma_error  = dma_error_ff;
    next_err_lock   = err_lock_ff;
    next_rd_counter = rd_counter_ff;
    next_wr_counter = wr_counter_ff;

    if (~dma_active_i) begin
      next_err_lock   = 1'b0;
    end
    else begin
      next_err_lock = rd_err_hpn || wr_err_hpn;
    end

    if (~err_lock_ff) begin
      if (rd_err_hpn) begin
        next_dma_error.valid    = 1'b1;
        next_dma_error.err_type = DMA_ERR_OPE;
        next_dma_error.src      = DMA_ERR_RD;
        next_dma_error.addr     = rd_txn_addr;
      end
      else if (wr_err_hpn) begin
        next_dma_error.valid    = 1'b1;
        next_dma_error.err_type = DMA_ERR_OPE;
        next_dma_error.src      = DMA_ERR_WR;
        next_dma_error.addr     = wr_txn_addr;
      end
    end

    if (clear_dma_i) begin
      next_dma_error = dma_error_t'('0);
      next_wr_lock   = 1'b0;
    end

    rd_txn_hpn  = axi_arvalid_o && axi_arready_i;
    rd_resp_hpn = axi_rvalid_i     &&
                  axi_rrsp_i.rlast &&
                  axi_rready_o;
    wr_txn_hpn  = axi_awvalid_o && axi_awready_i;
    wr_resp_hpn = axi_bvalid_i && axi_bready_o;

    if (dma_active_i) begin
      if (rd_txn_hpn || rd_resp_hpn) begin
        next_rd_counter = rd_counter_ff + (rd_txn_hpn ? 'd1 : 'd0) - (rd_resp_hpn ? 'd1 : 'd0);
      end

      if (wr_txn_hpn || wr_resp_hpn) begin
        next_wr_counter = wr_counter_ff + (wr_txn_hpn ? 'd1 : 'd0) - (wr_resp_hpn ? 'd1 : 'd0);
      end
    end
    else begin
      next_rd_counter = 'd0;
      next_wr_counter = 'd0;
    end
    // Write Data Txn finished
    wr_data_txn_hpn = axi_wvalid_o &&
                      axi_wreq_o.wlast  &&
                      axi_wready_i;

    // Every time we have a new req. coming from the wr streamer,
    // we store in the queue to push through the wr data channel
    // in the next CC. However, we don't send multiple wr data txn
    // without handshake in the wr address channel first. Having
    // both AWVALID + WVALID asserted is intended to break deadlock
    // depency in the AXI4 (A3.3 Relationships between the channels
    // page 44 - AXI4 Spec)
    wr_new_txn  = 1'b0;
    next_wr_lock = wr_lock_ff;
    wr_data_req_in = wr_req_t'('0);
    if (dma_axi_wr_req_i.valid) begin
      next_wr_lock = ~dma_axi_wr_resp_o.ready;
      wr_new_txn   = ~wr_lock_ff;
      wr_data_req_in.alen  = dma_axi_wr_req_i.alen;
      wr_data_req_in.wstrb = dma_axi_wr_req_i.strb;
    end

    if (wr_txn_hpn) begin
      next_wr_lock = 1'b0;
    end

    wr_beat_hpn = axi_wvalid_o && axi_wready_i;
    next_beat_count = beat_counter_ff;

    // Increment each beat of the burst
    if (wr_beat_hpn) begin
      next_beat_count = beat_counter_ff + 'd1;
    end

    // If the last beat of the burst happens,
    // lets clear the beat counter
    if (wr_data_txn_hpn) begin
      next_beat_count = axi_alen_t'('0);
    end
  end

  always_comb begin : axi4_master
    dma_fifo_req_o = dma_fifo_req_t'('0);
    rd_err_hpn = 1'b0;
    wr_err_hpn = 1'b0;
    dma_axi_rd_resp_o = dma_axi_resp_t'('0);
    dma_axi_wr_resp_o = dma_axi_resp_t'('0);
    next_aw_txn = aw_txn_started_ff;

    if (dma_active_i) begin
      // Address Read Channel - AR*
      axi_arreq_o.arid   = axi_tid_t'(DmaIdVal);

      axi_arvalid_o = (rd_counter_ff < `DMA_RD_TXN_BUFF) ? dma_axi_rd_req_i.valid : 1'b0;
      if (axi_arvalid_o) begin
        dma_axi_rd_resp_o.ready = axi_arready_i;
        axi_arreq_o.araddr  = dma_axi_rd_req_i.addr;
        axi_arreq_o.arlen   = dma_axi_rd_req_i.alen;
        axi_arreq_o.arsize  = dma_axi_rd_req_i.size;
        axi_arreq_o.arburst = (dma_axi_rd_req_i.mode == DMA_MODE_INCR) ? AXI_INCR : AXI_FIXED;
      end
      // Read Data Channel - R*
      axi_rready_o = (dma_fifo_resp_i.wr_rdy || dma_abort_i); // Available to recv if we're not full or there's an abort in progress
      if (axi_rvalid_i && (dma_fifo_resp_i.wr_rdy || dma_abort_i)) begin
        dma_fifo_req_o.wr_vld = dma_abort_i ? 1'b0 : 1'b1; // Ignore incoming data in case of abort
        dma_fifo_req_o.wdata  = apply_strb(axi_rrsp_i.rdata, rd_txn_last_strb);
        if (axi_rrsp_i.rlast && axi_rready_o) begin
          rd_err_hpn = (axi_rrsp_i.rresp == AxiSlaveError) ||
                       (axi_rrsp_i.rresp == AxiDecodeError);
        end
      end
      // Address Write Channel - AW*
      axi_awreq_o.awid   = axi_tid_t'(DmaIdVal);
      // Send a write txn based on the following conditions:
      // 1- if (we have enough buffer space - `DMA_WR_TXN_BUFF)
      // 2- We have a request coming from the streamer - ...valid
      // 3- ...and we have something to send in the data phase ...~empty
      // 3 (OR)- we have an abort request, so we can ignore the DMA_FIFO
      // 4- Or we have started a txn and we need to respect valid/ready handshake.
      //    We could potentially put awvalid back to low if dma_fifo gets empty
      //    while we are waiting for awready from the slave
      axi_awvalid_o = (wr_counter_ff < `DMA_WR_TXN_BUFF) ? ((dma_axi_wr_req_i.valid &&
                           (dma_fifo_resp_i.rd_vld || dma_abort_i)) || aw_txn_started_ff) : 1'b0;
      if (axi_awvalid_o) begin
        dma_axi_wr_resp_o.ready = axi_awready_i;
        axi_awreq_o.awaddr  = dma_axi_wr_req_i.addr;
        axi_awreq_o.awlen   = dma_axi_wr_req_i.alen;
        axi_awreq_o.awsize  = dma_axi_wr_req_i.size;
        axi_awreq_o.awburst = (dma_axi_wr_req_i.mode == DMA_MODE_INCR) ? AXI_INCR : AXI_FIXED;
        next_aw_txn         = ~axi_awready_i; // Ensures we respect valid / ready AMBA protocol
      end
      // Write Data Channel - W*
      if (wr_data_req_vld && (dma_fifo_resp_i.rd_vld || dma_abort_i)) begin
        dma_fifo_req_o.rd_rdy = dma_abort_i ? 1'b0 : axi_wready_i; // Ignore fifo content in case of abort
        axi_wreq_o.wid    = axi_tid_t'(DmaIdVal);
        axi_wreq_o.wdata  = dma_fifo_resp_i.rdata;
        axi_wreq_o.wstrb  = wr_data_req_out.wstrb;
        axi_wreq_o.wlast  = (beat_counter_ff == wr_data_req_out.alen);
        axi_wreq_o.wvalid = 1'b1;
      end
      // Write Response Channel - B*
      axi_bready_o = 1'b1;
      if (axi_bvalid_i) begin
        wr_err_hpn  = (axi_brsp_i.bresp == AxiSlaveError) ||
                      (axi_brsp_i.bresp == AxiDecodeError);
      end
    end
  end : axi4_master

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      rd_counter_ff     <= pend_rd_t'('0);
      wr_counter_ff     <= pend_rd_t'('0);
      dma_error_ff      <= dma_error_t'('0);
      err_lock_ff       <= 1'b0;
      beat_counter_ff   <= '0;
      wr_lock_ff        <= 1'b0;
      aw_txn_started_ff <= 1'b0;
    end
    else begin
      rd_counter_ff     <= next_rd_counter;
      wr_counter_ff     <= next_wr_counter;
      dma_error_ff      <= next_dma_error;
      err_lock_ff       <= next_err_lock;
      beat_counter_ff   <= next_beat_count;
      wr_lock_ff        <= next_wr_lock;
      aw_txn_started_ff <= next_aw_txn;
    end
  end

`ifndef NO_ASSERTIONS
  `ifndef VERILATOR
    default clocking axi4_clk @(posedge clk_i); endclocking

    // https://github.com/YosysHQ-GmbH/SVA-AXI4-FVIP/blob/250f1ffd47fc1cdc4b4dd1670c6e1df58dec1b12/AXI4/src/axi4_spec/amba_axi4_single_interface_requirements.sv#L68
    property valid_before_handshake(valid, ready);
       valid && !ready |-> ##1 valid;
    endproperty // valid_before_handshake

    // https://github.com/YosysHQ-GmbH/SVA-AXI4-FVIP/blob/250f1ffd47fc1cdc4b4dd1670c6e1df58dec1b12/AXI4/src/axi4_spec/amba_axi4_single_interface_requirements.sv#L54
    property stable_before_handshake(valid, ready, control);
      valid && !ready |-> ##1 $stable(control);
    endproperty // stable_before_handshake

    axi4_arvalid_arready : assert property(disable iff (rst) valid_before_handshake  (axi_arvalid_o, axi_arready_i))
                           else $error("Violation AXI4: Once ARVALID is asserted it must remain asserted until the handshake");
    axi4_arvalid_araddr  : assert property(disable iff (rst) stable_before_handshake (axi_arvalid_o, axi_arready_i, axi_arreq_o.araddr))
                           else $error("Violation AXI4: Once the master has asserted ARVALID, data and control information from master must remain stable [ADDR] until ARREADY is asserted");
    axi4_arvalid_arlen   : assert property(disable iff (rst) stable_before_handshake (axi_arvalid_o, axi_arready_i, axi_arreq_o.arlen))
                           else $error("Violation AXI4: Once the master has asserted ARVALID, data and control information from master must remain stable [ALEN] until ARREADY is asserted");
    axi4_arvalid_arsize  : assert property(disable iff (rst) stable_before_handshake (axi_arvalid_o, axi_arready_i, axi_arreq_o.arsize))
                           else $error("Violation AXI4: Once the master has asserted ARVALID, data and control information from master must remain stable [ASIZE] until ARREADY is asserted");
    axi4_arvalid_arburst : assert property(disable iff (rst) stable_before_handshake (axi_arvalid_o, axi_arready_i, axi_arreq_o.arburst))
                           else $error("Violation AXI4: Once the master has asserted ARVALID, data and control information from master must remain stable [ABURST] until ARREADY is asserted");

    axi4_awvalid_awready : assert property(disable iff (rst) valid_before_handshake  (axi_awvalid_o, axi_awready_i))
                           else $error("Violation AXI4: Once AWVALID is asserted it must remain asserted until the handshake");
    axi4_awvalid_awaddr  : assert property(disable iff (rst) stable_before_handshake (axi_awvalid_o, axi_awready_i, axi_awreq_o.awaddr))
                           else $error("Violation AXI4: Once the master has asserted AWVALID, data and control information from master must remain stable [ADDR] until AWREADY is asserted");
    axi4_awvalid_awlen   : assert property(disable iff (rst) stable_before_handshake (axi_awvalid_o, axi_awready_i, axi_awreq_o.awlen))
                           else $error("Violation AXI4: Once the master has asserted AWVALID, data and control information from master must remain stable [ALEN] until AWREADY is asserted");
    axi4_awvalid_awsize  : assert property(disable iff (rst) stable_before_handshake (axi_awvalid_o, axi_awready_i, axi_awreq_o.awsize))
                           else $error("Violation AXI4: Once the master has asserted AWVALID, data and control information from master must remain stable [ASIZE] until AWREADY is asserted");
    axi4_awvalid_awburst : assert property(disable iff (rst) stable_before_handshake (axi_awvalid_o, axi_awready_i, axi_awreq_o.awburst))
                           else $error("Violation AXI4: Once the master has asserted AWVALID, data and control information from master must remain stable [ABURST] until AWREADY is asserted");

    axi4_wvalid_wready   : assert property(disable iff (rst) valid_before_handshake  (axi_wreq_o.wvalid, axi_wready_i))
                           else $error("Violation AXI4: Once WVALID is asserted it must remain asserted until the handshake");
    axi4_wvalid_wdata    : assert property(disable iff (rst) stable_before_handshake (axi_wreq_o.wvalid, axi_wready_i, axi_wreq_o.wdata))
                           else $error("Violation AXI4: Once the master has asserted WVALID, data and control information from master must remain stable [DATA] until WREADY is asserted");
    axi4_wvalid_wstrb    : assert property(disable iff (rst) stable_before_handshake (axi_wreq_o.wvalid, axi_wready_i, axi_wreq_o.wstrb))
                           else $error("Violation AXI4: Once the master has asserted WVALID, data and control information from master must remain stable [WSTRB] until WREADY is asserted");
    axi4_wvalid_wlast    : assert property(disable iff (rst) stable_before_handshake (axi_wreq_o.wvalid, axi_wready_i, axi_wreq_o.wlast))
                           else $error("Violation AXI4: Once the master has asserted WVALID, data and control information from master must remain stable [WLAST] until WREADY is asserted");

    axi4_bvalid_bready   : assert property(disable iff (rst) valid_before_handshake  (axi_bvalid_i, axi_bready_o))
                           else $error("Violation AXI4: Once BVALID is asserted it must remain asserted until the handshake");
    axi4_bvalid_bresp    : assert property(disable iff (rst) stable_before_handshake (axi_bvalid_i, axi_bready_o, axi_brsp_i.bresp))
                           else $error("Violation AXI4: Once the slave has asserted BVALID, data and control information from slave must remain stable [RESP] until BREADY is asserted");

    axi4_rvalid_rready   : assert property(disable iff (rst) valid_before_handshake  (axi_rvalid_i, axi_rready_o))
                           else $error("Violation AXI4: Once RVALID is asserted it must remain asserted until the handshake");
    axi4_rvalid_rdata    : assert property(disable iff (rst) stable_before_handshake (axi_rvalid_i, axi_rready_o, axi_rrsp_i.rdata))
                           else $error("Violation AXI4: Once the slave has asserted RVALID, data and control information from slave must remain stable [DATA] until RREADY is asserted");
    axi4_rvalid_rlast    : assert property(disable iff (rst) stable_before_handshake (axi_rvalid_i, axi_rready_o, axi_rrsp_i.rlast))
                           else $error("Violation AXI4: Once the slave has asserted RVALID, data and control information from slave must remain stable [RLAST] until RREADY is asserted");

  `endif
`endif
endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// verilog-typedef-regexp: "_t$"
// End:
