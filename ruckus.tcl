# Load RUCKUS environment and library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Load local source Code and constraints
foreach f {
  AxilLan9254HbiMaster.vhd
  AxilSpiMaster.vhd
  Bus2DRP.vhd
  Bus2I2cStreamIF.vhd
  Bus2SpiFlashIF.vhd
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
  FoE2SpiPkg.vhd
  FoE2Spi.vhd
  I2cEEPROM.vhd
  I2cProgrammer.vhd
  I2cWrapper.vhd
  IcapE2Reg.vhd
  PhaseDetector.vhd
  PsiI2cStreamIF.vhd
  PwmCore.vhd
  SpiBitShifter.vhd
  SpiMonitor.vhd
  ZynqBspPkg.vhd
  ZynqIOBuf.vhd
  ZynqOBufDS.vhd
  ZynqSpiIOBuf.vhd
} {
  loadSource    -path "$::DIR_PATH/hdl/$f"
}
