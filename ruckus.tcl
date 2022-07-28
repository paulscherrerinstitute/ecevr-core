# Load RUCKUS environment and library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Load local source Code and constraints
foreach f {
  AxilLan9254HbiMaster.vhd
  AxilSpiMaster.vhd
  EcEvrBoardMap.vhd
  EcEvrBspPkg.vhd
  EcEvrWrapper.vhd
  EEPROMConfigPkg.vhd
  EEPROMConfigurator.vhd
  Evr320ConfigPkg.vhd
  evr320_udp2bus.vhd
  evr320_udp2bus_wrapper.vhd
  EvrTxPDOPkg.vhd
  EvrTxPDO.vhd
  I2cEEPROM.vhd
  PhaseDetector.vhd
  PsiI2cStreamIF.vhd
  ZynqBspPkg.vhd
  ZynqIOBuf.vhd
  ZynqOBufDS.vhd
  ZynqSpiIOBuf.vhd
} {
  loadSource    -path "$::DIR_PATH/rtl/$f"
}
