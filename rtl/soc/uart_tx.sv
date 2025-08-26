// 
// Module: uart_tx 
// 
// Notes:
// - UART transmitter module.
//

module uart_tx
  #(parameter CLK_HZ       = 100000000,
    parameter BIT_RATE     = 115200,
    parameter PAYLOAD_BITS = 8)  
   (
    input wire 			  clk , 
    input wire 			  rst_n , 
    output wire 		  uart_txd ,
    output wire 		  uart_tx_done, 
    input wire 			  uart_tx_en ,
    input wire [PAYLOAD_BITS-1:0] uart_tx_data 
    );
   

   localparam  BIT_P           = 1_000_000_000 * 1/BIT_RATE;  // nanoseconds   
   localparam  CLK_P           = 1_000_000_000 * 1/CLK_HZ;    // nanoseconds
   parameter   STOP_BITS       = 1;
   //localparam  CYCLES_PER_BIT  = BIT_P / CLK_P;
   localparam  CYCLES_PER_BIT  = 8;
   localparam  COUNT_REG_LEN   = 1+$clog2(CYCLES_PER_BIT);
   
   reg 				  txd_reg;
   reg [PAYLOAD_BITS-1:0] 	  data_to_send;
   reg [COUNT_REG_LEN-1:0] 	  cycle_counter;
   reg [3:0] 			  bit_counter;
   
   typedef enum 		  logic [1:0] {
					       FSM_IDLE  = 2'd0,
					       FSM_START = 2'd1,
					       FSM_SEND  = 2'd2,
					       FSM_STOP  = 2'd3
					       } uart_fsm_t;

   uart_fsm_t 				     fsm_state,n_fsm_state;

   wire 			  next_bit     = cycle_counter == CYCLES_PER_BIT;
   wire 			  payload_done = bit_counter   == PAYLOAD_BITS  ;
   wire 			  stop_done    = bit_counter   == STOP_BITS && fsm_state == FSM_STOP;

   assign uart_tx_done = (fsm_state == FSM_STOP) && stop_done;
   assign uart_txd     = txd_reg;

   always @(*) begin : p_n_fsm_state
      case(fsm_state)
        FSM_IDLE : n_fsm_state = uart_tx_en   ? FSM_START: FSM_IDLE ;
        FSM_START: n_fsm_state = next_bit     ? FSM_SEND : FSM_START;
        FSM_SEND : n_fsm_state = payload_done ? FSM_STOP : FSM_SEND ;
        FSM_STOP : n_fsm_state = stop_done    ? FSM_IDLE : FSM_STOP ;
        default  : n_fsm_state = FSM_IDLE;
      endcase
   end

   always @(posedge clk) begin : p_data_to_send
      if(!rst_n) begin
         data_to_send <= {PAYLOAD_BITS{1'b0}};
      end else if(fsm_state == FSM_IDLE && uart_tx_en) begin
	 data_to_send <= uart_tx_data;
      end else if(fsm_state       == FSM_SEND       && next_bit ) begin
	 data_to_send <= {1'b0,data_to_send[PAYLOAD_BITS-1:1]};	    
      end
   end

   always @(posedge clk) begin : p_bit_counter
      if(!rst_n) begin
         bit_counter <= 4'b0;
      end else if(fsm_state != FSM_SEND && fsm_state != FSM_STOP) begin
         bit_counter <= {COUNT_REG_LEN{1'b0}};
      end else if(fsm_state == FSM_SEND && n_fsm_state == FSM_STOP) begin
         bit_counter <= {COUNT_REG_LEN{1'b0}};
      end else if(fsm_state == FSM_STOP&& next_bit) begin
	 bit_counter <= bit_counter + 1'b1;
      end else if(fsm_state == FSM_SEND && next_bit) begin
	 bit_counter <= bit_counter + 1'b1;
      end
   end

   always @(posedge clk) begin : p_cycle_counter
      if(!rst_n) begin
         cycle_counter <= {COUNT_REG_LEN{1'b0}};
      end else if(next_bit) begin
	 cycle_counter <= {COUNT_REG_LEN{1'b0}};
      end else if(fsm_state == FSM_START || 
                  fsm_state == FSM_SEND  || 
                  fsm_state == FSM_STOP   ) begin
         cycle_counter <= cycle_counter + 1'b1;
      end
   end

   always @(posedge clk) begin : p_fsm_state
      if(!rst_n) begin
         fsm_state <= FSM_IDLE;
      end else begin
         fsm_state <= n_fsm_state;
      end
   end

   always @(posedge clk) begin : p_txd_reg
      if(!rst_n) begin
         txd_reg <= 1'b1;
      end else if(fsm_state == FSM_IDLE) begin
         txd_reg <= 1'b1;
      end else if(fsm_state == FSM_START) begin
         txd_reg <= 1'b0;
      end else if(fsm_state == FSM_SEND) begin
         txd_reg <= data_to_send[0];
      end else if(fsm_state == FSM_STOP) begin
         txd_reg <= 1'b1;
      end
   end

endmodule
