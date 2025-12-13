/*
 
*/

module dma_fsm
  import amba_axi_pkg::*;
  import dma_utils_pkg::*;
(/*AUTOARG*/
   // Outputs
   dma_stats_o, dma_error_o, clear_dma_o, dma_active_o,
   dma_stream_rd_o, dma_stream_wr_o,
   // Inputs
   clk_i, rst_ni, dma_ctrl_i, dma_desc_i, axi_pend_txn_i,
   axi_txn_err_i, dma_stream_rd_i, dma_stream_wr_i
   );


  input                                   clk_i;
  input                                   rst_ni;
  // From/To CSRs
  input   dma_control_t                   dma_ctrl_i;
  input   dma_desc_t [`DMA_NUM_DESC-1:0]  dma_desc_i;
  output  dma_status_t                    dma_stats_o;
  // From/To AXI I/F
  input                                   axi_pend_txn_i;
  input   dma_error_t                     axi_txn_err_i;
  output  dma_error_t                     dma_error_o;
  output  logic                           clear_dma_o;
  output  logic                           dma_active_o;
  // To/From streamers
  output  dma_str_in_t                    dma_stream_rd_o;
  input   dma_str_out_t                   dma_stream_rd_i;
  output  dma_str_in_t                    dma_stream_wr_o;
  input  dma_str_out_t                    dma_stream_wr_i;
   

  dma_st_t cur_st_ff, next_st;
  logic [`DMA_NUM_DESC-1:0] rd_desc_done_ff, next_rd_desc_done;
  logic [`DMA_NUM_DESC-1:0] wr_desc_done_ff, next_wr_desc_done;

  logic pending_desc; // Gets set when there are pending descriptors to process
  logic pending_rd_desc, pending_wr_desc;
  logic abort_ff;

  function automatic logic check_cfg();
    logic [`DMA_NUM_DESC-1:0] valid_desc;

    valid_desc = '0;

    for (int i=0; i<`DMA_NUM_DESC; i++) begin
      if (dma_desc_i[i].enable) begin
        valid_desc[i] = (|dma_desc_i[i].num_bytes);
      end
    end
    return |valid_desc;
  endfunction

  always_comb begin : fsm_dma_ctrl
    next_st = DMA_ST_IDLE;
    pending_desc = pending_rd_desc || pending_wr_desc;

    case (cur_st_ff)
      DMA_ST_IDLE: begin
        if (dma_ctrl_i.go) begin
          next_st = DMA_ST_CFG;
        end
      end
      DMA_ST_CFG: begin
        if (~dma_ctrl_i.abort && check_cfg()) begin
          next_st = DMA_ST_RUN;
        end
        else begin
          next_st = DMA_ST_DONE;
        end
      end
      DMA_ST_RUN: begin
        if (pending_desc || axi_pend_txn_i) begin
          next_st = DMA_ST_RUN;
        end
        else begin
          next_st = DMA_ST_DONE;
        end
      end
      DMA_ST_DONE: begin
        if (dma_ctrl_i.go) begin
          next_st = DMA_ST_DONE;
        end
      end
    endcase
  end : fsm_dma_ctrl

  /* verilator lint_off WIDTH */
  always_comb begin : rd_streamer
    dma_stream_rd_o   = dma_str_in_t'('0);
    next_rd_desc_done = rd_desc_done_ff;
    pending_rd_desc   = 1'b0;
    dma_active_o      = (cur_st_ff == DMA_ST_RUN);

    if (cur_st_ff == DMA_ST_RUN) begin
      for (int i=0; i<`DMA_NUM_DESC; i++) begin
        if (dma_desc_i[i].enable && (|dma_desc_i[i].num_bytes) && (~rd_desc_done_ff[i])) begin
          dma_stream_rd_o.idx   = i;
          dma_stream_rd_o.valid = ~abort_ff;
          break;
        end
      end

      if (dma_stream_rd_i.done) begin
        next_rd_desc_done[dma_stream_rd_o.idx] = 1'b1;
      end

      pending_rd_desc = dma_stream_rd_o.valid;
    end

    if (cur_st_ff == DMA_ST_DONE) begin
      next_rd_desc_done = '0;
    end
  end : rd_streamer

  always_comb begin : wr_streamer
    dma_stream_wr_o   = dma_str_in_t'('0);
    next_wr_desc_done = wr_desc_done_ff;
    pending_wr_desc   = 1'b0;

    if (cur_st_ff == DMA_ST_RUN) begin
      for (int i=0; i<`DMA_NUM_DESC; i++) begin
        if (dma_desc_i[i].enable && (|dma_desc_i[i].num_bytes) && (~wr_desc_done_ff[i])) begin
          dma_stream_wr_o.idx   = i;
          dma_stream_wr_o.valid = ~abort_ff;
          break;
        end
      end

      if (dma_stream_wr_i.done) begin
        next_wr_desc_done[dma_stream_wr_o.idx] = 1'b1;
      end

      pending_wr_desc = dma_stream_wr_o.valid;
    end

    if (cur_st_ff == DMA_ST_DONE) begin
      next_wr_desc_done = '0;
    end
  end : wr_streamer
  /* verilator lint_on WIDTH */

  always_comb begin : dma_status
    dma_error_o = dma_error_t'('0);

    if (axi_txn_err_i.valid) begin
      dma_error_o.addr     = axi_txn_err_i.addr;
      dma_error_o.err_type = DMA_ERR_OPE;
      dma_error_o.src      = axi_txn_err_i.src;
      dma_error_o.valid    = 1'b1;
    end
    dma_stats_o.error = axi_txn_err_i.valid;
    dma_stats_o.done  = (cur_st_ff == DMA_ST_DONE);
    clear_dma_o       = (cur_st_ff == DMA_ST_DONE) && (next_st == DMA_ST_IDLE);
  end : dma_status

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cur_st_ff       <= dma_st_t'('0);
      rd_desc_done_ff <= '0;
      wr_desc_done_ff <= '0;
      abort_ff        <= '0;
    end
    else begin
      cur_st_ff       <= next_st;
      rd_desc_done_ff <= next_rd_desc_done;
      wr_desc_done_ff <= next_wr_desc_done;
      abort_ff        <= dma_ctrl_i.abort;
    end
  end
endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// verilog-typedef-regexp: "_t$"
// End:
