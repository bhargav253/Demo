package soc_pkg;
   
   parameter ROC_START   = 32'h10000000;
   parameter ROC_STOP    = 32'h10000008;
   parameter ROM_START   = 32'h00000000;
   parameter ROM_STOP    = 32'h00000400;
   parameter RAM_START   = 32'h00000400;
   parameter RAM_STOP    = 32'h00001000;

   parameter NUM_ROC_DSTS = 3;
   
   parameter UART_START   = 32'h10000000;
   parameter UART_STOP    = 32'h10010000;

   parameter GPIO_START   = 32'h10010000;
   parameter GPIO_STOP    = 32'h10020000;

   parameter DMA_START    = 32'h10020000;
   parameter DMA_STOP     = 32'h10030000;
   
endpackage : soc_pkg
