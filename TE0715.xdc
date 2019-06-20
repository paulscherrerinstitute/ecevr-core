##############################################################################
## This file is part of 'Example Project Firmware'.
## It is subject to the license terms in the LICENSE.txt file found in the
## top-level directory of this distribution and at:
##    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
## No part of 'Example Project Firmware', including this file,
## may be copied, modified, propagated, or distributed except according to
## the terms contained in the LICENSE.txt file.
##############################################################################
# I/O Port Mapping
#

##########################################################
## SFP MGT0
set_property PACKAGE_PIN AA3     [get_ports {mgtTxP[0]}]
set_property PACKAGE_PIN AB3     [get_ports {mgtTxN[0]}]
set_property PACKAGE_PIN AA7     [get_ports {mgtRxP[0]}]
set_property PACKAGE_PIN AB7     [get_ports {mgtRxN[0]}]

## SFP MGT1
set_property PACKAGE_PIN W4      [get_ports {mgtTxP[1]}]
set_property PACKAGE_PIN Y4      [get_ports {mgtTxN[1]}]
set_property PACKAGE_PIN W8      [get_ports {mgtRxP[1]}]
set_property PACKAGE_PIN Y8      [get_ports {mgtRxN[1]}]


## SFP MGT2
set_property PACKAGE_PIN AA5     [get_ports {mgtTxP[2]}]
set_property PACKAGE_PIN AB5     [get_ports {mgtTxN[2]}]
set_property PACKAGE_PIN AA9     [get_ports {mgtRxP[2]}]
set_property PACKAGE_PIN AB9     [get_ports {mgtRxN[2]}]

## SFP MGT3
set_property PACKAGE_PIN W2      [get_ports {mgtTxP[3]}]
set_property PACKAGE_PIN Y2      [get_ports {mgtTxN[3]}]
set_property PACKAGE_PIN W6      [get_ports {mgtRxP[3]}]
set_property PACKAGE_PIN Y6      [get_ports {mgtRxN[3]}]

## MGTREFCLK0 -- carrier
set_property PACKAGE_PIN U9      [get_ports {mgtRefClkP[0]}]
set_property PACKAGE_PIN V9      [get_ports {mgtRefClkN[0]}]

## MGTREFCLK1 -- Si5338
set_property PACKAGE_PIN U5      [get_ports {mgtRefClkP[1]}]
set_property PACKAGE_PIN V5      [get_ports {mgtRefClkN[1]}]
##########################################################
# END SFP
##########################################################
#

##########################################################
# B34
##########################################################

# IO_L9P_T1_DQS_34 -- Marvell PHY LED[0]
set_property PACKAGE_PIN J3       [get_ports {gpIn[2]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {gpIn[2]}]

# B34_L10_P
set_property PACKAGE_PIN L2      [get_ports {timingRecClkP}]
# IOSTANDARD defined in VHDL depending on PRJ_PART

# B34_L10_N
set_property PACKAGE_PIN L1      [get_ports {timingRecClkN}]
# IOSTANDARD defined in VHDL depending on PRJ_PART

create_clock -name timingRefClk -period 5.3846 [get_ports {mgtRefClkP[0]}]
# Just rename, Timing IP already defines
set timingTxClk  [get_clocks -regexp {.*/GEN_TIMING.U_TimingGt/.*/TXOUTCLK$}]
set timingRxClk  [get_clocks -regexp {.*/GEN_TIMING.U_TimingGt/.*/RXOUTCLK$}]

# Time it 
create_clock -name si5338Clk    -period 8.000  [get_ports {mgtRefClkP[1]}]
