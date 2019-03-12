
set_clock_groups -async -group [get_clocks -include_generated_clocks timingRefClk]
set_clock_groups -async -group [get_clocks -include_generated_clocks clk_fpga_0]

set_clock_groups -async -group [get_clocks -include_generated_clocks timingRxClk]
set_clock_groups -async -group [get_clocks -include_generated_clocks timingTxClk]

