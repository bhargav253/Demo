`include intf_pkg.sv

module axil_rom
  import intf_pkg::*;
  #(
    parameter MEM_START  = 32'h00000000,
    parameter MEM_STOP   = 32'h00000400,    
    parameter DATA_WIDTH = `AXI_DATA_WIDTH,
    parameter ADDR_WIDTH = `AXI_ADDR_WIDTH,
    parameter STRB_WIDTH = (DATA_WIDTH/8))
   (/*AUTOARG*/
   // Outputs
   axi_arready_o, axi_rrsp_o, axi_rvalid_o, mem_ren_o, mem_raddr_o,
   // Inputs
   clk_i, rst_ni, axi_arreq_i, axi_arvalid_i, axi_rready_i, mem_rdata_i
   );
   
   input 			 clk_i;
   input 			 rst_ni;

   input axil_raddr_t            axi_arreq_i;
   input 			 axi_arvalid_i;
   output logic 		 axi_arready_o;

   output axil_rdata_t           axi_rrsp_o;
   output logic 		 axi_rvalid_o;
   input 			 axi_rready_i;
   
   output 			 mem_ren_o;   
   output [ADDR_WIDTH-1:0] 	 mem_raddr_o;   
   input [DATA_WIDTH-1:0] 	 mem_rdata_i;   
   
   logic 			 rd_resp_pend,rd_resp_full;
   logic 			 rd_addr_err;   
   axi_resp_t 			 mem_rd_error,mem_rd_error_d1;

   assign rd_addr_err  = !((axi_arreq_i.araddr >= MEM_START) && (axi_arreq_i.araddr < MEM_STOP));
   
   assign mem_raddr_o  = axi_arreq_i.araddr;      
   assign mem_ren_o    = axi_arvalid_i & !rd_addr_err & !rd_resp_full;   
   assign mem_rd_error = axi_resp_t'{(axi_arvalid_i & rd_addr_err),1'b0};   

   assign axi_arready_o   = axi_arvalid_i & !rd_resp_full;
   assign axi_rrsp_o.rdata = |mem_rd_error_d1 ? '0 : rd_resp_pend ? mem_rdata_i : '0;
   assign axi_rrsp_o.rresp = mem_rd_error_d1;
   assign axi_rvalid_o     = rd_resp_pend;

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
