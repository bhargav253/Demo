/*
 wrapper with 4 processing elements in 2x2 config
 with skid fifos to control logic pushing and popping data 
 */

module pe
  #(parameter WIDTH=4)
   (/*AUTOARG*/
   // Outputs
   cout, cout_val,
   // Inputs
   clk, rst_n, ain, bin, psh, pop
   );
   
   input wire 		 clk;   
   input wire 		 rst_n;   

   input [3:0] [WIDTH-1:0] ain;
   input [3:0] [WIDTH-1:0] bin;
   input 		   psh;

   output [3:0] [(2*WIDTH):0] cout;
   output 		      cout_val;
   input 		      pop;   

   /*AUTOINPUT*/   
   
   /*AUTOLOGIC*/

   typedef enum logic [1:0] {
			     cyc_0 = 2'd0,
			     cyc_1 = 2'd1,
			     cyc_2 = 2'd2
			     } state_t;
   
   logic [WIDTH-1:0] 	E11_aout,E12_aout,E21_aout,E22_aout;
   logic [WIDTH-1:0] 	E11_bout,E12_bout,E21_bout,E22_bout;
   logic [(2*WIDTH):0] 	E11_cout,E12_cout,E21_cout,E22_cout;

   logic [WIDTH-1:0] 	E11_ain,E12_ain,E21_ain,E22_ain;
   logic [WIDTH-1:0] 	E11_bin,E12_bin,E21_bin,E22_bin;
   logic [(2*WIDTH):0] 	E11_cin,E12_cin,E21_cin,E22_cin;         

   logic 		E11_ain_slot,E12_ain_slot,E21_ain_slot,E22_ain_slot;
   logic 		E11_bin_slot,E12_bin_slot,E21_bin_slot,E22_bin_slot;   
   logic 		E11_aout_slot,E12_aout_slot,E21_aout_slot,E22_aout_slot;   
   logic 		E11_bout_slot,E12_bout_slot,E21_bout_slot,E22_bout_slot;

   logic 		E11_ain_val,E12_ain_val,E21_ain_val,E22_ain_val;
   logic 		E11_bin_val,E12_bin_val,E21_bin_val,E22_bin_val;
   logic 		E11_cin_val,E12_cin_val,E21_cin_val,E22_cin_val;      
   logic 		E11_aout_val,E12_aout_val,E21_aout_val,E22_aout_val;   
   logic 		E11_bout_val,E12_bout_val,E21_bout_val,E22_bout_val;  
   logic 		E11_cout_val,E12_cout_val,E21_cout_val,E22_cout_val;                
   
   logic [1:0] [WIDTH-1:0] a_fif,b_fif;
   logic [1:0] [2*WIDTH:0] c_fif_in;   

   logic [1:0] 		   a_fif_pop,b_fif_pop;
   logic [1:0] 		   c_fif_psh;
   logic [1:0] 		   b_fif_val;   

   state_t                 pe_state,nxt_pe_state;
   logic 		   curr_slot,nxt_slot;
   logic [1:0] 		   ele_slot,ele_val,ele_pop;
   logic [1:0] 		   ele_slot_d1,ele_val_d1,ele_pop_d1;   
   logic [1:0] 		   ele_slot_d2,ele_val_d2,ele_pop_d2;   

   logic [1:0] [WIDTH-1:0] ain_core,bin_core;
   logic [1:0] 		   ain_core_slot,bin_core_slot;
   logic [1:0] 		   ain_core_val,bin_core_val;      
   
   /*
    pe_in_fifo AUTO_TEMPLATE (
    .din      (bin),
    .pop      (b_fif_pop),
    .dout     (b_fif),
    .dout_val (b_fif_val),
    );
    */

   pe_in_fifo #(.WIDTH(WIDTH),.DEPTH(3)) 
   u_b_fif (/*AUTOINST*/
	    // Outputs
	    .dout			(b_fif),		 // Templated
	    .dout_val			(b_fif_val),		 // Templated
	    // Inputs
	    .clk,
	    .rst_n,
	    .psh,
	    .din			(bin),			 // Templated
	    .pop			(b_fif_pop));		 // Templated


   /*
    pe_in_fifo AUTO_TEMPLATE (
    .din      (ain),
    .pop      (a_fif_pop),
    .dout     (a_fif),
    .dout_val (),
    );
    */

   pe_in_fifo #(.WIDTH(WIDTH),.DEPTH(3)) 
   u_a_fif (/*AUTOINST*/
	    // Outputs
	    .dout			(a_fif),		 // Templated
	    .dout_val			(),			 // Templated
	    // Inputs
	    .clk,
	    .rst_n,
	    .psh,
	    .din			(ain),			 // Templated
	    .pop			(a_fif_pop));		 // Templated


   /*
    pe_out_fifo AUTO_TEMPLATE (
    .din      (c_fif_in),
    .psh      (c_fif_psh),
    .dout     (cout),
    .dout_val (cout_val),
    );
    */

   pe_out_fifo #(.WIDTH(2*WIDTH+1),.DEPTH(2)) 
   u_c_fif (/*AUTOINST*/
	    // Outputs
	    .dout			(cout),			 // Templated
	    .dout_val			(cout_val),		 // Templated
	    // Inputs
	    .clk,
	    .rst_n,
	    .psh			(c_fif_psh),		 // Templated
	    .din			(c_fif_in),		 // Templated
	    .pop);
     
   

   always_comb begin
      nxt_pe_state = pe_state;
      ele_pop      = '0;
      ele_slot     = '0;            
      ele_val      = '0;      
      nxt_slot     = curr_slot;      
      
      case(pe_state)
	cyc_0 : begin
	   if(|b_fif_val) begin
	      ele_pop      = 2'd1;
	      ele_slot     = {curr_slot,curr_slot};
	      ele_val      = 2'b10;	      
	      nxt_pe_state = cyc_1;
	   end
	end
	cyc_1 : begin
	   ele_pop      = 2'd2;
	   ele_slot     = {curr_slot,curr_slot};
	   ele_val      = 2'b11;
	   nxt_pe_state = cyc_2;
	end
	cyc_2 : begin
	   if(b_fif_val == 2'b10) begin
	      ele_pop      = 2'd2;
	      ele_slot     = {~curr_slot,curr_slot};
	      ele_val      = 2'b11;	      
	      nxt_slot     = ~curr_slot;
	      nxt_pe_state = cyc_1;	      
	   end
	   else begin
	      ele_pop      = 2'd1;
	      ele_slot     = {~curr_slot,curr_slot};
	      ele_val      = 2'b01;	
	      nxt_slot     = ~curr_slot;      	      
	      nxt_pe_state = cyc_0;
	   end
	end
      endcase
   end

   always @(posedge clk)
     if(!rst_n) begin	
	pe_state  <= cyc_0;
	curr_slot <= '0;	
     end
     else begin
	pe_state  <= nxt_pe_state;
	curr_slot <= nxt_slot;
     end
   
   
   always @(posedge clk)
     if(!rst_n) begin	
	ele_slot_d1 <= '0;
	ele_slot_d2 <= '0;

	ele_val_d1 <= '0;
	ele_val_d2 <= '0;

	ele_pop_d1 <= '0;
	ele_pop_d2 <= '0;	
     end
     else begin
	ele_slot_d1 <= ele_slot;
	ele_slot_d2 <= ele_slot_d1;
	
	ele_val_d1 <= ele_val;
	ele_val_d2 <= ele_val_d1;

	ele_pop_d1 <= ele_pop;
	ele_pop_d2 <= ele_pop_d1;	
     end
   
   assign b_fif_pop     = ele_pop;      
   assign bin_core      = b_fif;   
   assign bin_core_val  = ele_val;
   assign bin_core_slot = ele_slot;

   assign a_fif_pop     = ele_pop_d2;   
   assign ain_core      = a_fif;   
   assign ain_core_val  = {ele_val_d2};
   assign ain_core_slot = {ele_slot_d2};      

   always_comb
     case({E21_cout_val,E22_cout_val})
       2'b01   : begin c_fif_in = {{((2*WIDTH)+1){1'b0}},E22_cout}; c_fif_psh = 2'b01; end
       2'b10   : begin c_fif_in = {{((2*WIDTH)+1){1'b0}},E21_cout}; c_fif_psh = 2'b01; end
       2'b11   : begin c_fif_in = {E21_cout,E22_cout};	            c_fif_psh = 2'b10; end	
       default : begin c_fif_in = '0;                               c_fif_psh = '0;    end
     endcase   
   
   
   assign E11_ain      = ain_core[1];
   assign E11_ain_slot = ain_core_slot[1];
   assign E11_ain_val  = ain_core_val[1];
   assign E11_bin      = bin_core[1];
   assign E11_bin_slot = bin_core_slot[1];
   assign E11_bin_val  = bin_core_val[1];
   assign E11_cin      = '0;
   assign E11_cin_val  = '0;

   assign E12_ain      = E11_aout;
   assign E12_ain_slot = E11_aout_slot;   
   assign E12_ain_val  = E11_aout_val;   
   assign E12_bin      = bin_core[0];
   assign E12_bin_slot = bin_core_slot[0];
   assign E12_bin_val  = bin_core_val[0];
   assign E12_cin      = '0;
   assign E12_cin_val  = '0;   

   assign E21_ain      = ain_core[0];
   assign E21_ain_slot = ain_core_slot[0];   
   assign E21_ain_val  = ain_core_val[0];   
   assign E21_bin      = E11_bout;
   assign E21_bin_slot = E11_bout_slot;
   assign E21_bin_val  = E11_bout_val;
   assign E21_cin      = E11_cout;
   assign E21_cin_val  = E11_cout_val;   

   assign E22_ain      = E21_aout;
   assign E22_ain_slot = E21_aout_slot;   
   assign E22_ain_val  = E21_aout_val;   
   assign E22_bin      = E12_bout;
   assign E22_bin_slot = E12_bout_slot;
   assign E22_bin_val  = E12_bout_val;
   assign E22_cin      = E12_cout;
   assign E22_cin_val  = E12_cout_val;   
   
   
   /*
    pe_core AUTO_TEMPLATE "core_\(.*$\)" (
    .clk    (clk),
    .rst_n  (rst_n),    
    .\(.*\) (@_\1[]),
    );
    */

   pe_core u_pe_core_E11 ( /*AUTOINST*/
			  // Outputs
			  .cout			(E11_cout[(2*WIDTH):0]), // Templated
			  .cout_val		(E11_cout_val),	 // Templated
			  .aout			(E11_aout[WIDTH-1:0]), // Templated
			  .aout_slot		(E11_aout_slot), // Templated
			  .aout_val		(E11_aout_val),	 // Templated
			  .bout			(E11_bout[WIDTH-1:0]), // Templated
			  .bout_slot		(E11_bout_slot), // Templated
			  .bout_val		(E11_bout_val),	 // Templated
			  // Inputs
			  .clk,					 // Templated
			  .rst_n,				 // Templated
			  .ain			(E11_ain[WIDTH-1:0]), // Templated
			  .ain_slot		(E11_ain_slot),	 // Templated
			  .ain_val		(E11_ain_val),	 // Templated
			  .bin			(E11_bin[WIDTH-1:0]), // Templated
			  .bin_slot		(E11_bin_slot),	 // Templated
			  .bin_val		(E11_bin_val),	 // Templated
			  .cin			(E11_cin[(2*WIDTH):0]), // Templated
			  .cin_val		(E11_cin_val));	 // Templated
   
   pe_core u_pe_core_E12 ( /*AUTOINST*/
			  // Outputs
			  .cout			(E12_cout[(2*WIDTH):0]), // Templated
			  .cout_val		(E12_cout_val),	 // Templated
			  .aout			(E12_aout[WIDTH-1:0]), // Templated
			  .aout_slot		(E12_aout_slot), // Templated
			  .aout_val		(E12_aout_val),	 // Templated
			  .bout			(E12_bout[WIDTH-1:0]), // Templated
			  .bout_slot		(E12_bout_slot), // Templated
			  .bout_val		(E12_bout_val),	 // Templated
			  // Inputs
			  .clk,					 // Templated
			  .rst_n,				 // Templated
			  .ain			(E12_ain[WIDTH-1:0]), // Templated
			  .ain_slot		(E12_ain_slot),	 // Templated
			  .ain_val		(E12_ain_val),	 // Templated
			  .bin			(E12_bin[WIDTH-1:0]), // Templated
			  .bin_slot		(E12_bin_slot),	 // Templated
			  .bin_val		(E12_bin_val),	 // Templated
			  .cin			(E12_cin[(2*WIDTH):0]), // Templated
			  .cin_val		(E12_cin_val));	 // Templated

   pe_core u_pe_core_E21 ( /*AUTOINST*/
			  // Outputs
			  .cout			(E21_cout[(2*WIDTH):0]), // Templated
			  .cout_val		(E21_cout_val),	 // Templated
			  .aout			(E21_aout[WIDTH-1:0]), // Templated
			  .aout_slot		(E21_aout_slot), // Templated
			  .aout_val		(E21_aout_val),	 // Templated
			  .bout			(E21_bout[WIDTH-1:0]), // Templated
			  .bout_slot		(E21_bout_slot), // Templated
			  .bout_val		(E21_bout_val),	 // Templated
			  // Inputs
			  .clk,					 // Templated
			  .rst_n,				 // Templated
			  .ain			(E21_ain[WIDTH-1:0]), // Templated
			  .ain_slot		(E21_ain_slot),	 // Templated
			  .ain_val		(E21_ain_val),	 // Templated
			  .bin			(E21_bin[WIDTH-1:0]), // Templated
			  .bin_slot		(E21_bin_slot),	 // Templated
			  .bin_val		(E21_bin_val),	 // Templated
			  .cin			(E21_cin[(2*WIDTH):0]), // Templated
			  .cin_val		(E21_cin_val));	 // Templated
   
   pe_core u_pe_core_E22 ( /*AUTOINST*/
			  // Outputs
			  .cout			(E22_cout[(2*WIDTH):0]), // Templated
			  .cout_val		(E22_cout_val),	 // Templated
			  .aout			(E22_aout[WIDTH-1:0]), // Templated
			  .aout_slot		(E22_aout_slot), // Templated
			  .aout_val		(E22_aout_val),	 // Templated
			  .bout			(E22_bout[WIDTH-1:0]), // Templated
			  .bout_slot		(E22_bout_slot), // Templated
			  .bout_val		(E22_bout_val),	 // Templated
			  // Inputs
			  .clk,					 // Templated
			  .rst_n,				 // Templated
			  .ain			(E22_ain[WIDTH-1:0]), // Templated
			  .ain_slot		(E22_ain_slot),	 // Templated
			  .ain_val		(E22_ain_val),	 // Templated
			  .bin			(E22_bin[WIDTH-1:0]), // Templated
			  .bin_slot		(E22_bin_slot),	 // Templated
			  .bin_val		(E22_bin_val),	 // Templated
			  .cin			(E22_cin[(2*WIDTH):0]), // Templated
			  .cin_val		(E22_cin_val));	 // Templated
   
endmodule

// Local variables:
// verilog-library-directories:(".")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
