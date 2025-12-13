`include intf_pkg.sv

module axil_dp_ram
  import intf_pkg::*;
  #(
    
    parameter MEM_START  = 32'h00000400,
    parameter MEM_STOP   = 32'h00001000,    
    parameter DATA_WIDTH = `AXI_DATA_WIDTH,
    parameter ADDR_WIDTH = `AXI_ADDR_WIDTH,
    parameter STRB_WIDTH = (DATA_WIDTH/8))
   (/*AUTOARG*/
   // Outputs
   axi_awready_o, axi_wready_o, axi_brsp_o, axi_bvalid_o, axi_arready_o,
   axi_rrsp_o, axi_rvalid_o, mem_wen_o, mem_wdata_o, mem_waddr_o,
   mem_ren_o, mem_raddr_o,
   // Inputs
   clk_i, rst_ni, axi_awreq_i, axi_awvalid_i, axi_wreq_i, axi_wvalid_i,
   axi_bready_i, axi_arreq_i, axi_arvalid_i, axi_rready_i, mem_rdata_i
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
   output logic 		 axi_rvalid_o;
   input 			 axi_rready_i;
   
   output logic [STRB_WIDTH-1:0] mem_wen_o;
   output logic [DATA_WIDTH-1:0] mem_wdata_o;   
   output logic [ADDR_WIDTH-1:0] mem_waddr_o;      
   
   output logic 		 mem_ren_o;   
   output logic [ADDR_WIDTH-1:0] mem_raddr_o;   
   input [DATA_WIDTH-1:0] 	 mem_rdata_i;   
   
   logic 			 rd_addr_err,wr_addr_err;   
   axi_resp_t 			 mem_rd_error,mem_rd_error_d1;
   axi_resp_t 			 mem_wr_error,mem_wr_error_d1;      
   logic 			 wr_resp_pend,wr_resp_full;
   logic 			 rd_resp_pend,rd_resp_full;      
   
   assign wr_addr_err  = !((axi_awreq_i.awaddr >= MEM_START) && (axi_awreq_i.awaddr < MEM_STOP));

   assign mem_wdata_o  = axi_wreq_i.wdata;   
   assign mem_waddr_o  = axi_awreq_i.awaddr;
   assign mem_wen_o    = axi_awvalid_i && axi_wvalid_i & !wr_addr_err & !wr_resp_full ? axi_wreq_i.wstrb : '0;
   assign mem_wr_error = axi_resp_t'{(axi_awvalid_i & wr_addr_err),1'b0};   
   assign axi_awready_o  = axi_awvalid_i & axi_wvalid_i & !wr_resp_full;
   assign axi_wready_o   = axi_awvalid_i & axi_wvalid_i & !wr_resp_full;
   assign axi_brsp_o.bresp = mem_wr_error_d1;
   assign axi_bvalid_o   = wr_resp_pend;
   
   assign wr_resp_full = wr_resp_pend & !axi_bready_i;   

   always @(posedge clk_i) begin
      if (!rst_ni) begin
	 wr_resp_pend    <= '0;	 
	 mem_wr_error_d1 <= '0;
      end
      else begin
	 wr_resp_pend    <= axi_awvalid_i && axi_wvalid_i & !wr_resp_full ? '1 :           axi_bready_i ? '0 : wr_resp_pend;
         mem_wr_error_d1 <= axi_awvalid_i && axi_wvalid_i & !wr_resp_full ? mem_wr_error : axi_bready_i ? '0 : mem_wr_error_d1;
      end
   end   

   assign rd_addr_err  = !((axi_arreq_i.araddr >= MEM_START) && (axi_arreq_i.araddr < MEM_STOP));
   
   assign mem_raddr_o  = axi_arreq_i.araddr;      
   assign mem_ren_o    = axi_arvalid_i & !rd_addr_err & !rd_resp_full;   
   assign mem_rd_error = axi_resp_t'{(axi_arvalid_i & rd_addr_err),1'b0};   

   assign axi_arready_o = !rd_resp_full;
   assign axi_rrsp_o.rdata   = |mem_rd_error_d1 ? '0 : rd_resp_pend ? mem_rdata_i : '0;
   assign axi_rrsp_o.rresp   = mem_rd_error_d1;
   assign axi_rvalid_o  = rd_resp_pend;   

   assign rd_resp_full = rd_resp_pend & !axi_rready_i;   
   
   always @(posedge clk_i) begin
      if (!rst_ni) begin
	 rd_resp_pend    <= '0;	 
	 mem_rd_error_d1 <= '0;
      end
      else begin
	 rd_resp_pend    <= axi_arvalid_i & !rd_resp_full ? '1 :           axi_rready_i ? '0 : rd_resp_pend;	 
         mem_rd_error_d1 <= axi_arvalid_i & !rd_resp_full ? mem_rd_error : axi_rready_i ? '0 : mem_rd_error_d1;
      end
   end   

endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
