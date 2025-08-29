/*
 using this FIFO for weights and inputs
 wr 4 elements per cycle
 rd 1 or 2 elements per cycle 
 */

module pe_in_fifo
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

   input 		     psh; // psh 4 elements
   input [3:0] [WIDTH-1:0]   din; 

   input [1:0] 		     pop; // either pop 1 or 2 elements
   output logic [1:0] [WIDTH-1:0] dout;
   output logic [1:0] 		  dout_val;   

   localparam CNTR = DEPTH * 4;   

   typedef logic [DEPTH-1:0] [3:0] [WIDTH-1:0] wr_fmt_t;
   typedef logic [(4*DEPTH)-1:0] [WIDTH-1:0]   rd_fmt_t;      
   
   wr_fmt_t                            fif_dat;
   rd_fmt_t                            fif_rdat;   
   logic [$clog2(CNTR):0] 	       fif_cnt;
   logic [$clog2(CNTR)-1:0] 	       fif_rptr;
   logic [$clog2(DEPTH)-1:0] 	       fif_wptr;      

   // on read side counting 1 element at a time
   always @(posedge clk)
     if(!rst_n) 
       fif_rptr <= '0;   
     else begin
	if(pop == 2'b10)
	  fif_rptr <= (fif_rptr == CNTR-1) ? 1 : (fif_rptr == CNTR-2) ? '0 : fif_rptr + 2; 
	else if(pop == 2'b01)
	  fif_rptr <= (fif_rptr == CNTR-1) ? '0 : fif_rptr + 1;
     end

   // on write side counting 4 elements at a time; becuase we always write 4 at a time
   always @(posedge clk)
     if(!rst_n)   fif_wptr <= '0;   
     else if(psh) fif_wptr <= (fif_wptr == DEPTH-1) ? '0 : fif_wptr + 1;

   
   always @(posedge clk)
     if(!rst_n)   fif_dat <= '0;   
     else if(psh) fif_dat[fif_wptr] <= din;   

   always @(posedge clk)
     if(!rst_n)          fif_cnt <= '0;   
     else if(psh & |pop) fif_cnt <= fif_cnt - pop + 4;
     else if(psh)        fif_cnt <= fif_cnt + 4;
     else if(|pop)       fif_cnt <= fif_cnt - pop;   

   
   // reformating data to readside
   assign fif_rdat = rd_fmt_t'(fif_dat);

   always_comb begin
      if(pop == 2'b10)      dout = (fif_rptr == CNTR-1) ? {fif_rdat[0],fif_rdat[fif_rptr]} : {fif_rdat[fif_rptr+1],fif_rdat[fif_rptr]};
      else if(pop == 2'b01) dout = {fif_rdat[fif_rptr],fif_rdat[fif_rptr]};
      else                  dout = 0;      
   end

   always_comb begin
      if(fif_cnt > 1)
	dout_val = 2'b10;
      else if(fif_cnt == 1)
	dout_val = 2'b01;
      else
	dout_val = 0;      
   end
   
endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
