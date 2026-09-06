`include "intf_pkg.sv"

module axil_rom
  import intf_pkg::*;
  #(
    parameter MemStart  = 32'h00000000,
    parameter MemStop   = 32'h00000400,
    parameter DataWidth = `AXI_DATA_WIDTH,
    parameter AddrWidth = `AXI_ADDR_WIDTH)
   (/*AUTOARG*/
   // Outputs
   axi_arready_o, axi_rrsp_o, axi_rvalid_o, mem_ren_o, mem_raddr_o,
   // Inputs
   clk_i, rst_ni, axi_arreq_i, axi_arvalid_i, axi_rready_i, mem_rdata_i
   );

   input  logic                 clk_i;
   input  logic                 rst_ni;

   input  axil_raddr_t          axi_arreq_i;
   input  logic                 axi_arvalid_i;
   output logic                 axi_arready_o;

   output axil_rdata_t          axi_rrsp_o;
   output logic                 axi_rvalid_o;
   input  logic                 axi_rready_i;

   output logic                 mem_ren_o;
   output logic [AddrWidth-1:0] mem_raddr_o;
   input  logic [DataWidth-1:0] mem_rdata_i;

   logic      rd_resp_pend,rd_resp_full;
   logic      rd_addr_err;
   axi_resp_t mem_rd_error,mem_rd_error_d1;

   if (MemStart == 0) begin : gen_zero_base
      assign rd_addr_err = axi_arreq_i.araddr >= MemStop;
   end else begin : gen_nonzero_base
      assign rd_addr_err = (axi_arreq_i.araddr < MemStart) ||
                           (axi_arreq_i.araddr >= MemStop);
   end

   assign mem_raddr_o  = axi_arreq_i.araddr;
   assign mem_ren_o    = axi_arvalid_i & !rd_addr_err & !rd_resp_full;
   assign mem_rd_error = axi_resp_t'{(axi_arvalid_i & rd_addr_err),1'b0};

   assign axi_arready_o   = axi_arvalid_i & !rd_resp_full;
   assign axi_rrsp_o.rdata = |mem_rd_error_d1 ? '0 : rd_resp_pend ? mem_rdata_i : '0;
   assign axi_rrsp_o.rresp = mem_rd_error_d1;
   assign axi_rvalid_o     = rd_resp_pend;

   assign rd_resp_full = rd_resp_pend & !axi_rready_i;

   always_ff @(posedge clk_i) begin
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
