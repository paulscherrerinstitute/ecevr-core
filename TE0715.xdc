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
#set_property PACKAGE_PIN AA3     [get_ports {timingTxP}]
#set_property PACKAGE_PIN AB3     [get_ports {timingTxN}]
#set_property PACKAGE_PIN AA7     [get_ports {timingRxP}]
#set_property PACKAGE_PIN AB7     [get_ports {timingRxN}]

## SFP MGT1
set_property PACKAGE_PIN W4      [get_ports {sfpTxP[0]}]
set_property PACKAGE_PIN Y4      [get_ports {sfpTxN[0]}]
set_property PACKAGE_PIN W8      [get_ports {sfpRxP[0]}]
set_property PACKAGE_PIN Y8      [get_ports {sfpRxN[0]}]

## SFP MGT2
#set_property PACKAGE_PIN AA5     [get_ports {sfpTxP[1]}]
#set_property PACKAGE_PIN AB5     [get_ports {sfpTxN[1]}]
#set_property PACKAGE_PIN AA9     [get_ports {sfpRxP[1]}]
#set_property PACKAGE_PIN AB9     [get_ports {sfpRxN[1]}]

## SFP MGT3
#set_property PACKAGE_PIN W2      [get_ports {sfpTxP[2]}]
#set_property PACKAGE_PIN Y2      [get_ports {sfpTxN[2]}]
#set_property PACKAGE_PIN W6      [get_ports {sfpRxP[2]}]
#set_property PACKAGE_PIN Y6      [get_ports {sfpRxN[2]}]

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

# B34_L10_P
set_property PACKAGE_PIN L2      [get_ports {timingRecClkP}]
set_property IOSTANDARD  LVDS    [get_ports {timingRecClkP}]

# B34_L10_N
set_property PACKAGE_PIN L1      [get_ports {timingRecClkN}]
set_property IOSTANDARD  LVDS    [get_ports {timingRecClkN}]

create_clock -name timingRefClk -period 5.3846 [get_ports {mgtRefClkP[0]}]
create_clock -name timingTxClk  -period 5.385  [get_pins -hier -regexp {.*/GEN_TIMING.U_TimingGt/.*/TXOUTCLK$}]
create_clock -name timingRxClk  -period 5.385  [get_pins -hier -regexp {.*/GEN_TIMING.U_TimingGt/.*/RXOUTCLK$}]
