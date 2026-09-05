`include "intf_pkg.sv"

module axil_wr_ext
  import intf_pkg::*;
  #(
    parameter MemBase   = 32'h10000000,
    parameter DataWidth = `AXI_DATA_WIDTH,
    parameter StrbWidth = (DataWidth/8))
   (/*AUTOARG*/
   // Outputs
   axi_awready_o, axi_wready_o, axi_brsp_o, axi_bvalid_o, ext_wr_dat_o,
   ext_wen_o, ext_wr_req_o,
   // Inputs
   clk_i, rst_ni, axi_awreq_i, axi_awvalid_i, axi_wreq_i, axi_wvalid_i,
   axi_bready_i, ext_rsp_val_i
   );

   input  logic                 clk_i;
   input  logic                 rst_ni;

   input  axil_waddr_t          axi_awreq_i;
   input  logic                 axi_awvalid_i;
   output logic                 axi_awready_o;

   input  axil_wdata_t          axi_wreq_i;
   input  logic                 axi_wvalid_i;
   output logic                 axi_wready_o;

   output axil_bresp_t          axi_brsp_o;
   output logic                 axi_bvalid_o;
   input  logic                 axi_bready_i;

   input  logic                 ext_rsp_val_i;
   output logic [DataWidth-1:0] ext_wr_dat_o;
   output logic [StrbWidth-1:0] ext_wen_o;
   output logic                 ext_wr_req_o;

   logic      wr_addr_err;
   axi_resp_t mem_wr_error,mem_wr_error_d1;
   logic      fif_full,fif_psh;
   logic      wr_resp_full,wr_resp_pend;

   assign wr_addr_err  = !(axi_awreq_i.awaddr == MemBase);

   assign fif_psh      = axi_awvalid_i && axi_wvalid_i & !wr_addr_err & !fif_full & !wr_resp_full;
   assign mem_wr_error = axi_resp_t'{(axi_awvalid_i & axi_wvalid_i & wr_addr_err),1'b0};
   assign axi_awready_o  = axi_awvalid_i && axi_wvalid_i & !fif_full & !wr_resp_full;
   assign axi_wready_o   = axi_awvalid_i && axi_wvalid_i & !fif_full & !wr_resp_full;
   assign axi_brsp_o.bresp = mem_wr_error_d1;
   assign axi_bvalid_o   = wr_resp_pend;

   assign wr_resp_full = wr_resp_pend & !axi_bready_i;

   always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
   wr_resp_pend    <= '0;
   mem_wr_error_d1 <= '0;
      end
      else begin
   wr_resp_pend    <= axi_awvalid_i && axi_wvalid_i & !wr_resp_full & !fif_full ? '1 :           axi_bready_i ? '0 : wr_resp_pend;
         mem_wr_error_d1 <= axi_awvalid_i && axi_wvalid_i & !wr_resp_full & !fif_full ? mem_wr_error : axi_bready_i ? '0 : mem_wr_error_d1;
      end
   end

   /*
    fifo AUTO_TEMPLATE (
    .wdata_i      ({axi_wreq_i.wdata,axi_wreq_i.wstrb}),
    .wvalid_i      (fif_psh),
    .rready_i      (ext_rsp_val_i),
    .rdata_o     ({ext_wr_dat_o,ext_wen_o}),
    .rvalid_o (ext_wr_req_o),
    .full_o     (fif_full),
    );
    */

   prim_fifo_sync #(.Width(DataWidth+StrbWidth),.Depth(1))
   u_fif (/*AUTOINST*/
    // Outputs
    .rdata_o        ({ext_wr_dat_o,ext_wen_o}), // Templated
    .rvalid_o      (ext_wr_req_o),     // Templated
    .wready_o     (),
    .full_o        (fif_full),     // Templated
    .depth_o       (),
    // Inputs
    .clk_i        (clk_i),
    .rst_ni      (rst_ni),
    .clr_i       (1'b0),
    .wvalid_i        (fif_psh),     // Templated
    .wdata_i        ({axi_wreq_i.wdata,axi_wreq_i.wstrb}), // Templated
    .rready_i        (ext_rsp_val_i));     // Templated



endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
