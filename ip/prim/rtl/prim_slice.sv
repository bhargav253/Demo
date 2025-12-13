module prim_slice
  #(
    parameter  WIDTH = 8
    )
   (/*AUTOARG*/
   // Outputs
   in_ready, out_data, out_vld,
   // Inputs
   clk, rst_n, in_data, in_vld, out_ready
   );

   input                    clk_i;
   input                    rst_ni;
   input [WIDTH-1:0]        i_data_i;
   input                    i_valid_i;
   output logic 	    i_ready_o;
   output logic [WIDTH-1:0] e_data_o;
   output logic             e_valid_o;
   input                    e_ready_i;   

   logic [1:0] 		    skid_val,nxt_skid_val,skid_clr,skid_set;
   logic [1:0][7:0] 	    skid_dat,nxt_skid_dat;
   logic 		    rx_pop,tx_pop;
   
   assign i_ready_o = ~(&skid_val);
   assign e_data_o  = skid_dat[0];
   assign e_valid_o = skid_val[0];
   
   assign rx_pop = i_valid_i  & i_ready_o;
   assign tx_pop = e_valid_o & e_ready_i;
   
   assign skid_set[0] = (rx_pop & ~skid_val[0]) | (rx_pop & tx_pop & ~skid_val[1]) | (tx_pop & skid_val[1]);
   assign skid_clr[0] = tx_pop;
   
   assign skid_set[1] = rx_pop & ~tx_pop & skid_val[0];
   assign skid_clr[1] = tx_pop & skid_val[1];
   
   always_comb begin
      nxt_skid_val= (skid_val & ~skid_clr) | skid_set;
      nxt_skid_dat = skid_dat;
      
      if(skid_set[0])
	nxt_skid_dat[0] = rx_pop & ~skid_val[0] | tx_pop & ~skid_val[1] ? i_data_i : skid_dat[1];
      
      if(skid_set[1])
	nxt_skid_dat[1] = i_data_i;
   end

   always @ (posedge clk_i) begin
      if(!rst_ni) begin
         skid_val <= '0;
         skid_dat <= '0;
      end
      else begin
         skid_val <= nxt_skid_val;
         skid_dat <= nxt_skid_dat;
      end
   end
   
endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
