module apb_reg
  include intf_pkg.sv
  #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter REG_AWIDTH = 16)
   (/*AUTOARG*/
   // Outputs
   apb_pready_o, apb_rsp_o, wdata_o, be_o, ren_o, wen_o, addr_o,
   // Inputs
   clk_i, rst_ni, apb_req_i, busy_i, rdata_i, error_i
   );

   // Clock and Reset
   input logic 		         clk_i;
   input logic 		         rst_ni;

   // APB Slave Interface
   input  apb_req_t              apb_req_i;
   output logic 		 apb_pready_o;
   output apb_rsp_t              apb_rsp_o;

   // Register Interface
   output logic [DATA_WIDTH-1:0] wdata_o;
   output logic [STRB_WIDTH-1:0] be_o;
   output logic 		 ren_o;
   output logic 		 wen_o;
   output logic [REG_AWIDTH-1:0] addr_o;
   input logic 			 busy_i;
   input logic [DATA_WIDTH-1:0]  rdata_i;
   input logic 			 error_i;   

   // Internal signals
   logic 			 apb_access;
   logic 			 apb_write;
   logic 			 apb_read;
   logic 			 addr_error;
   logic 			 response_pending;
   logic [DATA_WIDTH-1:0] 	 prdata_reg;
   logic 			 pslverr_reg;
   logic 			 pready_reg;

   // APB transaction detection
   assign apb_access = apb_req_i.psel && apb_req_i.penable;
   assign apb_write  = apb_access && apb_req_i.pwrite;
   assign apb_read   = apb_access && !apb_req_i.pwrite;

   // Register interface connections
   assign addr_o  = apb_req_i.paddr[REG_AWIDTH-1:0];
   assign wdata_o = apb_req_i.pwdata;
   assign be_o    = apb_req_i.pstrb;
   assign wen_o   = apb_write && !error_i && !response_pending;
   assign ren_o   = apb_read && !error_i && !response_pending;

   // Response generation
   always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
         prdata_reg       <= '0;
         pslverr_reg      <= '0;
         pready_reg       <= '0;
         response_pending <= '0;
      end else begin
         // Capture response when register operation completes
         if ((wen_o || ren_o) && !busy_i) begin
            prdata_reg       <= rdata_i;
            pslverr_reg      <= error_i || addr_error;
            pready_reg       <= 1'b1;
            response_pending <= 1'b1;
         end
         // Clear response when APB transaction completes
         else if (pready_reg && apb_access) begin
            pready_reg       <= 1'b0;
            response_pending <= 1'b0;
         end
         // Handle address errors immediately
         else if (apb_access && addr_error && !response_pending) begin
            prdata_reg       <= '0;
            pslverr_reg      <= 1'b1;
            pready_reg       <= 1'b1;
            response_pending <= 1'b1;
         end
      end
   end

   // APB output assignments
   assign apb_rsp_o.prdata  = prdata_reg;
   assign apb_rsp_o.pslverr = pslverr_reg;
   assign apb_pready_o      = pready_reg || (apb_access && addr_error && !response_pending);

endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-typedef-regexp: "_t$"
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
