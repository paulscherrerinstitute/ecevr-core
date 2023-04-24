# EoE Client Software Support

This directory contains utilities for accessing firmware resources via EoE.

## The `ecurcli` tool

`ecurcli` lets the user inspect and modify registers on the target via EoE.
Usage information may be printed with the `-h` option.

Note that while most registers are defined in the BSP (i.e., hdl code
contained in this module) there are a few (at the 'local' base address
`0x180000`) which are application-specific for the ethercat-evr prototype.
This should eventually be cleaned up...

## `spiFlashRead`

The `spiFlashRead` provides read-access to the on-board flash memory
(which is also the FPGA configuration memory). Note that writing this
memory is accomplished via EtherCAT/FoE. However, FoE read-access has
not been implemented in firmware (as this is not needed for regular
firmware updates). For special applications, testing and debugging the
`spiFlashRead` utility can be employed to read back the memory.
Usage info is available on-line (`-h` option).
