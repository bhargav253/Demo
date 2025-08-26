module axil_dp_ram
  #(
    
    parameter MEM_START  = 32'h00000400,
    parameter MEM_STOP   = 32'h00001000,    
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8))
   (/*AUTOARG*/
   // Outputs
   axi_awready, axi_wready, axi_bresp, axi_bvalid, axi_arready,
   axi_rdata, axi_rresp, axi_rvalid, mem_wen, mem_wdata, mem_waddr,
   mem_ren, mem_raddr,
   // Inputs
   clk, rst_n, axi_awaddr, axi_awvalid, axi_wdata, axi_wstrb,
   axi_wvalid, axi_bready, axi_araddr, axi_arvalid, axi_rready,
   mem_rdata
   );
   
   input 			 clk;
   input 			 rst_n;

   input [ADDR_WIDTH-1:0] 	 axi_awaddr;
   input 			 axi_awvalid;
   output logic 		 axi_awready;

   input [DATA_WIDTH-1:0] 	 axi_wdata;
   input [STRB_WIDTH-1:0] 	 axi_wstrb;
   input 			 axi_wvalid;
   output logic 		 axi_wready;

   output logic [1:0] 		 axi_bresp;
   output logic 		 axi_bvalid;
   input 			 axi_bready;

   input [ADDR_WIDTH-1:0] 	 axi_araddr;
   input 			 axi_arvalid;
   output logic 		 axi_arready;

   output logic [DATA_WIDTH-1:0] axi_rdata;
   output logic [1:0] 		 axi_rresp;
   output logic 		 axi_rvalid;
   input 			 axi_rready;
   
   output logic [STRB_WIDTH-1:0] mem_wen;
   output logic [DATA_WIDTH-1:0] mem_wdata;   
   output logic [ADDR_WIDTH-1:0] mem_waddr;      
   
   output logic 		 mem_ren;   
   output logic [ADDR_WIDTH-1:0] mem_raddr;   
   input [DATA_WIDTH-1:0] 	 mem_rdata;   
   
   logic 			 rd_addr_err,wr_addr_err;   
   logic [1:0] 			 mem_rd_error,mem_rd_error_d1;
   logic [1:0] 			 mem_wr_error,mem_wr_error_d1;      
   logic 			 wr_resp_pend,wr_resp_full;
   logic 			 rd_resp_pend,rd_resp_full;      
   
   assign wr_addr_err  = !((axi_awaddr >= MEM_START) && (axi_awaddr < MEM_STOP));

   assign mem_wdata    = axi_wdata;   
   assign mem_waddr    = axi_awaddr;
   assign mem_wen      = axi_awvalid && axi_wvalid & !wr_addr_err & !wr_resp_full ? axi_wstrb : '0;
   assign mem_wr_error = {(axi_awvalid & wr_addr_err),1'b0};   
   assign axi_awready  = axi_awvalid & axi_wvalid & !wr_resp_full;
   assign axi_wready   = axi_awvalid & axi_wvalid & !wr_resp_full;
   assign axi_bresp    = mem_wr_error_d1;
   assign axi_bvalid   = wr_resp_pend;
   
   assign wr_resp_full = wr_resp_pend & !axi_bready;   

   always @(posedge clk) begin
      if (!rst_n) begin
	 wr_resp_pend    <= '0;	 
	 mem_wr_error_d1 <= '0;
      end
      else begin
	 wr_resp_pend    <= axi_awvalid && axi_wvalid & !wr_resp_full ? '1 :           axi_bready ? '0 : wr_resp_pend;
         mem_wr_error_d1 <= axi_awvalid && axi_wvalid & !wr_resp_full ? mem_wr_error : axi_bready ? '0 : mem_wr_error_d1;
      end
   end   

   assign rd_addr_err  = !((axi_araddr >= MEM_START) && (axi_araddr < MEM_STOP));
   
   assign mem_raddr    = axi_araddr;      
   assign mem_ren      = axi_arvalid & !rd_addr_err & !rd_resp_full;   
   assign mem_rd_error = {(axi_arvalid & rd_addr_err),1'b0};   

   assign axi_arready = !rd_resp_full;
   assign axi_rdata   = |mem_rd_error_d1 ? '0 : rd_resp_pend ? mem_rdata : '0;
   assign axi_rresp   = mem_rd_error_d1;
   assign axi_rvalid  = rd_resp_pend;   

   assign rd_resp_full = rd_resp_pend & !axi_rready;   
   
   always @(posedge clk) begin
      if (!rst_n) begin
	 rd_resp_pend    <= '0;	 
	 mem_rd_error_d1 <= '0;
      end
      else begin
	 rd_resp_pend    <= axi_arvalid & !rd_resp_full ? '1 :           axi_rready ? '0 : rd_resp_pend;	 
         mem_rd_error_d1 <= axi_arvalid & !rd_resp_full ? mem_rd_error : axi_rready ? '0 : mem_rd_error_d1;
      end
   end   

endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
