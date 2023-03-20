# CDC constraint, SCOPE_TO_REF EcEvrWrapper
# Value read from EEPROM and then held steady
set_false_path -through [get_nets -hier {dbufLastAddr*}]

set_max_delay -datapath_only -from [get_clocks -of_objects [get_ports sysClk]] -through [get_nets {G_OPEN_EVR.U_OPEN_EVR/cfgReqLoc*}] -to [get_clocks -of_objects [get_ports eventClk]] [get_property PERIOD [get_clocks -of_objects [get_ports eventClk]]]
