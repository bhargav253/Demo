`include "intf_pkg.sv"

module axil_ext
  import intf_pkg::*;
  #(
    parameter MemBase   = 32'h10000000,
    parameter DataWidth = `AXI_DATA_WIDTH,
    parameter StrbWidth = (DataWidth/8))
   (/*AUTOARG*/
   // Outputs
   axi_awready_o, axi_wready_o, axi_brsp_o, axi_bvalid_o, axi_arready_o,
   axi_rrsp_o, axi_rvalid_o, ext_rd_req_o, ext_wr_req_o, ext_wr_dat_o,
   ext_wen_o,
   // Inputs
   clk_i, rst_ni, axi_awreq_i, axi_awvalid_i, axi_wreq_i, axi_wvalid_i,
   axi_bready_i, axi_arreq_i, axi_arvalid_i, axi_rready_i, ext_rrsp_dat_i,
   ext_rrsp_val_i, ext_wrsp_val_i
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

   input  axil_raddr_t          axi_arreq_i;
   input  logic                 axi_arvalid_i;
   output logic                 axi_arready_o;

   output axil_rdata_t          axi_rrsp_o;
   output logic                 axi_rvalid_o;
   input  logic                 axi_rready_i;

   output logic                 ext_rd_req_o;
   output logic                 ext_wr_req_o;
   output logic [DataWidth-1:0] ext_wr_dat_o;
   output logic [StrbWidth-1:0] ext_wen_o;

   input  logic [DataWidth-1:0] ext_rrsp_dat_i;
   input  logic                 ext_rrsp_val_i;
   input  logic                 ext_wrsp_val_i;


   /*
    axil_wr_ext AUTO_TEMPLATE (
    .ext_rsp_val_i (ext_wrsp_val_i),
    );
    */

   axil_wr_ext #(.MemBase(MemBase),.DataWidth(DataWidth))
   u_wr_ext (/*AUTOINST*/
       // Outputs
       .axi_awready_o,
       .axi_wready_o,
       .axi_brsp_o    (axi_brsp_o),
       .axi_bvalid_o,
       .ext_wr_dat_o    (ext_wr_dat_o[DataWidth-1:0]),
       .ext_wen_o      (ext_wen_o[StrbWidth-1:0]),
       .ext_wr_req_o,
       // Inputs
       .clk_i,
       .rst_ni,
       .axi_awreq_i    (axi_awreq_i),
       .axi_awvalid_i,
       .axi_wreq_i    (axi_wreq_i),
       .axi_wvalid_i,
       .axi_bready_i,
       .ext_rsp_val_i    (ext_wrsp_val_i));     // Templated


   /*
    axil_rd_ext AUTO_TEMPLATE (
    .ext_rsp_val_i (ext_rrsp_val_i),
    .ext_rsp_dat_i (ext_rrsp_dat_i),
    );
    */

   axil_rd_ext #(.MemBase(MemBase),.DataWidth(DataWidth))
   u_rd_ext (/*AUTOINST*/
       // Outputs
       .axi_arready_o,
       .axi_rrsp_o    (axi_rrsp_o),
       .axi_rvalid_o,
       .ext_rd_req_o,
       // Inputs
       .clk_i,
       .rst_ni,
       .axi_arreq_i    (axi_arreq_i),
       .axi_arvalid_i,
       .axi_rready_i,
       .ext_rsp_dat_i    (ext_rrsp_dat_i),   // Templated
       .ext_rsp_val_i    (ext_rrsp_val_i));   // Templated



endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
