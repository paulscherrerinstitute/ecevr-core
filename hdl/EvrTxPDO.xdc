# CDC constraints for EvrTxPDO - use SCOPE_TO_REF

# After a PDO trigger data are held stable until the next PDO trigger; this is eternal
# for the fabric's viewpoint.
set_max_delay -datapath_only -from [get_clocks -of_objects [get_ports evrClk]] -through [get_nets -hier {ecArray*}] 100.0
set_max_delay -datapath_only -from [get_clocks -of_objects [get_ports evrClk]] -through [get_nets -hier {tsArray*}] 100.0
