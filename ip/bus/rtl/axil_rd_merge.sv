`include intf_pkg.sv

/*
 Simple read merge to ROM
 Expect data to come in 1 cycle always, so no extra buffering
 */
module axil_rd_merge
  import intf_pkg::*;
  #(
    parameter NUM_SRCS   = 2,
    parameter DATA_WIDTH = `AXI_DATA_WIDTH,    
    parameter ADDR_WIDTH = `AXI_ADDR_WIDTH,
    parameter STRB_WIDTH = (DATA_WIDTH/8))
   (/*AUTOARG*/
   // Outputs
   src_axi_arready_o, src_axi_rrsp_o, src_axi_rvalid_o, dst_axi_arvalid_o,
   dst_axi_arreq_o, dst_axi_rready_o,
   // Inputs
   clk_i, rst_ni, src_axi_arreq_i, src_axi_arvalid_i, src_axi_rready_i,
   dst_axi_arready_i, dst_axi_rvalid_i, dst_axi_rrsp_i
   );
   
   input wire 			             clk_i;
   input wire 			             rst_ni;

   input        [NUM_SRCS-1:0] axil_raddr_t  src_axi_arreq_i;
   input        [NUM_SRCS-1:0] 		     src_axi_arvalid_i;
   output logic [NUM_SRCS-1:0] 	             src_axi_arready_o;
   
   output       [NUM_SRCS-1:0] axil_rdata_t  src_axi_rrsp_o;
   output logic [NUM_SRCS-1:0] 	             src_axi_rvalid_o;
   input        [NUM_SRCS-1:0] 	             src_axi_rready_i;
   
   output logic 			     dst_axi_arvalid_o;
   output                      axil_raddr_t  dst_axi_arreq_o;
   input 				     dst_axi_arready_i;   
   
   input 				     dst_axi_rvalid_i;
   input                       axil_rdata_t  dst_axi_rrsp_i;
   output logic 			     dst_axi_rready_o;
   
   localparam SRC_W = $clog2(NUM_SRCS);   
   
   logic [SRC_W-1:0] 			      mrg_gnt_idx;
   logic [NUM_SRCS-1:0] 		      mrg_gnt,mrg_gnt_d1;   
   logic 				      dst_rready;
   
   always_comb begin
      mrg_gnt_idx     = '0;            
      for(int i=0; i<NUM_SRCS; i++)
	if(src_axi_arvalid_i[i]) 
	  mrg_gnt_idx = i[SRC_W-1:0];
   end
   
   assign mrg_gnt = 1 << mrg_gnt_idx;
   
   always_comb begin
      dst_axi_arvalid_o = '0;
      dst_axi_arreq_o   = '0;

      src_axi_arready_o = '0;      
      
      for(int i=0; i<NUM_SRCS; i++)
	if(mrg_gnt[i]) begin	 
	   dst_axi_arvalid_o    = src_axi_arvalid_i[i];
	   dst_axi_arreq_o      = src_axi_arreq_i[i];
	   src_axi_arready_o[i] = dst_axi_arready_i;	   
	end      
   end
   
   always @(posedge clk_i) begin
      if (!rst_ni) mrg_gnt_d1 <= '0;
      else         mrg_gnt_d1 <= mrg_gnt;
   end      
   
   always_comb begin
      dst_rready = '0;
      for(int i=0;i<NUM_SRCS;i++) begin
	 src_axi_rrsp_o[i]   = '0;
	 src_axi_rvalid_o[i] = '0;	 	 
	 if(mrg_gnt_d1[i]) begin
	    src_axi_rrsp_o[i]   = dst_axi_rrsp_i;
	    src_axi_rvalid_o[i] = dst_axi_rvalid_i;
	    dst_rready          = dst_rready | src_axi_rready_i[i];	 
	 end
      end
   end

   assign dst_axi_rready_o = dst_rready;
      
endmodule
