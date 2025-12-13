`include intf_pkg.sv

module axil_wr_ext
  import intf_pkg::*;
  #(
    parameter MEM_BASE   = 32'h10000000,
    parameter DATA_WIDTH = `AXI_DATA_WIDTH,
    parameter ADDR_WIDTH = `AXI_ADDR_WIDTH,
    parameter STRB_WIDTH = (DATA_WIDTH/8))
   (/*AUTOARG*/
   // Outputs
   axi_awready_o, axi_wready_o, axi_brsp_o, axi_bvalid_o, ext_wr_dat_o,
   ext_wen_o, ext_wr_req_o,
   // Inputs
   clk_i, rst_ni, axi_awreq_i, axi_awvalid_i, axi_wreq_i, axi_wvalid_i,
   axi_bready_i, ext_rsp_val_i
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

   input 			 ext_rsp_val_i;
   output logic [DATA_WIDTH-1:0] ext_wr_dat_o;
   output logic [STRB_WIDTH-1:0] ext_wen_o;   
   output 			 ext_wr_req_o;   
   
   logic 			 wr_addr_err;   
   axi_resp_t 			 mem_wr_error,mem_wr_error_d1;      
   logic 			 fif_full,fif_psh;   
   logic 			 wr_resp_full,wr_resp_pend;   
   
   assign wr_addr_err  = !(axi_awreq_i.awaddr == MEM_BASE);

   assign fif_psh      = axi_awvalid_i && axi_wvalid_i & !wr_addr_err & !fif_full & !wr_resp_full;
   assign mem_wr_error = axi_resp_t'{(axi_awvalid_i & axi_wvalid_i & wr_addr_err),1'b0};   
   assign axi_awready_o  = axi_awvalid_i && axi_wvalid_i & !fif_full & !wr_resp_full;
   assign axi_wready_o   = axi_awvalid_i && axi_wvalid_i & !fif_full & !wr_resp_full;
   assign axi_brsp_o.bresp = mem_wr_error_d1;
   assign axi_bvalid_o   = wr_resp_pend;

   assign wr_resp_full = wr_resp_pend & !axi_bready_i;   

   always @(posedge clk_i) begin
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
    .din      ({axi_wreq_i.wdata,axi_wreq_i.wstrb}),
    .psh      (fif_psh),
    .pop      (ext_rsp_val_i),
    .dout     ({ext_wr_dat_o,ext_wen_o}),
    .dout_val (ext_wr_req_o),
    .full     (fif_full),
    );
    */

   fifo #(.WIDTH(DATA_WIDTH+STRB_WIDTH),.DEPTH(1)) 
   u_fif (/*AUTOINST*/
	  // Outputs
	  .dout				({ext_wr_dat_o,ext_wen_o}), // Templated
	  .dout_val			(ext_wr_req_o),		 // Templated
	  .full				(fif_full),		 // Templated
	  // Inputs
	  .clk				(clk_i),
	  .rst_n			(rst_ni),
	  .psh				(fif_psh),		 // Templated
	  .din				({axi_wreq_i.wdata,axi_wreq_i.wstrb}), // Templated
	  .pop				(ext_rsp_val_i));		 // Templated
   
   
   
endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
