/*
 APB split
 */
`include "intf_pkg.sv"

module apb_split
  import intf_pkg::*;
  #(
    parameter NumDsts   = 2
   )(
   src_apb_req_i, src_apb_pready_o, src_apb_rsp_o, decode_i,
   dst_apb_req_o, dst_apb_pready_i, dst_apb_rsp_i
   );

   // Master side
   input  apb_req_t                   src_apb_req_i;
   output logic                       src_apb_pready_o;
   output var apb_rsp_t               src_apb_rsp_o;

   input  logic [NumDsts:0]           decode_i;

   // Slave side
   output var apb_req_t [NumDsts-1:0] dst_apb_req_o;
   input  logic [NumDsts-1:0]         dst_apb_pready_i;
   input  apb_rsp_t [NumDsts-1:0]     dst_apb_rsp_i;



   // Mux back responses
   always_comb begin
      src_apb_pready_o      = dst_apb_pready_i[0];
      src_apb_rsp_o.prdata  = dst_apb_rsp_i[0].prdata;
      src_apb_rsp_o.pslverr = dst_apb_rsp_i[0].pslverr;

      dst_apb_req_o         = '0;

      for(int i=0; i<NumDsts; i++) begin
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
