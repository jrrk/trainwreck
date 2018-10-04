`timescale 1ns / 1ps

module fpga_top
(
  input wire clkin_200_p,
  input wire clkin_200_n,
  input wire resetin,

  input  wire RxD,
  output wire TxD,

  output wire lcd_db4,
  output wire lcd_db5,
  output wire lcd_db6,
  output wire lcd_db7,
  output wire lcd_rw,
  output wire lcd_rs,
  output wire lcd_e,

  output wire [7:0] led,

  output wire [7:0] PHY_TXD,
  output wire PHY_TXEN,
  output wire PHY_TXER,
  output wire PHY_GTXCLK,
  input  wire [7:0] PHY_RXD,
  input  wire PHY_RXDV,
  input  wire PHY_RXER,
  input  wire PHY_RXCLK,
  output wire PHY_RESET
);

  localparam CPU_CLK_MHZ = 25;

  wire clk_cpu, reset_cpu;
  wire clk_eth, reset_eth;
  wire clk_200, reset_200;
  wire clk_offchip; // clk_offchip is generated by the chip

  fpga_clocking #(.CLK_CPU_MHZ(CPU_CLK_MHZ)) clock_block
  (
    .clkin_200_p(clkin_200_p),
    .clkin_200_n(clkin_200_n),
    .resetin_p(resetin),

    .clk_cpu(clk_cpu),
    .reset_cpu(reset_cpu),

    .clk_eth(clk_eth),
    .reset_eth(reset_eth),

    .clk_200(clk_200),
    .reset_200(reset_200)
  );

  wire [63:0] rxq_bits;
  wire rxq_last_word;
  wire rxq_val;
  wire rxq_rdy;

  wire [63:0] txq_bits;
  wire [2:0] txq_byte_cnt;
  wire txq_last_word;
  wire txq_val;
  wire txq_rdy;

  wire htif_req_eth_val;
  wire [63:0] htif_req_eth_bits;

  wire htif_resp_eth_rdy;
  wire htif_resp_eth_val;
  wire [63:0] htif_resp_eth_bits;

  wire htif_req_chip_val;
  wire [3:0] htif_req_chip_bits;
  wire htif_req_chip_rdy;

  wire htif_resp_chip_rdy;
  wire [3:0] htif_resp_chip_bits;
  wire htif_resp_chip_val;

  wire error_eth;
  wire error_htif_onchip;
  wire error_core0;
  wire error_core1;
  wire blink_cpu;
  wire blink_offchip;
  wire blink_tx;
  wire blink_rx;

  wire console_val;
  wire console_rdy;
  wire [7:0] console_bits;

  wire rs232_tx_val;
  wire rs232_tx_rdy;
  wire [7:0] rs232_tx_bits;

  //wire rs232_rx_val;
  //wire rs232_rx_error;
  //wire [7:0] rs232_rx_bits;

  //wire lcd_rdy;
  //wire lcd_val;
  //wire [7:0] lcd_bits;

  wire rxclk;

  mac_gmii mac
  (
    .clk_eth(clk_eth),
    .reset_eth(reset_eth),

    .clk_cpu(clk_cpu),
    .reset_cpu(reset_cpu),

    .clk_200(clk_200),
    .reset_200(reset_200),

    .rxq_bits(rxq_bits),
    .rxq_last_word(rxq_last_word),
    .rxq_val(rxq_val),
    .rxq_rdy(rxq_rdy),

    .txq_bits(txq_bits),
    .txq_byte_cnt(txq_byte_cnt),
    .txq_last_word(txq_last_word),
    .txq_val(txq_val),
    .txq_rdy(txq_rdy),

    .rxclk(rxclk),

    .GMII_TXD(PHY_TXD),
    .GMII_TX_EN(PHY_TXEN),
    .GMII_TX_ER(PHY_TXER),
    .GMII_TX_CLK(PHY_GTXCLK),
    .GMII_RXD(PHY_RXD),
    .GMII_RX_DV(PHY_RXDV),
    .GMII_RX_ER(PHY_RXER),
    .GMII_RX_CLK(PHY_RXCLK),
    .GMII_RESET_B(PHY_RESET)              
  );

  HTIFEthernetAdapter htif_eth
  (
    .clk(clk_cpu),
    .reset(reset_cpu),

    .rxq_bits(rxq_bits),
    .rxq_last_word(rxq_last_word),
    .rxq_val(rxq_val),
    .rxq_rdy(rxq_rdy),

    .txq_bits(txq_bits),
    .txq_byte_cnt(txq_byte_cnt),
    .txq_last_word(txq_last_word),
    .txq_val(txq_val),
    .txq_rdy(txq_rdy),

    .htif_req_val(htif_req_eth_val),
    .htif_req_bits(htif_req_eth_bits),

    .htif_resp_rdy(htif_resp_eth_rdy),
    .htif_resp_val(htif_resp_eth_val),
    .htif_resp_bits(htif_resp_eth_bits)
  );

  //`include "macros.vh"
  //`include "riscvConst.vh"

  //`VC_SIMPLE_QUEUE(64, 16) loopback_eth
  //(
  //  .clk(clk_cpu),
  //  .reset(reset_cpu),
  //  .enq_bits(htif_req_eth_bits),
  //  .enq_val(htif_req_eth_val),
  //  .enq_rdy(),
  //  .deq_bits(htif_resp_eth_bits),
  //  .deq_val(htif_resp_eth_val),
  //  .deq_rdy(htif_resp_eth_rdy)
  //);

  offchip_phy phy
  (
    .clk_cpu(clk_cpu),
    .reset_cpu(reset_cpu),

    .clk_200(clk_200),
    .reset_200(reset_200),

    .clk_offchip(clk_offchip),
    .reset_offchip(reset_offchip),

    .htif_req_eth_val(htif_req_eth_val),
    .htif_req_eth_bits(htif_req_eth_bits),

    .htif_resp_eth_val(htif_resp_eth_val),
    .htif_resp_eth_bits(htif_resp_eth_bits),
    .htif_resp_eth_rdy(htif_resp_eth_rdy),

    .htif_req_chip_val(htif_req_chip_val),
    .htif_req_chip_bits(htif_req_chip_bits),
    .htif_req_chip_rdy(htif_req_chip_rdy),

    .htif_resp_chip_val(htif_resp_chip_val),
    .htif_resp_chip_bits(htif_resp_chip_bits)
  );

  riscvTop top
  (
    .clk(clk_cpu),
      
    .console_out_val(console_val),
    .console_out_rdy(console_rdy),
    .console_out_bits(console_bits),

    .htif_reset(reset_offchip),

    .htif_in_val(htif_req_chip_val),
    .htif_in_bits(htif_req_chip_bits),
    .htif_in_rdy(htif_req_chip_rdy),  

    .htif_out_clk(clk_offchip),
    .htif_out_val(htif_resp_chip_val),
    .htif_out_bits(htif_resp_chip_bits),
    
    .error_core0(error_core0),
    .error_core1(error_core1),
    .error_htif(error_htif_onchip)
  );
 
  //assign console_rdy = 1'b1;
  ////assign console_rdy = lcd_rdy;
  ////assign lcd_val = console_val;
  ////assign lcd_bits = console_bits;

  `include "macros.vh"
  `include "riscvConst.vh"

  `VC_SIMPLE_QUEUE(8, 64) rxq
  (
    .clk(clk_offchip),
    .reset(reset_offchip),
    .enq_bits(htif_resp_chip_bits < 4'd10 ? htif_resp_chip_bits + 8'd48 : htif_resp_chip_bits + 8'd55),
    .enq_val(htif_resp_chip_val),
    .enq_rdy(),
    .deq_bits(rs232_tx_bits),
    .deq_val(rs232_tx_val),
    .deq_rdy(rs232_tx_rdy)
  );

  rs232_tx_ctrl #(.CLOCKS_PER_BAUD(CPU_CLK_MHZ * 1000000 / 9600 / 64)) rs232_out
  (
    .clk(clk_offchip),
    .reset(reset_offchip),

    .rdy(rs232_tx_rdy),
    .val(rs232_tx_val),
    .bits(rs232_tx_bits),

    .TxD(TxD)
  );

  ////rs232_rx_ctrl #(.NOISY(0)) rs232_in
  ////(
  ////  .clk(clk_cpu),
  ////  .rst(reset_cpu),

  ////  .val(rs232_rx_val),
  ////  .bits(rs232_rx_bits),
  ////  .error(rs232_rx_error),

  ////  .RxD()
  ////);

  ////lcd_ctrl lcd_out
  ////(
  ////  .clk(clk_cpu),
  ////  .rst(reset_cpu),

  ////  .rdy(lcd_rdy),
  ////  .val(lcd_val),
  ////  .bits(lcd_bits),

  ////  .lcd_pins({{lcd_db7,lcd_db6,lcd_db5,lcd_db4},lcd_rw,lcd_rs,lcd_e})
  ////);

  blink #(24) blinker_cpu
  (
    .clk(clk_cpu),
    .reset(reset_cpu),
    .blink(blink_cpu)
  );
           
  blink #(24-6) blinker_offchip
  (
    .clk(clk_offchip),
    .reset(reset_offchip),
    .blink(blink_offchip)
  );
           
  blink #(24) blinker_tx
  (
    .clk(clk_eth),
    .reset(reset_eth),
    .blink(blink_tx)
  );

  blink #(24) blinker_rx
  (
    .clk(rxclk),
    .reset(resetin),
    .blink(blink_rx)
  );
           
  // synthesis translate_off
  always @(posedge clk_cpu)
  begin
    if (error_eth)
    begin
      $display("***** ENTERED ETH ERROR MODE *****");
      $finish(1);
    end
    if (error_htif_onchip)
    begin
      $display("***** ENTERED HTIF ONCHIP ERROR MODE *****");
      $finish(1);
    end
    if (error_core0)
    begin
      $display("***** ENTERED CORE0 ERROR MODE *****");
      $finish(1);
    end
    if (error_core1)
    begin
      $display("***** ENTERED CORE1 ERROR MODE *****");
      $finish(1);
    end
  end
  // synthesis translate_on
 
  assign led[7:0] = {error_eth, error_htif_onchip, error_core0, error_core1, blink_rx, blink_tx, blink_offchip, blink_cpu};
   
endmodule
