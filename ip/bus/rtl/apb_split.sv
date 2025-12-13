/*
 APB split
 */
module apb_split
  include intf_pkg.sv
  #(
    parameter NUM_DSTS   = 2
   )(/*AUTOARG*/
   // Outputs
   src_apb_pready, src_apb_rsp, dst_apb_req,
   // Inputs
   clk, rst_n, src_apb_req, decode, dst_apb_pready, dst_apb_rsp
   );
   
   // Master side	                   
   input  apb_req_t                  src_apb_req_i;
   output                            src_apb_pready_o;
   output apb_rsp_t                  src_apb_rsp_o;

   input [NUM_DSTS:0] 	             decode_i;

   // Slave side
   output apb_req_t [NUM_DSTS-1:0]   dst_apb_req_o;
   input  [NUM_DSTS-1:0]             dst_apb_pready_i;
   input  apb_rsp_t [NUM_DSTS-1:0]   dst_apb_rsp_i;


   
   // Mux back responses
   always_comb begin
      src_apb_pready_o      = dst_apb_pready_i[0];
      src_apb_rsp_o.prdata  = dst_apb_rsp_i[0].prdata;
      src_apb_rsp_o.pslverr = dst_apb_rsp_i[0].pslverr;      

      dst_apb_req_o         = '0;

      for(int i=0; i<NUM_WR_DSTS; i++) begin
	 if(decode_i[i]) begin
	    src_apb_pready_o      = dst_apb_pready_i[i];
	    src_apb_rsp_o.prdata  = dst_apb_rsp_i[i].prdata;
	    src_apb_rsp_o.pslverr = dst_apb_rsp_i[i].pslverr;

	    dst_apb_req_o[i]   = src_apb_req_i;
	 end
      end
   end // always
   
endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-typedef-regexp: "_t$"
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
