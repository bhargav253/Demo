module roc
  import soc_pkg::*;
   (
    input 	  clk, 
    input 	  rst_n,

    output 	  roc__axi_arready,
    input [31:0]  roc__axi_araddr,
    input 	  roc__axi_arvalid,
   
    output 	  roc__axi_awready,
    input [31:0]  roc__axi_awaddr, 
    input 	  roc__axi_awvalid,

    output 	  roc__axi_wready,
    input 	  roc__axi_wvalid,
    input [31:0]  roc__axi_wdata, 
    input [3:0]   roc__axi_wstrb,
   
    output 	  roc__axi_bvalid,
    output [1:0]  roc__axi_bresp,
    input 	  roc__axi_bready,
   
    output [31:0] roc__axi_rdata,
    output [1:0]  roc__axi_rresp, 
    output 	  roc__axi_rvalid, 
    input 	  roc__axi_rready,

    input 	  UART_RXD,
    output 	  UART_TXD,    
    output [3:0]  GPIO_OUT
    );      
   

   logic [NUM_ROC_DSTS:0] roc_decode;
   
   /*AUTOLOGIC*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   logic [ADDR_WIDTH-1:0] apb_paddr;		// From u_roc_bus of axil2apb.v
   logic		apb_penable;		// From u_roc_bus of axil2apb.v
   logic		apb_psel;		// From u_roc_bus of axil2apb.v
   logic [STRB_WIDTH-1:0] apb_pstrb;		// From u_roc_bus of axil2apb.v
   logic [DATA_WIDTH-1:0] apb_pwdata;		// From u_roc_bus of axil2apb.v
   logic		apb_pwrite;		// From u_roc_bus of axil2apb.v
   logic		axi_arready;		// From u_roc_bus of axil2apb.v
   logic		axi_awready;		// From u_roc_bus of axil2apb.v
   logic [1:0]		axi_bresp;		// From u_roc_bus of axil2apb.v
   logic		axi_bvalid;		// From u_roc_bus of axil2apb.v
   logic [DATA_WIDTH-1:0] axi_rdata;		// From u_roc_bus of axil2apb.v
   logic [1:0]		axi_rresp;		// From u_roc_bus of axil2apb.v
   logic		axi_rvalid;		// From u_roc_bus of axil2apb.v
   logic		axi_wready;		// From u_roc_bus of axil2apb.v
   logic		dma__apb_psel;		// From u_roc_split of apb_split.v
   logic		gpio__apb_psel;		// From u_roc_split of apb_split.v
   logic		roc__apb_prdata;	// From u_roc_split of apb_split.v
   logic		roc__apb_pready;	// From u_roc_split of apb_split.v
   logic		roc__apb_pslverr;	// From u_roc_split of apb_split.v
   logic		uart__apb_psel;		// From u_roc_split of apb_split.v
   // End of automatics

   
   /*
    axi2apb AUTO_TEMPLATE (
    .axi_\(.*\)    (roc__axi_\1),
    .apb_\(.*\)    (roc__apb_\1),    
    );
    */
   
   axil2apb
   u_roc_bus (/*AUTOINST*/
	      // Outputs
	      .axi_awready,
	      .axi_wready,
	      .axi_bresp		(axi_bresp[1:0]),
	      .axi_bvalid,
	      .axi_arready,
	      .axi_rdata		(axi_rdata[DATA_WIDTH-1:0]),
	      .axi_rresp		(axi_rresp[1:0]),
	      .axi_rvalid,
	      .apb_psel,
	      .apb_penable,
	      .apb_paddr		(apb_paddr[ADDR_WIDTH-1:0]),
	      .apb_pwrite,
	      .apb_pwdata		(apb_pwdata[DATA_WIDTH-1:0]),
	      .apb_pstrb		(apb_pstrb[STRB_WIDTH-1:0]),
	      // Inputs
	      .clk,
	      .rst_n,
	      .axi_awaddr		(axi_awaddr[ADDR_WIDTH-1:0]),
	      .axi_awvalid,
	      .axi_wdata		(axi_wdata[DATA_WIDTH-1:0]),
	      .axi_wstrb		(axi_wstrb[STRB_WIDTH-1:0]),
	      .axi_wvalid,
	      .axi_bready,
	      .axi_araddr		(axi_araddr[ADDR_WIDTH-1:0]),
	      .axi_arvalid,
	      .axi_rready,
	      .apb_prdata		(apb_prdata[DATA_WIDTH-1:0]),
	      .apb_pready,
	      .apb_pslverr);


   /*
    apb_split AUTO_TEMPLATE (
    .src_apb_\(.*\)    (roc__apb_\1),
    .dst_apb_\(.*\)    ({gpio__apb_\1,uart__apb_\1,dma__apb_\1}),
    .decode            ({gpio__decode,uart__decode,dma__decode}),
    );
    */
   
   apb_split
   u_roc_split #(.NUM_DSTS(NUM_ROC_DSTS)
               )(/*AUTOINST*/
		 // Outputs
		 .src_apb_prdata	(roc__apb_prdata),	 // Templated
		 .src_apb_pready	(roc__apb_pready),	 // Templated
		 .src_apb_pslverr	(roc__apb_pslverr),	 // Templated
		 .dst_apb_psel		({gpio__apb_psel,uart__apb_psel,dma__apb_psel}), // Templated
		 // Inputs
		 .clk,
		 .rst_n,
		 .src_apb_paddr		(roc__apb_paddr),	 // Templated
		 .src_apb_pwdata	(roc__apb_pwdata),	 // Templated
		 .src_apb_pwrite	(roc__apb_pwrite),	 // Templated
		 .src_apb_penable	(roc__apb_penable),	 // Templated
		 .src_apb_psel		(roc__apb_psel),	 // Templated
		 .decode		({gpio__decode,uart__decode,dma__decode}), // Templated
		 .dst_apb_prdata	({gpio__apb_prdata,uart__apb_prdata,dma__apb_prdata}), // Templated
		 .dst_apb_pready	({gpio__apb_pready,uart__apb_pready,dma__apb_pready}), // Templated
		 .dst_apb_pslverr	({gpio__apb_pslverr,uart__apb_pslverr,dma__apb_pslverr})); // Templated
            

   assign roc_decode[2] = ~(roc_decode[1] | roc_decode[2]);
   assign roc_decode[1] = (roc__apb_addr >= GPIO_START)  && (roc__apb_addr < GPIO_STOP);   
   assign roc_decode[0] = (roc__apb_addr >= UART_START)  && (roc__apb_addr < UART_STOP);
   
   
   //-------------------------------------------------------------
   // DMA
   //-------------------------------------------------------------         

   
   //-------------------------------------------------------------
   // UART
   //-------------------------------------------------------------         
   

   //-------------------------------------------------------------
   // GPIO OUT
   //-------------------------------------------------------------         
   

   
endmodule

// Local variables:
// verilog-library-directories:("." "../../bus/rtl/.")
// verilog-auto-sense-defines-constant:t
// verilog-auto-inst-vector:t
// verilog-auto-inst-dot-name:t
// End:
