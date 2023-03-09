# CDC constraint, SCOPE_TO_REF EcEvrWrapper
# Value read from EEPROM and then held steady
set_false_path -through [get_nets -hier {dbufLastAddr*}]
