/*
 Processing element of systolic array with 
 double buffered weights
 */


module pe_core
  #(parameter WIDTH=4)
   (/*AUTOARG*/
   // Outputs
   cout, cout_val, aout, aout_slot, aout_val, bout, bout_slot,
   bout_val,
   // Inputs
   clk, rst_n, ain, ain_slot, ain_val, bin, bin_slot, bin_val, cin,
   cin_val
   );
   
   input wire 		 clk;
   input wire 		 rst_n;

   output logic [(2*WIDTH):0] cout;
   output logic 	      cout_val;   
   
   output logic [WIDTH-1:0]   aout;
   output logic 	      aout_slot;
   output logic 	      aout_val;   

   output logic [WIDTH-1:0]   bout;
   output logic 	      bout_slot;
   output logic 	      bout_val; 
   
   input [WIDTH-1:0] 	      ain;
   input 		      ain_slot;
   input 		      ain_val;
   
   input [WIDTH-1:0] 	      bin;
   input 		      bin_slot;
   input 		      bin_val;      
   
   input [(2*WIDTH):0] 	      cin;
   input 		      cin_val;   
   
  
   logic [1:0] [WIDTH-1:0] b_reg;   
   logic [(2*WIDTH-1):0]   prod;
   
   assign prod = ain * b_reg[ain_slot];   

   always @(posedge clk)
     if(!rst_n) begin
	aout       <= '0;
	aout_slot  <= '0;	
	aout_val   <= '0;
     end
     else begin
	aout       <= ain;
	aout_slot  <= ain_slot;	
	aout_val   <= ain_val;
     end

   always @(posedge clk)
     if(!rst_n)       b_reg           <= '0;
     else if(bin_val) b_reg[bin_slot] <= bin;

   always @(posedge clk)
     if(!rst_n) begin
	bout      <= '0;
	bout_slot <= '0;
	bout_val  <= '0;	
     end
     else begin
	bout      <= b_reg[bin_slot];
	bout_slot <= bin_slot;
	bout_val  <= bin_val;	
     end

   always @(posedge clk)
     if(!rst_n) begin
	cout     <= '0;
	cout_val <= '0;	
     end
     else begin
	cout     <= cin_val ? (cin + prod) : prod;
	cout_val <= ain_val;	
     end

endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
