`include intf_pkg.sv

module axil_ext
  import intf_pkg::*;
  #(
    parameter MEM_BASE   = 32'h10000000,
    parameter DATA_WIDTH = `AXI_DATA_WIDTH,
    parameter ADDR_WIDTH = `AXI_ADDR_WIDTH,
    parameter STRB_WIDTH = (DATA_WIDTH/8))
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
   
   input 			 clk_i;
   input 			 rst_ni;

   input axil_waddr_t            axi_awreq_i;
   input 			 axi_awvalid_i;
   output logic 		 axi_awready_o;

   input axil_wdata_t            axi_wreq_i;
   input 			 axi_wvalid_i;
   output logic 		 axi_wready_o;

   output axil_bresp_t 		 axi_brsp_o;
   output logic 		 axi_bvalid_o;
   input 			 axi_bready_i;

   input axil_raddr_t            axi_arreq_i;
   input 			 axi_arvalid_i;
   output logic 		 axi_arready_o;

   output axil_rdata_t           axi_rrsp_o;
   output logic			 axi_rvalid_o;
   input 			 axi_rready_i;

   output 			 ext_rd_req_o;   
   output 			 ext_wr_req_o;
   output logic [DATA_WIDTH-1:0] ext_wr_dat_o;
   output logic [STRB_WIDTH-1:0] ext_wen_o;   

   input [DATA_WIDTH-1:0] 	 ext_rrsp_dat_i;
   input 			 ext_rrsp_val_i;   
   input 			 ext_wrsp_val_i;   
   
     
   /*
    axil_wr_ext AUTO_TEMPLATE (
    .ext_rsp_val_i (ext_wrsp_val_i),
    );
    */

   axil_wr_ext #(.MEM_BASE(MEM_BASE),.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(ADDR_WIDTH))
   u_wr_ext (/*AUTOINST*/
	     // Outputs
	     .axi_awready_o,
	     .axi_wready_o,
	     .axi_brsp_o		(axi_brsp_o),
	     .axi_bvalid_o,
	     .ext_wr_dat_o		(ext_wr_dat_o[DATA_WIDTH-1:0]),
	     .ext_wen_o			(ext_wen_o[STRB_WIDTH-1:0]),
	     .ext_wr_req_o,
	     // Inputs
	     .clk_i,
	     .rst_ni,
	     .axi_awreq_i		(axi_awreq_i),
	     .axi_awvalid_i,
	     .axi_wreq_i		(axi_wreq_i),
	     .axi_wvalid_i,
	     .axi_bready_i,
	     .ext_rsp_val_i		(ext_wrsp_val_i));		 // Templated


   /*
    axil_rd_ext AUTO_TEMPLATE (
    .ext_rsp_val_i (ext_rrsp_val_i),
    .ext_rsp_dat_i (ext_rrsp_dat_i),
    );
    */

   axil_rd_ext #(.MEM_BASE(MEM_BASE),.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(ADDR_WIDTH))
   u_rd_ext (/*AUTOINST*/
	     // Outputs
	     .axi_arready_o,
	     .axi_rrsp_o		(axi_rrsp_o),
	     .axi_rvalid_o,
	     .ext_rd_req_o,
	     // Inputs
	     .clk_i,
	     .rst_ni,
	     .axi_arreq_i		(axi_arreq_i),
	     .axi_arvalid_i,
	     .axi_rready_i,
	     .ext_rsp_dat_i		(ext_rrsp_dat_i),	 // Templated
	     .ext_rsp_val_i		(ext_rrsp_val_i));	 // Templated
   
   
   
endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
