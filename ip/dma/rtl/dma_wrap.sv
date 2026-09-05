/*

*/

module dma_wrap
  import intf_pkg::*;
  import dma_pkg::*;
#(
  parameter int DmaIdVal = 0
)(/*AUTOARG*/
   // Outputs
   dma_error_o, dma_stats_o, axi_awreq_o, axi_awvalid_o, axi_wreq_o,
   axi_wvalid_o, axi_bready_o, axi_arreq_o, axi_arvalid_o,
   axi_rready_o,
   // Inputs
   clk_i, rst, dma_ctrl_i, dma_desc_i, axi_awready_i, axi_wready_i,
   axi_brsp_i, axi_bvalid_i, axi_arready_i, axi_rrsp_i, axi_rvalid_i
   );

  input  logic                          clk_i;
  input  logic                          rst_ni;
  // From/To CSRs
  input  dma_control_t                  dma_ctrl_i;
  input  dma_desc_t [`DMA_NUM_DESC-1:0] dma_desc_i;
  output dma_error_t                    dma_error_o;
  output dma_status_t                   dma_stats_o;
  // Master AXI I/F
  output axi_waddr_t                    axi_awreq_o;
  output logic                          axi_awvalid_o;
  input  logic                          axi_awready_i;
  output axi_wdata_t                    axi_wreq_o;
  output logic                          axi_wvalid_o;
  input  logic                          axi_wready_i;
  input  axi_bresp_t                    axi_brsp_i;
  input  logic                          axi_bvalid_i;
  output logic                          axi_bready_o;
  output axi_raddr_t                    axi_arreq_o;
  output logic                          axi_arvalid_o;
  input  logic                          axi_arready_i;
  input  axi_rdata_t                    axi_rrsp_i;
  input  logic                          axi_rvalid_i;
  output logic                          axi_rready_o;
);

  dma_str_in_t    dma_rd_stream_in;
  dma_str_out_t   dma_rd_stream_out;
  dma_str_in_t    dma_wr_stream_in;
  dma_str_out_t   dma_wr_stream_out;
  dma_axi_req_t   dma_axi_rd_req;
  dma_axi_resp_t  dma_axi_rd_resp;
  dma_axi_req_t   dma_axi_wr_req;
  dma_axi_resp_t  dma_axi_wr_resp;
  dma_fifo_req_t  dma_fifo_req;
  dma_fifo_resp_t dma_fifo_resp;
  dma_error_t     axi_dma_err;
  logic           axi_pend_txn;
  logic           clear_dma;
  logic           dma_active;

  /*
   dma_fsm AUTO_TEMPLATE (
   .axi_pend_txn_i   (axi_pend_txn),
   .axi_txn_err_i    (axi_dma_err),
   .dma_error_o      (dma_error_o),
   .clear_dma_o      (clear_dma),
   .dma_active_o     (dma_active),
   .dma_stream_rd_o  (dma_rd_stream_in),
   .dma_stream_rd_i  (dma_rd_stream_out),
   .dma_stream_wr_o  (dma_wr_stream_in),
   .dma_stream_wr_i  (dma_wr_stream_out),
   );
   */

  dma_fsm
    u_dma_fsm(/*AUTOINST*/
        // Outputs
        .dma_stats_o,
        .dma_error_o,           // Templated
        .clear_dma_o    (clear_dma),     // Templated
        .dma_active_o    (dma_active),     // Templated
        .dma_stream_rd_o    (dma_rd_stream_in),   // Templated
        .dma_stream_wr_o    (dma_wr_stream_in),   // Templated
        // Inputs
        .clk_i,             // Templated
        .rst_ni,             // Templated
        .dma_ctrl_i,
        .dma_desc_i    (dma_desc_i[`DMA_NUM_DESC-1:0]),
        .axi_pend_txn_i    (axi_pend_txn),     // Templated
        .axi_txn_err_i    (axi_dma_err),     // Templated
        .dma_stream_rd_i    (dma_rd_stream_out),   // Templated
        .dma_stream_wr_i    (dma_wr_stream_out));   // Templated


  /*
   dma_streamer AUTO_TEMPLATE "_dma_\\([a-z]+\\)_streamer" (
   .dma_abort_i      (dma_ctrl_i.abort),
   .dma_maxb_i       (dma_ctrl_i.max_burst),
   .dma_axi_req_o    (dma_axi_rd_req),
   .dma_axi_resp_i   (dma_axi_rd_resp),
   .dma_stream_i     (dma_rd_stream_in),
   .dma_stream_o     (dma_rd_stream_out),
   );
  */

  dma_streamer #(
    .STREAM_TYPE(0)
  )
  u_dma_rd_streamer (/*AUTOINST*/
         // Outputs
         .dma_axi_req_o  (dma_axi_rd_req),   // Templated
         .dma_stream_o  (dma_rd_stream_out),   // Templated
         // Inputs
         .clk_i,           // Templated
         .rst_ni,           // Templated
         .dma_desc_i  (dma_desc_i[`DMA_NUM_DESC-1:0]),
         .dma_abort_i  (dma_ctrl_i.abort),   // Templated
         .dma_maxb_i  (dma_ctrl_i.max_burst),   // Templated
         .dma_axi_resp_i  (dma_axi_rd_resp),   // Templated
         .dma_stream_i  (dma_rd_stream_in));   // Templated

  dma_streamer #(
    .STREAM_TYPE(1)
  )
  u_dma_wr_streamer (/*AUTOINST*/
         // Outputs
         .dma_axi_req_o  (dma_axi_rd_req),   // Templated
         .dma_stream_o  (dma_rd_stream_out),   // Templated
         // Inputs
         .clk_i,           // Templated
         .rst_ni,           // Templated
         .dma_desc_i  (dma_desc_i[`DMA_NUM_DESC-1:0]),
         .dma_abort_i  (dma_ctrl_i.abort),   // Templated
         .dma_maxb_i  (dma_ctrl_i.max_burst),   // Templated
         .dma_axi_resp_i  (dma_axi_rd_resp),   // Templated
         .dma_stream_i  (dma_rd_stream_in));   // Templated

  /*
   dma_axi_if AUTO_TEMPLATE (
   .dma_abort_i         (dma_ctrl_i.abort),
   .\(dma_.*\)_\(i\|o\) (\1),
   .axi_pend_txn_o      (axi_pend_txn),
   .axi_dma_err_o       (axi_dma_err),
   .clear_dma_i         (clear_dma),
   );
  */

  dma_axi_if #(
    .DmaIdVal         (DmaIdVal)
  )
  u_dma_axi_if (/*AUTOINST*/
    // Outputs
    .dma_axi_rd_resp_o  (dma_axi_rd_resp),   // Templated
    .dma_axi_wr_resp_o  (dma_axi_wr_resp),   // Templated
    .axi_awreq_o,
    .axi_awvalid_o,
    .axi_wreq_o,
    .axi_wvalid_o,
    .axi_bready_o,
    .axi_arreq_o,
    .axi_arvalid_o,
    .axi_rready_o,
    .dma_fifo_req_o    (dma_fifo_req),     // Templated
    .axi_pend_txn_o    (axi_pend_txn),     // Templated
    .axi_dma_err_o    (axi_dma_err),     // Templated
    // Inputs
    .clk_i,             // Templated
    .rst_ni,           // Templated
    .dma_axi_rd_req_i  (dma_axi_rd_req),   // Templated
    .dma_axi_wr_req_i  (dma_axi_wr_req),   // Templated
    .axi_awready_i,
    .axi_wready_i,
    .axi_brsp_i,
    .axi_bvalid_i,
    .axi_arready_i,
    .axi_rrsp_i,
    .axi_rvalid_i,
    .dma_fifo_resp_i  (dma_fifo_resp),   // Templated
    .clear_dma_i    (clear_dma),     // Templated
    .dma_abort_i    (dma_ctrl_i.abort),   // Templated
    .dma_active_i    (dma_active));     // Templated

  prim_fifo_sync #(
    .Depth  (`DMA_FIFO_DEPTH),
    .Width  (`DMA_DATA_WIDTH)
  ) u_dma_fifo(
                .clk_i    (clk_i),
                .rst_ni   (rst_ni),
                .wvalid_i (dma_fifo_req.wr_vld),
                .wdata_i  (dma_fifo_req.wdata),
                .wready_o (dma_fifo_resp.wr_rdy),
                .rvalid_o (dma_fifo_resp.rd_vld)
                .rready_i (dma_fifo_req.rd_rdy),
                .rdata_o  (dma_fifo_resp.rdata),
                .full_o   (),
                .depth_o  (),
                .clr_i    (clear_dma),
  );


endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// verilog-typedef-regexp: "_t$"
// End:
