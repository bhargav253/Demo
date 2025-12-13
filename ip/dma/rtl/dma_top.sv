/*
*/

module dma_top
  import intf_pkg::*;
  import dma_pkg::*;
  import dma_reg_pkg::*;
#(
  parameter int DMA_ID_VAL = 0
)(/*AUTOARG*/
   // Outputs
   dma_csr_rsp_o, dma_csr_ready_o, axi_awreq_o, axi_awvalid_o,
   axi_wreq_o, axi_wvalid_o, axi_bready_o, axi_arreq_o, axi_arvalid_o,
   axi_rready_o, dma_done_o, dma_error_o,
   // Inputs
   clk, rst, dma_csr_req_i, axi_awready_i, axi_wready_i, axi_brsp_i,
   axi_bvalid_i, axi_arready_i, axi_rrsp_i, axi_rvalid_i
   );

  input                 clk;
  input                 rst;
  // CSR DMA I/F
  input   apb_req_t     dma_csr_req_i;
  output  apb_rsp_t     dma_csr_rsp_o;
  output                dma_csr_ready_o,
  // Master DMA I/F
  output  axi_waddr_t   axi_awreq_o;
  output  logic         axi_awvalid_o;
  input                 axi_awready_i;
  output  axi_wdata_t   axi_wreq_o;
  output  logic         axi_wvalid_o;
  input   logic         axi_wready_i;
  input   axi_bresp_t   axi_brsp_i;
  input   logic         axi_bvalid_i;
  output  logic	        axi_bready_o;
  output  axi_raddr_t   axi_arreq_o;
  output  logic         axi_arvalid_o;
  input   logic         axi_arready_i;
  input   axi_rdata_t   axi_rrsp_i;
  input   logic         axi_rvalid_i;
  output  logic         axi_rready_o;
  // Triggers - IRQs
  output  logic         dma_done_o;
  output  logic 	dma_error_o;
   

  dma_reg2hw_t dma_csr_reg2hw;   
  dma_hw2reg_t dma_csr_hw2reg;
   
  dma_desc_t  [`DMA_NUM_DESC-1:0]               dma_desc;
  dma_control_t                                 dma_ctrl;
  dma_status_t                                  dma_stats;
  dma_error_t                                   dma_error;

  always_comb begin
    dma_done_o  = dma_stats.done;
    dma_error_o = dma_stats.error;

    // Hook-up Desc. CSR and DMA logic
    for (int i=0; i<`DMA_NUM_DESC; i++) begin
      dma_desc[i].src_addr  = dma_csr_reg2hw.desc_src_addr[i];
      dma_desc[i].dst_addr  = dma_csr_reg2hw.desc_dst_addr[i];
      dma_desc[i].num_bytes = dma_csr_reg2hw.desc_num_bytes[i];
      dma_desc[i].wr_mode   = dma_mode_t'(dma_csr_reg2hw.desc_cfg[i].write_mode);
      dma_desc[i].rd_mode   = dma_mode_t'(dma_csr_reg2hw.desc_cfg[i].read_mode);
      dma_desc[i].enable    = dma_csr_reg2hw.desc_cfg[i].enable;
    end

    dma_csr_hw2reg.status.version     = '0;
    dma_csr_hw2reg.status.done        = dma_stats.done;
    dma_csr_hw2reg.status.error       = dma_stats.error;
    dma_csr_hw2reg.err_addr           = dma_error.addr;
    dma_csr_hw2reg.err_stats.err_type = dma_error.err_type;
    dma_csr_hw2reg.err_stats.err_src  = dma_error.src
    dma_csr_hw2reg.err_stats.err_trig = dma_stats.error     
  end

  /* verilator lint_off WIDTH */

  /*
   dma_reg_top AUTO_TEMPLATE (
   .apb_req_i    (dma_csr_req_i),
   .apb_rsp_o    (dma_csr_rsp_o),   
   .apb_pready_o (dma_csr_ready_o),
   .reg2hw       (dma_csr_reg2hw),
   .hw2reg       (dma_csr_hw2reg),   
   .intg_err_o   (),
   );
   */

  dma_reg_top 
  u_csr_dma(/*AUTOINST*/
	    // Interfaces
	    .apb_req_i			(dma_csr_req_i),	 // Templated
	    .apb_rsp_o			(dma_csr_rsp_o),	 // Templated
	    .reg2hw			(dma_csr_reg2hw),	 // Templated
	    .hw2reg			(dma_csr_hw2reg),	 // Templated
	    // Outputs
	    .apb_pready_o		(dma_csr_ready_o),	 // Templated
	    .intg_err_o			(),			 // Templated
	    // Inputs
	    .clk_i,
	    .rst_ni);

  /* verilator lint_on WIDTH */

  dma_func_wrapper #(
    .DMA_ID_VAL  (DMA_ID_VAL)
  ) u_dma_func_wrapper (
    .clk         (clk),
    .rst         (rst),
    // From/To CSRs
    .dma_ctrl_i  (dma_ctrl),
    .dma_desc_i  (dma_desc),
    .dma_stats_o (dma_stats),
    .dma_error_o (dma_error),
    // Master AXI I/F
    .dma_mosi_o  (dma_m_mosi_o),
    .dma_miso_i  (dma_m_miso_i)
  );
endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// verilog-typedef-regexp: "_t$"
// End:
