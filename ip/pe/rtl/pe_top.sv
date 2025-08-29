/*
 contains two PE_wrappers to allow full throughput
 */

module pe_top
   (/*AUTOARG*/
   // Outputs
   out_val, c11, c12, c21, c22,
   // Inputs
   clk, rst_n, in_val, a11, a12, a21, a22, b11, b12, b21, b22
   );
   
   input wire 			  clk;   
   input wire 			  rst_n;   

   input 			  in_val;

   input [3:0] 			  a11;
   input [3:0] 			  a12;
   input [3:0] 			  a21;
   input [3:0] 			  a22;

   input [3:0] 			  b11;
   input [3:0] 			  b12;
   input [3:0] 			  b21;
   input [3:0] 			  b22;            

   output 			  out_val;   
   output [8:0] 		  c11;
   output [8:0] 		  c12;
   output [8:0] 		  c21;
   output [8:0] 		  c22;               

   localparam WIDTH = 4;   

   logic [1:0] [3:0] [(2*WIDTH):0] cout;
   logic [1:0] 			   cout_val;   
   logic [1:0] [3:0] [WIDTH-1:0]   ain,bin;
   logic [1:0]  		   psh,pop;            
   logic 			   psh_fif,pop_fif;   
   
   always @(posedge clk)
     if(!rst_n) psh_fif <= '0;
     else       psh_fif <= in_val ? ~psh_fif : psh_fif;

   assign psh[0] = (psh_fif == 0) & in_val;   
   assign ain[0] = {a22,
		    a21,
		    a12,
		    a11};
   assign bin[0] = {b12,
		    b11,
		    b22,
		    b21};
   
   assign psh[1] = (psh_fif == 1) & in_val;
   assign ain[1] = {a22,
		    a21,
		    a12,
		    a11};   
   assign bin[1] = {b12,
		    b11,
		    b22,
		    b21};   
   
   assign out_val = cout_val[pop_fif];   
   always @(posedge clk)
     if(!rst_n) pop_fif <= '1;
     else       pop_fif <= out_val ? ~pop_fif : pop_fif;   

   assign c11 = cout[pop_fif][0];
   assign c12 = cout[pop_fif][1];
   assign c21 = cout[pop_fif][2];
   assign c22 = cout[pop_fif][3];   

   assign pop[0] = (pop_fif == 0) & cout_val[0];
   assign pop[1] = (pop_fif == 1) & cout_val[1];   

   /*
    pe AUTO_TEMPLATE (
    .clk    (clk),
    .rst_n  (rst_n),
    .\(.*\) (\1[@]),
    );
    */

   pe #(.WIDTH(WIDTH))
   u_proc0 (/*AUTOINST*/
	    // Outputs
	    .cout			(cout[0]),		 // Templated
	    .cout_val			(cout_val[0]),		 // Templated
	    // Inputs
	    .clk,						 // Templated
	    .rst_n,						 // Templated
	    .ain			(ain[0]),		 // Templated
	    .bin			(bin[0]),		 // Templated
	    .psh			(psh[0]),		 // Templated
	    .pop			(pop[0]));		 // Templated

   pe #(.WIDTH(WIDTH))
   u_proc1 (/*AUTOINST*/
	    // Outputs
	    .cout			(cout[1]),		 // Templated
	    .cout_val			(cout_val[1]),		 // Templated
	    // Inputs
	    .clk,						 // Templated
	    .rst_n,						 // Templated
	    .ain			(ain[1]),		 // Templated
	    .bin			(bin[1]),		 // Templated
	    .psh			(psh[1]),		 // Templated
	    .pop			(pop[1]));		 // Templated
   
   

   
endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
