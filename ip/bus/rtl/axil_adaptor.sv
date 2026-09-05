/*mem adapter*/
`include "intf_pkg.sv"

module axil_adaptor
  import intf_pkg::*;
   (
   clk_i, rst_ni,
   axi_awreq_o, axi_awvalid_o, axi_awready_i,
   axi_wreq_o, axi_wvalid_o, axi_wready_i,
   axi_brsp_i, axi_bvalid_i, axi_bready_o,
   axi_arreq_o, axi_arvalid_o, axi_arready_i,
   axi_rrsp_i, axi_rvalid_i, axi_rready_o,
   intf_req_i, intf_req_accept_o, intf_rsp_val_o, intf_rsp_o
   );

   input  logic        clk_i;
   input  logic        rst_ni;

   // AXI4-lite master memory interface

   // AXI4-Lite Slave Interface
   // Write Address Channel
   output axil_waddr_t axi_awreq_o;
   output logic        axi_awvalid_o;
   input  logic        axi_awready_i;

   // Write Data Channel
   output axil_wdata_t axi_wreq_o;
   output logic        axi_wvalid_o;
   input  logic        axi_wready_i;

   // Write Response Channel
   input  axil_bresp_t axi_brsp_i;
   input  logic        axi_bvalid_i;
   output logic        axi_bready_o;

   // Read Address Channel
   output axil_raddr_t axi_arreq_o;
   output logic        axi_arvalid_o;
   input  logic        axi_arready_i;

   // Read Data Channel
   input  axil_rdata_t axi_rrsp_i;
   input  logic        axi_rvalid_i;
   output logic        axi_rready_o;


   input  intf_req_t   intf_req_i;
   output logic        intf_req_accept_o;


   output logic        intf_rsp_val_o;
   output intf_rsp_t   intf_rsp_o;


   localparam TxnRead = 1'b0;
   localparam TxnWrite = 1'b1;

   intf_req_t                  skid_in_data,skid_out_data;
   logic                       skid_in_valid,skid_in_ready,skid_out_valid,skid_out_ready;
   logic [`AXI_TXN_ID_WIDTH:0] rsp_skid_in_data,rsp_skid_out_data;
   logic                       rsp_skid_in_valid, rsp_skid_in_ready;
   logic                       rsp_skid_out_valid, rsp_skid_out_ready;
   logic                       unused_req_tag;

   assign unused_req_tag = ^skid_out_data.req_tag;

   assign axi_awvalid_o      = skid_out_valid & |skid_out_data.wen;
   assign axi_awreq_o.awaddr = skid_out_data.addr;

   assign axi_wvalid_o       = skid_out_valid & |skid_out_data.wen;
   assign axi_wreq_o.wdata   = skid_out_data.wdata;
   assign axi_wreq_o.wstrb   = skid_out_data.wen;

   assign axi_arvalid_o      = skid_out_valid & skid_out_data.ren;
   assign axi_arreq_o.araddr = skid_out_data.addr;

   assign intf_req_accept_o = skid_in_ready & rsp_skid_in_ready;

   always_comb begin
      skid_in_valid       = '0;
      skid_in_data        = '0;

      rsp_skid_in_valid   = '0;
      rsp_skid_in_data    = '0;

      if(intf_req_i.ren | (|intf_req_i.wen)) begin
         skid_in_valid     = 1'b1;
         skid_in_data      = '{ addr    : intf_req_i.addr,
                                wdata   : intf_req_i.wdata,
                                req_tag : intf_req_i.req_tag,
                                wen     : intf_req_i.wen,
                                ren     : intf_req_i.ren };

         rsp_skid_in_valid = 1'b1;
         rsp_skid_in_data  = {intf_req_i.req_tag,intf_req_i.ren ? TxnRead : TxnWrite};
      end
   end

   assign skid_out_ready = skid_out_valid & |skid_out_data.wen ? axi_awready_i & axi_wready_i :
                           skid_out_valid & skid_out_data.ren  ? axi_arready_i : 1'b0;

   /*
    prim_slice AUTO_TEMPLATE (
    .in_data_i   (skid_in_data),
    .in_valid_i  (skid_in_valid),
    .in_ready_o  (skid_in_ready),
    .out_data_o  (skid_out_data),
    .out_valid_o (skid_out_valid),
    .out_ready_i (skid_out_ready),
    );
    */

   prim_slice #(.Width($bits(intf_req_t)))
   u_req_slice (/*AUTOINST*/
                // Outputs
                .in_ready_o    (skid_in_ready),   // Templated
                .out_data_o    (skid_out_data),   // Templated
                .out_valid_o    (skid_out_valid),   // Templated
                // Inputs
                .clk_i,
                .rst_ni,
                .in_data_i    (skid_in_data),     // Templated
                .in_valid_i    (skid_in_valid),   // Templated
                .out_ready_i    (skid_out_ready));   // Templated


   always_comb begin
      intf_rsp_val_o      = '0;
      intf_rsp_o.error    = '0;
      intf_rsp_o.rdata    = axi_rrsp_i.rdata;
      intf_rsp_o.resp_tag = '0;

      rsp_skid_out_ready  = '0;

      if((rsp_skid_out_data[0] == TxnWrite) & rsp_skid_out_valid) begin
         intf_rsp_val_o      = axi_bvalid_i;
         intf_rsp_o.error    = axi_brsp_i.bresp[1];
         intf_rsp_o.resp_tag = rsp_skid_out_data[`AXI_TXN_ID_WIDTH:1];

         rsp_skid_out_ready  = axi_bvalid_i;
      end
      else if((rsp_skid_out_data[0] == TxnRead) & rsp_skid_out_valid) begin
         intf_rsp_val_o      = axi_rvalid_i;
         intf_rsp_o.error    = axi_rrsp_i.rresp[1];
         intf_rsp_o.resp_tag = rsp_skid_out_data[`AXI_TXN_ID_WIDTH:1];

         rsp_skid_out_ready  = axi_rvalid_i;
      end
   end

   assign axi_bready_o  = '1;
   assign axi_rready_o  = '1;

   /*
    prim_fifo_sync AUTO_TEMPLATE (
    .clr_i    ('0),
    .rvalid_o (rsp_skid_out_valid),
    .rready_i (rsp_skid_out_ready),
    .rdata_o  (rsp_skid_out_data),
    .wvalid_i (rsp_skid_in_valid),
    .wready_o (rsp_skid_in_ready),
    .wdata_i  (rsp_skid_in_data),
    .full_o   (),
    .depth_o  (),
    );
    */

   prim_fifo_sync #(.Width(`AXI_TXN_ID_WIDTH+1),.Depth(2))
   u_rsp_fif (/*AUTOINST*/
              // Outputs
              .wready_o      (rsp_skid_in_ready),   // Templated
              .rvalid_o      (rsp_skid_out_valid),   // Templated
              .rdata_o      (rsp_skid_out_data),   // Templated
              .full_o      (),       // Templated
              .depth_o      (),       // Templated
              // Inputs
              .clk_i,
              .rst_ni,
              .clr_i      ('0),       // Templated
              .wvalid_i      (rsp_skid_in_valid),   // Templated
              .wdata_i      (rsp_skid_in_data),   // Templated
              .rready_i      (rsp_skid_out_ready));   // Templated


endmodule

// Local variables:
// verilog-library-directories:("." "../../prim/rtl/")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
