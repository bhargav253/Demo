`include intf_pkg.sv

module axil_reg
  import intf_pkg::*;
  #(
    parameter MEM_BASE   = 32'h00000000,
    parameter DATA_WIDTH = `AXI_DATA_WIDTH,
    parameter ADDR_WIDTH = `AXI_ADDR_WIDTH,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter REG_AWIDTH = 16)
   (/*AUTOARG*/
   // Outputs
   axi_awready_o, axi_wready_o, axi_brsp_o, axi_bvalid_o, axi_arready_o,
   axi_rrsp_o, axi_rvalid_o, reg_wdata_o, reg_be_o, reg_ren_o, reg_wen_o,
   reg_addr_o,
   // Inputs
   clk_i, rst_ni, axi_awreq_i, axi_awvalid_i, axi_wreq_i, axi_wvalid_i,
   axi_bready_i, axi_arreq_i, axi_arvalid_i, axi_rready_i, reg_busy_i,
   reg_rdata_i, reg_error_i
   );
   
   input 			 clk_i;
   input 			 rst_ni;

   input axil_waddr_t 		 axi_awreq_i;
   input 			 axi_awvalid_i;
   output logic 		 axi_awready_o;

   input axil_wdata_t 		 axi_wreq_i;
   input 			 axi_wvalid_i;
   output logic 		 axi_wready_o;

   output axil_bresp_t 	         axi_brsp_o;
   output logic 		 axi_bvalid_o;
   input 			 axi_bready_i;

   input axil_raddr_t 		 axi_arreq_i;
   input 			 axi_arvalid_i;
   output logic 		 axi_arready_o;

   output axil_rdata_t 	         axi_rrsp_o;
   output logic			 axi_rvalid_o;
   input 			 axi_rready_i;   
   
   output logic [DATA_WIDTH-1:0] reg_wdata_o;
   output logic [STRB_WIDTH-1:0] reg_be_o;
   output logic 		 reg_ren_o;
   output logic 		 reg_wen_o;   
   output logic [REG_AWIDTH-1:0] reg_addr_o;
   input 			 reg_busy_i;
   input [DATA_WIDTH-1:0] 	 reg_rdata_i;

   input 			 reg_error_i;  
   
   
   
   logic 			 rd_addr_err,wr_addr_err;   
   axi_resp_t 			 mem_rd_error,mem_rd_error_d1;
   axi_resp_t 			 mem_wr_error,mem_wr_error_d1;      
   logic 			 wr_resp_wait;
   logic 			 rd_resp_wait;      
   

   assign reg_addr_o   = axi_arvalid_i ? axi_arreq_i.araddr[REG_AWIDTH-1:0] : axi_awreq_i.awaddr[REG_AWIDTH-1:0];
   assign reg_ren_o    = axi_arvalid_i && axi_rvalid_o & !rd_resp_wait;
   assign reg_wen_o    = axi_awvalid_i && axi_wvalid_i & !wr_resp_wait;
   assign reg_wdata_o  = axi_wreq_i.wdata;
   assign reg_be_o     = axi_wreq_i.wstrb;   
   
   assign mem_wr_error = axi_resp_t'{(axi_awvalid_i & axi_wvalid_i & wr_addr_err),1'b0};   
   assign axi_awready_o  = axi_awvalid_i && axi_wvalid_i & !wr_resp_wait;
   assign axi_wready_o   = axi_awvalid_i && axi_wvalid_i & !wr_resp_wait;
   assign axi_brsp_o.bresp = mem_wr_error_d1;
   assign axi_bvalid_o   = ~reg_busy_i;

   assign wr_addr_err  = reg_error_i;
   assign wr_resp_wait = reg_busy_i | !axi_bready_i;   

   always @(posedge clk_i) begin
      if (!rst_ni) begin
	 mem_wr_error_d1 <= '0;
      end
      else begin
         mem_wr_error_d1 <= axi_awvalid_i && axi_wvalid_i & !wr_resp_wait ? mem_wr_error : axi_bready_i ? '0 : mem_wr_error_d1;
      end
   end           

   assign rd_addr_err  = reg_error_i;

   assign mem_rd_error = axi_resp_t'{(axi_arvalid_i & rd_addr_err),1'b0};   
   assign axi_arready_o  = axi_arvalid_i & !rd_resp_wait;

   assign rd_resp_wait = reg_busy_i | !axi_rready_i;   
   
   assign axi_rrsp_o.rdata    = |mem_rd_error_d1 ? '0 : reg_rdata_i;
   assign axi_rrsp_o.rresp    = mem_rd_error_d1;
   assign axi_rvalid_o        = ~reg_busy_i;   
      
   always @(posedge clk_i) begin
      if (!rst_ni) begin
	 mem_rd_error_d1 <= '0;
      end
      else begin
         mem_rd_error_d1 <= axi_arvalid_i & !rd_resp_wait ? mem_rd_error : axi_rready_i ? '0 : mem_rd_error_d1;	 
      end
   end      
   
endmodule
