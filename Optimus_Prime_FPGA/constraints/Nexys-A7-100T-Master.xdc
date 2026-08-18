##==============================================================================
## buttons_keypad_bringup_top.xdc
##
## Active top-level ports used by this design:
##   clk100mhz
##   resetn
##   BTNC, BTNU, BTND, BTNL, BTNR
##   kp_row[3:0]
##   kp_col[3:0]
##   led[15:0]
##==============================================================================
## Added for mouse cursor bring-up:
##   ps2_clk
##   ps2_data
##   an[7:0]
##   seg[7:0]
##==============================================================================
## Clock
##==============================================================================
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { clk100mhz }]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0.000 5.000} [get_ports { clk100mhz }]

##==============================================================================
## CPU Reset Button
##==============================================================================
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports { resetn }]

##==============================================================================
## Push Buttons
##==============================================================================
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { BTNC }]
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports { BTNU }]
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports { BTND }]
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports { BTNL }]
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports { BTNR }]

##==============================================================================
## LEDs (disabled - debug-only outputs no longer wired in RTL)
##==============================================================================
#set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { led[0]  }]
#set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { led[1]  }]
#set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { led[2]  }]
#set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports { led[3]  }]
#set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { led[4]  }]
#set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { led[5]  }]
#set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { led[6]  }]
#set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports { led[7]  }]
#set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { led[8]  }]
#set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports { led[9]  }]
#set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { led[10] }]
#set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { led[11] }]
#set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { led[12] }]
#set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports { led[13] }]
#set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { led[14] }]
#set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports { led[15] }]

##==============================================================================
## VGA
##==============================================================================

## VGA Red
set_property -dict { PACKAGE_PIN A3 IOSTANDARD LVCMOS33 } [get_ports { RED[0] }]
set_property -dict { PACKAGE_PIN B4 IOSTANDARD LVCMOS33 } [get_ports { RED[1] }]
set_property -dict { PACKAGE_PIN C5 IOSTANDARD LVCMOS33 } [get_ports { RED[2] }]
set_property -dict { PACKAGE_PIN A4 IOSTANDARD LVCMOS33 } [get_ports { RED[3] }]

## VGA Green
set_property -dict { PACKAGE_PIN C6 IOSTANDARD LVCMOS33 } [get_ports { GRN[0] }]
set_property -dict { PACKAGE_PIN A5 IOSTANDARD LVCMOS33 } [get_ports { GRN[1] }]
set_property -dict { PACKAGE_PIN B6 IOSTANDARD LVCMOS33 } [get_ports { GRN[2] }]
set_property -dict { PACKAGE_PIN A6 IOSTANDARD LVCMOS33 } [get_ports { GRN[3] }]

## VGA Blue
set_property -dict { PACKAGE_PIN B7 IOSTANDARD LVCMOS33 } [get_ports { BLU[0] }]
set_property -dict { PACKAGE_PIN C7 IOSTANDARD LVCMOS33 } [get_ports { BLU[1] }]
set_property -dict { PACKAGE_PIN D8 IOSTANDARD LVCMOS33 } [get_ports { BLU[2] }]
set_property -dict { PACKAGE_PIN D7 IOSTANDARD LVCMOS33 } [get_ports { BLU[3] }]

## VGA Sync
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { HSYNC }]
set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports { VSYNC }]

##==============================================================================
## Pmod JA - Digilent Pmod KYPD
##
## Direct plug connection used:
##   KYPD Pin 1  -> JA1  -> COL4 -> kp_col[3]
##   KYPD Pin 2  -> JA2  -> COL3 -> kp_col[2]
##   KYPD Pin 3  -> JA3  -> COL2 -> kp_col[1]
##   KYPD Pin 4  -> JA4  -> COL1 -> kp_col[0]
##   KYPD Pin 7  -> JA7  -> ROW4 -> kp_row[3]
##   KYPD Pin 8  -> JA8  -> ROW3 -> kp_row[2]
##   KYPD Pin 9  -> JA9  -> ROW2 -> kp_row[1]
##   KYPD Pin 10 -> JA10 -> ROW1 -> kp_row[0]
##============================================================================== WILL NEED TO BRINGF BACK

### Keypad columns (outputs from FPGA)
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 } [get_ports { kp_col[3] }]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports { kp_col[2] }]
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports { kp_col[1] }]
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports { kp_col[0] }]

