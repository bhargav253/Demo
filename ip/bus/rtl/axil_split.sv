`include intf_pkg.sv

/*
 AXI split, to split Data access from core to RAM / and other IOs
 With a 2 deep FIFO, to allow 1 outstanding response
 */
module axil_split
  import intf_pkg::*;
  #(
    parameter NUM_WR_DSTS = 2,
    parameter NUM_RD_DSTS = 2,    
    parameter DATA_WIDTH  = `AXI_DATA_WIDTH,    
    parameter ADDR_WIDTH  = `AXI_ADDR_WIDTH,
    parameter STRB_WIDTH  = (DATA_WIDTH/8))
   (/*AUTOARG*/
   // Outputs
   src_axi_awready_o, src_axi_wready_o, src_axi_brsp_o, src_axi_bvalid_o,
   src_axi_arready_o, src_axi_rrsp_o, src_axi_rvalid_o, dst_axi_awreq_o,
   dst_axi_awvalid_o, dst_axi_wreq_o, dst_axi_wvalid_o, dst_axi_bready_o,
   dst_axi_arreq_o, dst_axi_arvalid_o, dst_axi_rready_o,
   // Inputs
   clk_i, rst_ni, wr_decode_i, rd_decode_i, src_axi_awreq_i,
   src_axi_awvalid_i, src_axi_wreq_i, src_axi_wvalid_i, src_axi_bready_i,
   src_axi_arreq_i, src_axi_arvalid_i, src_axi_rready_i, dst_axi_awready_i,
   dst_axi_wready_i, dst_axi_brsp_i, dst_axi_bvalid_i, dst_axi_arready_i,
   dst_axi_rrsp_i, dst_axi_rvalid_i
   );
   
   input 			 clk_i;
   input 			 rst_ni;

   input        [NUM_WR_DSTS:0] 	       wr_decode_i;
   input        [NUM_RD_DSTS:0] 	       rd_decode_i;      
   
   input                          axil_waddr_t src_axi_awreq_i;
   input 			               src_axi_awvalid_i;
   output logic 		               src_axi_awready_o;

   input                          axil_wdata_t src_axi_wreq_i;
   input 			               src_axi_wvalid_i;
   output logic 		               src_axi_wready_o;

   output                         axil_bresp_t src_axi_brsp_o;
   output logic 		               src_axi_bvalid_o;
   input 			               src_axi_bready_i;

   input                          axil_raddr_t src_axi_arreq_i;
   input 			               src_axi_arvalid_i;
   output logic 		               src_axi_arready_o;

   output                         axil_rdata_t src_axi_rrsp_o;
   output logic 		               src_axi_rvalid_o;
   input 			               src_axi_rready_i;

   output       [NUM_WR_DSTS-1:0] axil_waddr_t dst_axi_awreq_o;
   output logic [NUM_WR_DSTS-1:0]              dst_axi_awvalid_o;
   input        [NUM_WR_DSTS-1:0] 	       dst_axi_awready_i;

   output       [NUM_WR_DSTS-1:0] axil_wdata_t dst_axi_wreq_o;
   output logic [NUM_WR_DSTS-1:0]              dst_axi_wvalid_o;
   input        [NUM_WR_DSTS-1:0] 	       dst_axi_wready_i;

   input        [NUM_WR_DSTS-1:0] axil_bresp_t dst_axi_brsp_i;
   input        [NUM_WR_DSTS-1:0] 	       dst_axi_bvalid_i;
   output logic [NUM_WR_DSTS-1:0]              dst_axi_bready_o;

   output       [NUM_RD_DSTS-1:0] axil_raddr_t dst_axi_arreq_o;
   output logic [NUM_RD_DSTS-1:0]              dst_axi_arvalid_o;
   input        [NUM_RD_DSTS-1:0] 	       dst_axi_arready_i;

   input        [NUM_RD_DSTS-1:0] axil_rdata_t dst_axi_rrsp_i;
   input        [NUM_RD_DSTS-1:0]              dst_axi_rvalid_i;
   output logic [NUM_RD_DSTS-1:0]              dst_axi_rready_o;
   
   logic [NUM_WR_DSTS:0] 		       fif_wr_dat;
   logic [NUM_RD_DSTS:0] 		       fif_rd_dat;
   logic [NUM_WR_DSTS:0] 		       wr_accept,brsp_accept;
   logic [NUM_RD_DSTS:0] 		       rd_accept,rrsp_accept;
   logic 				       fif_wr_full,fif_rd_full,fif_wr_psh,fif_wr_pop;
   logic 				       fif_rd_psh,fif_rd_pop;
   logic 				       fif_wr_val,fif_rd_val;
   
   always_comb begin
      src_axi_awready_o    = '0;	 
      src_axi_wready_o     = '0;	 
      dst_axi_awreq_o      = '{default:'0};
      dst_axi_awvalid_o    = '0;
      dst_axi_wvalid_o     = '0;
      dst_axi_wreq_o       = '{default:'0};
      wr_accept            = '0;	 
      

      if(wr_decode_i[NUM_WR_DSTS]) begin
	 src_axi_awready_o        = '1;	 
	 src_axi_wready_o         = '1;
	 wr_accept[NUM_WR_DSTS]   = src_axi_awvalid_i & src_axi_wvalid_i;	 
      end
      else begin
	 for(int i=0; i<NUM_WR_DSTS; i++) begin
	    if(wr_decode_i[i] & !fif_wr_full) begin
	       src_axi_awready_o    = dst_axi_awready_i[i];	 
	       src_axi_wready_o     = dst_axi_wready_i[i];	    
	       dst_axi_awvalid_o[i] = src_axi_awvalid_i;
	       dst_axi_awreq_o[i]   = src_axi_awreq_i;
	       dst_axi_wvalid_o[i]  = src_axi_wvalid_i;
	       dst_axi_wreq_o[i]    = src_axi_wreq_i;	    	       
	       wr_accept[i]         = dst_axi_awvalid_o[i] & dst_axi_wvalid_o[i] & dst_axi_awready_i[i] & dst_axi_wready_i[i];	    
	    end
	 end
      end
   end

   always_comb begin
      src_axi_bvalid_o = '0;
      src_axi_brsp_o   = '0;	 
      dst_axi_bready_o = '0;	 
      brsp_accept      = '0;      
      
      if(fif_wr_val & fif_wr_dat[NUM_WR_DSTS]) begin
	 src_axi_bvalid_o           = '1;
	 src_axi_brsp_o.bresp       = AXI_SLVERR;
	 brsp_accept[NUM_WR_DSTS]   = src_axi_bready_i;
      end
      else begin	       
	 for(int i=0; i<NUM_WR_DSTS; i++) begin	 
	    if(fif_wr_val & fif_wr_dat[i]) begin
	       src_axi_bvalid_o    = dst_axi_bvalid_i[i];
	       src_axi_brsp_o      = dst_axi_brsp_i[i];
	       dst_axi_bready_o[i] = src_axi_bready_i;	 
	       brsp_accept[i]      = dst_axi_bvalid_i[i] & dst_axi_bready_o[i];
	    end	 
	 end
      end
   end

   assign fif_wr_psh = |wr_accept;   
   assign fif_wr_pop = |brsp_accept;   

   /*
    fifo AUTO_TEMPLATE (
    .din      (wr_decode_i),
    .psh      (fif_wr_psh),
    .pop      (fif_wr_pop),
    .dout     (fif_wr_dat),
    .dout_val (fif_wr_val),
    .full     (fif_wr_full),
    );
    */

   fifo #(.WIDTH(NUM_WR_DSTS+1),.DEPTH(2)) 
   u_wr_fif (/*AUTOINST*/
	     // Outputs
	     .dout			(fif_wr_dat),		 // Templated
	     .dout_val			(fif_wr_val),		 // Templated
	     .full			(fif_wr_full),		 // Templated
	     // Inputs
	     .clk			(clk_i),
	     .rst_n			(rst_ni),
	     .psh			(fif_wr_psh),		 // Templated
	     .din			(wr_decode_i),		 // Templated
	     .pop			(fif_wr_pop));		 // Templated


   always_comb begin
      src_axi_arready_o = '0;	 
      dst_axi_arreq_o   = '{default:'0};
      dst_axi_arvalid_o = '0;
      rd_accept         = '0;	 

      if(rd_decode_i[NUM_RD_DSTS]) begin
	 src_axi_arready_o        = '1;	 
	 rd_accept[NUM_RD_DSTS]   = src_axi_arvalid_i;	 
      end
      else begin
	 for(int i=0; i<NUM_RD_DSTS; i++) begin	    
	    if(rd_decode_i[i] & !fif_rd_full) begin
	       src_axi_arready_o    = dst_axi_arready_i[i];	 
	       dst_axi_arvalid_o[i] = src_axi_arvalid_i;
	       dst_axi_arreq_o[i]   = src_axi_arreq_i;	       
	       rd_accept[i]         = dst_axi_arvalid_o[i] & dst_axi_arready_i[i];
	    end
	 end
      end
   end
   
   always_comb begin
      src_axi_rvalid_o = '0;
      src_axi_rrsp_o   = '0;
      dst_axi_rready_o = '0;	 
      rrsp_accept      = '0;      

      if(fif_rd_val & fif_rd_dat[NUM_RD_DSTS]) begin
	 src_axi_rvalid_o           = '1;
	 src_axi_rrsp_o.rdata       = '0;
	 src_axi_rrsp_o.rresp       = AXI_SLVERR;
	 rrsp_accept[NUM_RD_DSTS]   = src_axi_rready_i;
      end
      else begin      	 
	 for(int i=0; i<NUM_RD_DSTS; i++) begin	 	    	 
	    if(fif_rd_val & fif_rd_dat[i]) begin
	       src_axi_rvalid_o    = dst_axi_rvalid_i[i];
	       src_axi_rrsp_o      = dst_axi_rrsp_i[i];
	       dst_axi_rready_o[i] = src_axi_rready_i;	 
	       rrsp_accept[i]      = dst_axi_rvalid_i[i] & dst_axi_rready_o[i];
	    end	 
	 end
      end
   end
   
   assign fif_rd_psh = |rd_accept;   
   assign fif_rd_pop = |rrsp_accept;   

   /*
    fifo AUTO_TEMPLATE (
    .din      (rd_decode_i),
    .psh      (fif_rd_psh),
    .pop      (fif_rd_pop),
    .dout     (fif_rd_dat),
    .dout_val (fif_rd_val),
    .full     (fif_rd_full),
    );
    */

   fifo #(.WIDTH(NUM_RD_DSTS+1),.DEPTH(2)) 
   u_rd_fif (/*AUTOINST*/
	     // Outputs
	     .dout			(fif_rd_dat),		 // Templated
	     .dout_val			(fif_rd_val),		 // Templated
	     .full			(fif_rd_full),		 // Templated
	     // Inputs
	     .clk			(clk_i),
	     .rst_n			(rst_ni),
	     .psh			(fif_rd_psh),		 // Templated
	     .din			(rd_decode_i),		 // Templated
	     .pop			(fif_rd_pop));		 // Templated
   
   
   
endmodule
