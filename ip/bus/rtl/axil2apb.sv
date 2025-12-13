/*
 Axi4L to APB
 */
module axil2apb
  include intf_pkg.sv
   (/*AUTOARG*/
   // Outputs
   axi_awready, axi_wready, axi_bresp, axi_bvalid, axi_arready,
   axi_rdata, axi_rresp, axi_rvalid, apb_psel, apb_penable, apb_paddr,
   apb_pwrite, apb_pwdata, apb_pstrb,
   // Inputs
   clk, rst_n, axi_awaddr, axi_awvalid, axi_wdata, axi_wstrb,
   axi_wvalid, axi_bready, axi_araddr, axi_arvalid, axi_rready,
   apb_prdata, apb_pready, apb_pslverr
   );
   
   // Clock and Reset
   input logic 	       clk_i;
   input logic 	       rst_ni;
   
   // AXI4-Lite Slave Interface
   // Write Address Channel
   input  axil_waddr_t axi_awreq_i;
   input  logic	       axi_awvalid_i;
   output logic        axi_awready_o;
   
   // Write Data Channel
   input  axil_wdata_t axi_wreq_i;
   input  logic	       axi_wvalid_i;
   output logic        axi_wready_o;
   
   // Write Response Channel
   output axil_bresp_t axi_brsp_o;
   output logic        axi_bvalid_o;
   input  logic	       axi_bready_i;
   
   // Read Address Channel
   input  axil_raddr_t axi_arreq_i;
   input  logic        axi_arvalid_i;
   output logic        axi_arready_o;
   
   // Read Data Channel
   output axil_rdata_t axi_rrsp_o;
   output logic        axi_rvalid_o;
   input  logic        axi_rready_i;
   
   // APB Master Interface
   // APB Slave Interface
   output apb_req_t    apb_req_o;
   input  logic        apb_pready_i;
   input  apb_rsp_t    apb_rsp_i;
   );

   // Internal signals
   typedef enum 		 logic [1:0] {
				 IDLE,
				 SETUP,
				 ACCESS,
				 RESPONSE
				 } apb_state_t;
   
   apb_state_t current_state, next_state;
   
   logic [ADDR_WIDTH-1:0] 	 addr_reg;
   logic [DATA_WIDTH-1:0] 	 wdata_reg;
   logic [STRB_WIDTH-1:0] 	 wstrb_reg;
   logic 			 write_reg;
   logic 			 error_reg;
   
   // Control signals
   logic 			 start_transaction;
   logic 			 transaction_complete;
   logic 			 read_transaction;
   logic 			 write_transaction;
   
   // State machine
   always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
         current_state <= IDLE;
      end else begin
         current_state <= next_state;
      end
   end
   
   // Next state logic
   always_comb begin
      next_state = current_state;
      
      case (current_state)
        IDLE: begin
           if (start_transaction) begin
              next_state = SETUP;
           end
        end
        
        SETUP: begin
           next_state = ACCESS;
        end
        
        ACCESS: begin
           if (apb_pready_i) begin
              next_state = RESPONSE;
           end
        end
        
        RESPONSE: begin
           if ((write_transaction && axi_bready_i) || 
             (read_transaction && axi_rready_i)) begin
              next_state = IDLE;
           end
        end
      endcase
   end
   
   // Transaction detection
   assign start_transaction = (axi_awvalid_i && axi_wvalid_i && !write_transaction) || 
                              (axi_arvalid_i && !read_transaction);
   
   assign write_transaction = axi_awvalid_i && axi_wvalid_i;
   assign read_transaction = axi_arvalid_i;
   
   // Register AXI signals
   always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
         addr_reg    <= '0;
         wdata_reg   <= '0;
         wstrb_reg   <= '0;
         write_reg   <= 1'b0;
         error_reg   <= 1'b0;
      end else begin
         if (current_state == IDLE && start_transaction) begin
            if (write_transaction) begin
               addr_reg  <= axi_awreq_i.awaddr;
               wdata_reg <= axi_wreq_i.wdata;
               wstrb_reg <= axi_wreq_i.wstrb;
               write_reg <= 1'b1;
            end else if (read_transaction) begin
               addr_reg  <= axi_arreq_i.araddr;
               write_reg <= 1'b0;
            end
         end
         
         if (current_state == ACCESS && apb_pready_i) begin
            error_reg <= apb_rsp_i.pslverr;
         end
      end
   end
   
   // APB interface control
   assign apb_req_o.psel    = (current_state == SETUP) || (current_state == ACCESS);
   assign apb_req_o.penable = (current_state == ACCESS);
   assign apb_req_o.paddr   = addr_reg;
   assign apb_req_o.pwrite  = write_reg;
   assign apb_req_o.pwdata  = wdata_reg;
   assign apb_req_o.pstrb   = wstrb_reg;
   
   // AXI interface control
   assign axi_awready_o = (current_state == IDLE) && write_transaction;
   assign axi_wready_o  = (current_state == IDLE) && write_transaction;
   assign axi_arready_o = (current_state == IDLE) && read_transaction;
   
   assign axi_brsp_o.bresp = error_reg ? 2'b10 : 2'b00; // SLVERR : OKAY
   assign axi_bvalid_o     = (current_state == RESPONSE) && write_reg;
   
   assign axi_rrsp_o.rdata = apb_rsp_i.prdata;
   assign axi_rrsp_o.rresp = error_reg ? 2'b10 : 2'b00; // SLVERR : OKAY
   assign axi_rvalid_o     = (current_state == RESPONSE) && !write_reg;
   
   assign transaction_complete = (current_state == RESPONSE) && 
                                 ((write_reg && axi_bready_i) || 
                                 (!write_reg && axi_rready_i));

endmodule
