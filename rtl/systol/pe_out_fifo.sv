/*
 using this FIFO for outputs
 wr 1 or 2 elements per cycle
 rd 4 elements per cycle
 */

module pe_out_fifo
  #(parameter WIDTH=4,
    parameter DEPTH=2)
   (/*AUTOARG*/
   // Outputs
   dout, dout_val,
   // Inputs
   clk, rst_n, psh, din, pop
   );
   
   input wire 		     clk;
   input wire 		     rst_n;

   input [1:0] 		     psh; // psh 1 or 2 elements
   input [1:0] [WIDTH-1:0]   din; 

   input 		     pop; // either pop 4 elements
   output logic [3:0] [WIDTH-1:0] dout;
   output logic 		  dout_val;   
   

   localparam CNTR = DEPTH * 4;   

   typedef logic [DEPTH-1:0] [3:0] [WIDTH-1:0] rd_fmt_t;
   typedef logic [(4*DEPTH)-1:0] [WIDTH-1:0]   wr_fmt_t;      
   
   rd_fmt_t                            fif_rdat;
   wr_fmt_t                            fif_dat;   
   logic [$clog2(CNTR):0] 	       fif_cnt;
   logic [$clog2(DEPTH)-1:0] 	       fif_rptr;
   logic [$clog2(CNTR)-1:0] 	       fif_wptr;      

   // on write side counting 1 element at a time
   always @(posedge clk)
     if(!rst_n) 
       fif_wptr <= '0;   
     else begin
	if(psh == 2'b10)
	  fif_wptr <= (fif_wptr == CNTR-1) ? 1 : (fif_wptr == CNTR-2) ? '0 : fif_wptr + 2; 
	else if(psh == 2'b01)
	  fif_wptr <= (fif_wptr == CNTR-1) ? '0 : fif_wptr + 1;
     end

   // on read side counting 4 elements at a time; becuase we always write 4 at a time
   always @(posedge clk)
     if(!rst_n)   fif_rptr <= '0;   
     else if(pop) fif_rptr <= (fif_rptr == DEPTH-1) ? '0 : fif_rptr + 1;

   
   always @(posedge clk)
     if(!rst_n)   
       fif_dat <= '0;   
     else begin
	if(psh == 2'b10) begin
	   fif_dat[fif_wptr] <= din[0];
	   if(fif_wptr == CNTR-1)
	     fif_dat[0] <= din[1];	   
	   else	     
	     fif_dat[fif_wptr+1] <= din[1];	   
	end
	else if(psh == 2'b01)
	  fif_dat[fif_wptr] <= din[0];	  
     end
   
   always @(posedge clk)
     if(!rst_n)          fif_cnt <= '0;   
     else if(|psh & pop) fif_cnt <= fif_cnt + psh - 4;
     else if(|psh)       fif_cnt <= fif_cnt + psh;
     else if(pop)        fif_cnt <= fif_cnt - 4;   

   // reformating data to readside
   assign fif_rdat = rd_fmt_t'(fif_dat);
   
   assign dout     = fif_rdat[fif_rptr];
   assign dout_val = ((fif_cnt >> 2) != 0);   
   
endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
