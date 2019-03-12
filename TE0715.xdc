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
## SFP MGT1
set_property PACKAGE_PIN W4      [get_ports {timingTxP}]
set_property PACKAGE_PIN Y4      [get_ports {timingTxN}]
set_property PACKAGE_PIN W8      [get_ports {timingRxP}]
set_property PACKAGE_PIN Y8      [get_ports {timingRxN}]
## MGTREFCLK1 -- Si5338
set_property PACKAGE_PIN U5      [get_ports {timingRefClkP}]
set_property PACKAGE_PIN V5      [get_ports {timingRefClkN}]
##########################################################
# END SFP
##########################################################
#
# B13_L6_N
set_property PACKAGE_PIN U14     [get_ports {sfp_tx_dis[0]}  ]
set_property IOSTANDARD LVCMOS33 [get_ports {sfp_tx_dis[0]}  ]

# B13_L6_P
set_property PACKAGE_PIN U13     [get_ports {sfp_tx_flt[0]}  ]
set_property IOSTANDARD LVCMOS33 [get_ports {sfp_tx_flt[0]}  ]
set_property PULLUP     true     [get_ports {sfp_tx_flt[0]}  ]

# B13_L4_N
set_property PACKAGE_PIN W11     [get_ports {sfp_los[0]}     ]
set_property IOSTANDARD LVCMOS33 [get_ports {sfp_los[0]}     ]
set_property PULLUP     true     [get_ports {sfp_los[0]}     ]

# B13_L4_P
set_property PACKAGE_PIN V11     [get_ports {sfp_presentb[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sfp_presentb[0]}]
set_property PULLUP     true     [get_ports {sfp_presentb[0]}]

create_clock -name timingRefClk -period 5.3846 [get_ports {timingRefClkP}]
create_clock -name timingTxClk  -period 5.385  [get_pins -hier -regexp {.*/GEN_TIMING.U_TimingGtx/.*/TXOUTCLK$}]
create_clock -name timingRxClk  -period 5.385  [get_pins -hier -regexp {.*/GEN_TIMING.U_TimingGtx/.*/RXOUTCLK$}]
