`timescale 1ns/1ps

module systolic_tb;

   logic clk,rst_n,wen,ren;   
   logic in_val;   
   logic [3:0] 	a11;
   logic [3:0] 	a12;
   logic [3:0] 	a21;
   logic [3:0] 	a22;
   logic [3:0] 	b11;
   logic [3:0] 	b12;
   logic [3:0] 	b21;
   logic [3:0] 	b22;            
   logic 	out_val;   
   logic [8:0] 	c11;
   logic [8:0] 	c12;
   logic [8:0] 	c21;
   logic [8:0] 	c22;               

   logic [3:0] 	tb_a_q[$];
   logic [3:0] 	tb_b_q[$];
   logic [8:0] 	tb_c_q[$];   
   
   int 		abort_cnt;   
   bit [1:0] 	skip_cnt;   

   /*
    systolic AUTO_TEMPLATE (
    );
    */

   systolic DUT (/*AUTOINST*/
		 // Outputs
		 .out_val,
		 .c11			(c11[8:0]),
		 .c12			(c12[8:0]),
		 .c21			(c21[8:0]),
		 .c22			(c22[8:0]),
		 // Inputs
		 .clk,
		 .rst_n,
		 .in_val,
		 .a11			(a11[3:0]),
		 .a12			(a12[3:0]),
		 .a21			(a21[3:0]),
		 .a22			(a22[3:0]),
		 .b11			(b11[3:0]),
		 .b12			(b12[3:0]),
		 .b21			(b21[3:0]),
		 .b22			(b22[3:0]));
   
endmodule

//End of systolic_tb

// Local variables:
// verilog-library-directories:("../rtl/")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