### Keypad rows (inputs to FPGA)
set_property -dict { PACKAGE_PIN D17 IOSTANDARD LVCMOS33 } [get_ports { kp_row[3] }]
set_property -dict { PACKAGE_PIN E17 IOSTANDARD LVCMOS33 } [get_ports { kp_row[2] }]
set_property -dict { PACKAGE_PIN F18 IOSTANDARD LVCMOS33 } [get_ports { kp_row[1] }]
set_property -dict { PACKAGE_PIN G18 IOSTANDARD LVCMOS33 } [get_ports { kp_row[0] }]

### Internal pullups for idle row inputs
set_property PULLUP true [get_ports { kp_row[3] }]
set_property PULLUP true [get_ports { kp_row[2] }]
set_property PULLUP true [get_ports { kp_row[1] }]
set_property PULLUP true [get_ports { kp_row[0] }]

##==============================================================================
## 7 Segment Display (disabled - debug-only outputs no longer wired in RTL)
## seg[7:0] = {dp,g,f,e,d,c,b,a}
## an[7:0]  = active-low digit enables
##==============================================================================

#set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { seg[0] }] ;# CA / a
#set_property -dict { PACKAGE_PIN R10 IOSTANDARD LVCMOS33 } [get_ports { seg[1] }] ;# CB / b
#set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { seg[2] }] ;# CC / c
#set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports { seg[3] }] ;# CD / d
#set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { seg[4] }] ;# CE / e
#set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports { seg[5] }] ;# CF / f
#set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports { seg[6] }] ;# CG / g
#set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports { seg[7] }] ;# DP

#set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports { an[0] }]
#set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { an[1] }]
#set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { an[2] }]
#set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 } [get_ports { an[3] }]
#set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports { an[4] }]
#set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports { an[5] }]
#set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports { an[6] }]
#set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports { an[7] }]

##==============================================================================
## USB HID (PS/2)
##==============================================================================

set_property -dict { PACKAGE_PIN F4 IOSTANDARD LVCMOS33 PULLUP true } [get_ports { ps2_clk }]
set_property -dict { PACKAGE_PIN B2 IOSTANDARD LVCMOS33 PULLUP true } [get_ports { ps2_data }]

##==============================================================================
## On-board microSD Slot (SPI-mode wiring)
##
## SPI-mode mapping used by this design:
##   sd_clk         -> SD_SCK
##   sd_cmd         -> SD_CMD  (MOSI in SPI mode)
##   sd_dat0_miso   -> SD_DAT[0] (MISO in SPI mode)
##   sd_dat1_unused -> SD_DAT[1] (unused in SPI mode)
##   sd_dat2_unused -> SD_DAT[2] (unused in SPI mode)
##   sd_dat3_cs_n   -> SD_DAT[3] (chip select in SPI mode)
##   sd_reset_n     -> SD_RESET
##   sd_card_detect -> SD_CD
##
## Notes:
##   - The FPGA drives sd_reset_n low through sd_slot_ctrl to enable the slot
##     for FPGA-side access.
##   - DAT1 and DAT2 are unused for SPI mode but are still constrained so the
##     physical SD bus is fully represented at the top level.
##==============================================================================

set_property -dict { PACKAGE_PIN E2 IOSTANDARD LVCMOS33 } [get_ports { sd_reset_n }]
set_property -dict { PACKAGE_PIN A1 IOSTANDARD LVCMOS33 } [get_ports { sd_card_detect }]
set_property -dict { PACKAGE_PIN B1 IOSTANDARD LVCMOS33 } [get_ports { sd_clk }]
set_property -dict { PACKAGE_PIN C1 IOSTANDARD LVCMOS33 } [get_ports { sd_cmd }]
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports { sd_dat0_miso }]
set_property -dict { PACKAGE_PIN E1 IOSTANDARD LVCMOS33 } [get_ports { sd_dat1_unused }]
set_property -dict { PACKAGE_PIN F1 IOSTANDARD LVCMOS33 } [get_ports { sd_dat2_unused }]
set_property -dict { PACKAGE_PIN D2 IOSTANDARD LVCMOS33 } [get_ports { sd_dat3_cs_n }]

## Optional pull-up on card detect if needed during bring-up
set_property PULLUP true [get_ports { sd_card_detect }]