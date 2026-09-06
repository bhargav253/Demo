`ifndef BUS_INTF_PKG_SV
`define BUS_INTF_PKG_SV

package intf_pkg;

  //*******************************
  //  AXI - AXIv4
  //*******************************

  `ifndef AXI_ADDR_WIDTH
    `define AXI_ADDR_WIDTH        32
  `endif

  `ifndef AXI_DATA_WIDTH
    `define AXI_DATA_WIDTH        32
  `endif

  `ifndef AXI_ALEN_WIDTH
    `define AXI_ALEN_WIDTH        8
  `endif

  `ifndef AXI_ASIZE_WIDTH
    `define AXI_ASIZE_WIDTH       3
  `endif

  `ifndef AXI_MAX_OUTSTD_RD
    `define AXI_MAX_OUTSTD_RD     2
  `endif

  `ifndef AXI_MAX_OUTSTD_WR
    `define AXI_MAX_OUTSTD_WR     2
  `endif

  `ifndef AXI_USER_RESP_WIDTH
    `define AXI_USER_RESP_WIDTH   1
  `endif

  `ifndef AXI_TXN_ID_WIDTH
    `define AXI_TXN_ID_WIDTH      8
  `endif

  typedef logic [`AXI_ADDR_WIDTH-1:0]       axi_addr_t;
  typedef logic [`AXI_DATA_WIDTH-1:0]       axi_data_t;
  typedef logic [`AXI_ALEN_WIDTH-1:0]       axi_alen_t;
  typedef logic [(`AXI_DATA_WIDTH/8)-1:0]   axi_strb_t;
  typedef logic [`AXI_TXN_ID_WIDTH-1:0]     axi_tid_t;

  typedef enum logic [`AXI_ASIZE_WIDTH-1:0] {
    AXI_BYTE,
    AXI_HALF_WORD,
    AXI_WORD,
    AXI_DWORD,
    AXI_BYTES_16,
    AXI_BYTES_32,
    AXI_BYTES_64,
    AXI_BYTES_128
  } axi_size_t;

  typedef enum logic [1:0] {
    AXI_FIXED,
    AXI_INCR,
    AXI_WRAP,
    AXI_RESERVED
  } axi_burst_t;

  typedef logic [1:0] axi_resp_t;
  localparam axi_resp_t AxiOkay   = 2'b00;
  localparam axi_resp_t AxiExOkay = 2'b01;
  localparam axi_resp_t AxiSlaveError = 2'b10;
  localparam axi_resp_t AxiDecodeError = 2'b11;

  typedef struct packed {
    axi_tid_t   awid;
    axi_addr_t  awaddr;
    axi_alen_t  awlen;
    axi_size_t  awsize;
    axi_burst_t awburst;
  } axi_waddr_t;

  typedef struct packed {
    axi_tid_t   wid;
    axi_data_t  wdata;
    axi_strb_t  wstrb;
    logic       wlast;
  } axi_wdata_t;

  typedef struct packed {
    axi_tid_t   bid;
    axi_resp_t  bresp;
  } axi_bresp_t;

  typedef struct packed {
    axi_tid_t   arid;
    axi_addr_t  araddr;
    axi_alen_t  arlen;
    axi_size_t  arsize;
    axi_burst_t arburst;
  } axi_raddr_t;

  typedef struct packed {
    axi_tid_t   rid;
    axi_data_t  rdata;
    axi_resp_t  rresp;
    logic       rlast;
  } axi_rdata_t;

  //*******************************
  //  AXIL - AXIv4 Lite
  //*******************************

  typedef struct packed {
    axi_addr_t  awaddr;
  } axil_waddr_t;

  typedef struct packed {
    axi_data_t  wdata;
    axi_strb_t  wstrb;
  } axil_wdata_t;

  typedef struct packed {
    axi_resp_t  bresp;
  } axil_bresp_t;

  typedef struct packed {
    axi_addr_t  araddr;
  } axil_raddr_t;

  typedef struct packed {
    axi_data_t  rdata;
    axi_resp_t  rresp;
  } axil_rdata_t;


  //*******************************
  //  APB
  //*******************************

  `ifndef APB_ADDR_WIDTH
    `define APB_ADDR_WIDTH        16
  `endif

  typedef logic [`APB_ADDR_WIDTH-1:0]  apb_addr_t;
  typedef logic [`AXI_DATA_WIDTH-1:0]  apb_data_t;

  typedef struct packed {
    apb_addr_t  paddr;
    apb_data_t  pwdata;
    axi_strb_t  pstrb;
    logic       pwrite;
    logic       penable;
    logic       psel;
  } apb_req_t;

  typedef struct packed {
    apb_data_t  prdata;
    logic       pslverr;
  } apb_rsp_t;

  //*******************************
  //  custom intf
  //*******************************

  typedef struct packed {
   axi_addr_t addr;
   axi_data_t wdata;
   logic      ren;
   axi_strb_t wen;
   axi_tid_t  req_tag;
  } intf_req_t;

  typedef struct packed {
   logic      error;
   axi_data_t rdata;
   axi_tid_t  resp_tag;
  } intf_rsp_t;


endpackage : intf_pkg
`endif
