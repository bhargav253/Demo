`include "intf_pkg.sv"

module axil_rd_ext
  import intf_pkg::*;
  #(
    parameter MemBase   = 32'h10000000,
    parameter DataWidth = `AXI_DATA_WIDTH)
   (/*AUTOARG*/
   // Outputs
   axi_arready_o, axi_rrsp_o, axi_rvalid_o, ext_rd_req_o,
   // Inputs
   clk_i, rst_ni, axi_arreq_i, axi_arvalid_i, axi_rready_i, ext_rsp_dat_i,
   ext_rsp_val_i
   );

   input  logic                 clk_i;
   input  logic                 rst_ni;

   input  axil_raddr_t          axi_arreq_i;
   input  logic                 axi_arvalid_i;
   output logic                 axi_arready_o;

   output axil_rdata_t          axi_rrsp_o;
   output logic                 axi_rvalid_o;
   input  logic                 axi_rready_i;

   output logic                 ext_rd_req_o;
   input  logic [DataWidth-1:0] ext_rsp_dat_i;
   input  logic                 ext_rsp_val_i;

   logic                 rd_resp_pend,rd_resp_full;
   logic                 rd_addr_err;
   axi_resp_t            mem_rd_error,mem_rd_error_d1;
   logic [DataWidth-1:0] skid_fif_dat;
   logic                 skid_fif_val;

   assign rd_addr_err  = !(axi_arreq_i.araddr == MemBase);

   assign ext_rd_req_o = axi_arvalid_i && !rd_addr_err & !rd_resp_full;
   assign mem_rd_error = axi_resp_t'{(axi_arvalid_i & rd_addr_err),1'b0};
   assign axi_arready_o  = axi_arvalid_i & !rd_resp_full;

   always_comb begin
      axi_rrsp_o.rdata    = '0;
      axi_rrsp_o.rresp    = '0;
      axi_rvalid_o        = '0;

      if(|mem_rd_error_d1) begin
         axi_rrsp_o.rdata = '0;
         axi_rrsp_o.rresp = mem_rd_error_d1;
         axi_rvalid_o     = '1;
      end
      else if(skid_fif_val | ext_rsp_val_i) begin
         axi_rrsp_o.rdata = skid_fif_val ? skid_fif_dat : ext_rsp_dat_i;
         axi_rrsp_o.rresp = mem_rd_error_d1;
         axi_rvalid_o     = '1;
      end
   end

   assign rd_resp_full = rd_resp_pend & !axi_rready_i;

   always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
         rd_resp_pend    <= '0;
         mem_rd_error_d1 <= '0;
      end
      else begin
         rd_resp_pend    <= axi_arvalid_i & !rd_resp_full ? '1 :           (ext_rsp_val_i | skid_fif_val | mem_rd_error_d1[1]) & axi_rready_i ? '0 : rd_resp_pend;
         mem_rd_error_d1 <= axi_arvalid_i & !rd_resp_full ? mem_rd_error : (ext_rsp_val_i | skid_fif_val | mem_rd_error_d1[1]) & axi_rready_i ? '0 : mem_rd_error_d1;
      end
   end

   always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
         skid_fif_val <= '0;
         skid_fif_dat <= '0;
      end
      else begin
         skid_fif_val <= ext_rsp_val_i & !axi_rready_i ? '1 : axi_rready_i ? '0 : skid_fif_val;
         skid_fif_dat <= ext_rsp_val_i ? ext_rsp_dat_i : skid_fif_dat;
      end
   end

endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
