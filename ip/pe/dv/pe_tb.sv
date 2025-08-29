`ifndef PE_TB__SV
 `define PE_TB__SV

 `timescale 1ns/1ps

class bubble;
   rand bit [1:0] gap;
   constraint bubble_gap {gap dist { 0:=70, 1:=15, 2:=10, 3:= 5};}
endclass

module pe_tb;

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

   localparam BUBBLES    = 0;
   localparam DEBUG      = 0;   
   localparam MAX_CYCLES = 10000;   
   
   /*
    pe_top AUTO_TEMPLATE (
    );
    */

   pe_top DUT (/*AUTOINST*/
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

   initial begin
      clk = 0;
      forever begin
         #5 clk = ~clk;
      end
   end

   initial begin
      bubble bubb;      
      bubb     = new();      
      skip_cnt = 0;      
      
      load_ref();      

      abort_cnt = 0;
            
      rst_n  = '0;
      clean_inp();
      
      repeat(20) @(posedge clk);      
      rst_n = '1;      

      do begin
	 if(DEBUG) begin
	    $display("INFO curr AQ size : %d", tb_a_q.size());
	    $display("INFO curr CQ size : %d", tb_c_q.size());
	 end
	 @(posedge clk);            

	 if(skip_cnt == 0)
	   push_inp();
	 else
	   clean_inp();	 
	 
	 if(out_val) begin
	    check_dat();	 
	 end
	 abort_cnt += 1;
	 if(abort_cnt == MAX_CYCLES)
	   $finish;	 

	 if (skip_cnt != 0) begin
	    skip_cnt = skip_cnt - 1;
	    if(DEBUG)
	      $display("INFO decrementing to %d bubbles", skip_cnt);
	 end

	 // if BUBBLE parameter is enabled, 
	 // will insert random bubbles between inputs
	 if(BUBBLES & (skip_cnt == 0)) begin
	    bubb.randomize();
	    skip_cnt = bubb.gap;	    
	    if(DEBUG)
	      $display("INFO inserting %d bubbles", skip_cnt);	    
	 end
	 else
	   skip_cnt = '0;	   	 	 
	 
      end while(tb_a_q.size());      

      do begin
	 if(DEBUG)
	   $display("INFO curr CQ size : %d", tb_c_q.size());	 	 
	 @(posedge clk);
	 clean_inp();	 
	 if(out_val) begin
	    check_dat();	 
	 end
	 abort_cnt += 1;	 
	 if(abort_cnt == MAX_CYCLES)
	   $finish;	 
      end while (tb_c_q.size());     
           
      #1000 $finish;
   end

   task push_inp();
      in_val = '1;      
      a11    = tb_a_q.pop_back();
      a12    = tb_a_q.pop_back();
      a21    = tb_a_q.pop_back();
      a22    = tb_a_q.pop_back();
	     
      b11    = tb_b_q.pop_back();
      b12    = tb_b_q.pop_back();
      b21    = tb_b_q.pop_back();
      b22    = tb_b_q.pop_back();      
   endtask

   task clean_inp();
      in_val = '0;      
      a11    = '0;
      a12    = '0;
      a21    = '0;
      a22    = '0;
	     
      b11    = '0;
      b12    = '0;
      b21    = '0;
      b22    = '0;
   endtask
   
   task check_dat();
      logic [8:0] exp_c11,exp_c12,exp_c21,exp_c22;      
      
      exp_c11 = tb_c_q.pop_back();
      exp_c12 = tb_c_q.pop_back();
      exp_c21 = tb_c_q.pop_back();
      exp_c22 = tb_c_q.pop_back();      

      if(exp_c11 != c11)
	$display("ERR time : %0t act_val : %x --- exp_val : %x", $time, c11, exp_c11);
      else
	$display("INFO time : %0t act_val : %x --- exp_val : %x", $time, c11, exp_c11);	
      if(exp_c12 != c12)
	$display("ERR time : %0t act_val : %x --- exp_val : %x", $time, c12, exp_c12);
      else
	$display("INFO time : %0t act_val : %x --- exp_val : %x", $time, c12, exp_c12);	
      if(exp_c21 != c21)
	$display("ERR time : %0t act_val : %x --- exp_val : %x", $time, c21, exp_c21);
      else
	$display("INFO time : %0t act_val : %x --- exp_val : %x", $time, c21, exp_c21);	
      if(exp_c22 != c22)
	$display("ERR time : %0t act_val : %x --- exp_val : %x", $time, c22, exp_c22);
      else
	$display("INFO time : %0t act_val : %x --- exp_val : %x", $time, c22, exp_c22);	

   endtask
   

   task simple_load_ref();
      logic [8:0] temp;      
      for(int i=0;i<64;i++) begin
	 tb_a_q.push_front(i[3:0]);
	 tb_b_q.push_front(i[3:0]);	 
	 if(i[1:0] == 2'b11) begin
	    temp = (i[3:0]-3)*(i[3:0]-3) + (i[3:0]-2)*(i[3:0]-1);	    
	    tb_c_q.push_front(temp);
	    if(DEBUG)
	      $display("A11 : %x, B11 : %x, C11 : %x",(i[3:0]-3),(i[3:0]-3),temp);	    
	    temp = (i[3:0]-3)*(i[3:0]-2) + (i[3:0]-2)*(i[3:0]);
	    tb_c_q.push_front(temp);
	    if(DEBUG)
	      $display("A12 : %x, B12 : %x, C12 : %x",(i[3:0]-2),(i[3:0]-2),temp);	    
	    temp = (i[3:0]-1)*(i[3:0]-3) + (i[3:0])*(i[3:0]-1);
	    tb_c_q.push_front(temp);
	    if(DEBUG)
	      $display("A21 : %x, B21 : %x, C21 : %x",(i[3:0]-1),(i[3:0]-1),temp);
	    temp = (i[3:0]-1)*(i[3:0]-2) + (i[3:0])*(i[3:0]);
	    tb_c_q.push_front(temp);
	    if(DEBUG)
	      $display("A22 : %x, B22 : %x, C22 : %x",(i[3:0]),(i[3:0]),temp);	    
	 end
      end      
   endtask


   task load_ref();
      logic [8:0] c11,c12,c21,c22;
      logic [3:0] a11,a12,a21,a22,b11,b12,b21,b22;      
      for(int i=0;i<64;i++) begin
	 a11 = $urandom_range(0,15);
	 b11 = $urandom_range(0,15);
	 a12 = $urandom_range(0,15);
	 b12 = $urandom_range(0,15);	 
	 a21 = $urandom_range(0,15);
	 b21 = $urandom_range(0,15);	 
	 a22 = $urandom_range(0,15);
	 b22 = $urandom_range(0,15);	 	 

	 c11 = (a11 * b11) + (a12 * b21);
	 c12 = (a11 * b12) + (a12 * b22);
	 c21 = (a21 * b11) + (a22 * b21);
	 c22 = (a21 * b12) + (a22 * b22);	 
	 
	 tb_a_q.push_front(a11);
	 tb_a_q.push_front(a12);
	 tb_a_q.push_front(a21);
	 tb_a_q.push_front(a22);	 

	 tb_b_q.push_front(b11);
	 tb_b_q.push_front(b12);	 
	 tb_b_q.push_front(b21);	 
	 tb_b_q.push_front(b22);	 	 

	 tb_c_q.push_front(c11);
	 tb_c_q.push_front(c12);
	 tb_c_q.push_front(c21);
	 tb_c_q.push_front(c22);
      end      
   endtask
   
endmodule

`endif

//End of pe_tb

// Local variables:
// verilog-library-directories:("../rtl/")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
