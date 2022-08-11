
LAN9254_DIR=../../lan9254-rtl-esc/hdl
EVR320_DIR=../../evr320/hdl
PSI_COMMON_DIR=../../psi_common/hdl
GHDL=ghdl

LANSRCS+=ESCBasicTypesPkg.vhd
LANSRCS+=Lan9254Pkg.vhd
LANSRCS+=Lan9254ESCPkg.vhd
LANSRCS+=IPAddrConfigPkg.vhd
LANSRCS+=IlaWrappersPkg.vhd
LANSRCS+=ESCFoEPkg.vhd
#LANSRCS+=EEPROMContentPkg.vhd

SRCS = $(addprefix $(LAN9254_DIR)/,$(LANSRCS))
SRCS+=EvrTxPDOPkg.vhd
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_array_pkg.vhd)
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_math_pkg.vhd)
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_logic_pkg.vhd)
SRCS+=$(addprefix $(EVR320_DIR)/,evr320_pkg.vhd)
SRCS+=Evr320ConfigPkg.vhd
SRCS+=EEPROMConfigPkg.vhd
SRCS+=EEPROMContentPkg.vhd
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_bit_cc.vhd)
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_i2c_master.vhd)
SRCS+=PsiI2cStreamIF.vhd
SRCS+=EEPROMConfigurator.vhd
SRCS+=I2cEEPROM.vhd
SRCS+=EEPROMConfiguratorTb.vhd
SRCS+=SpiBitShifter.vhd
SRCS+=SpiBitShifterTb.vhd
SRCS+=FoE2Spi.vhd
SRCS+=FoE2SpiTb.vhd

eepromconfiguratortb: ana
	$(GHDL) -e $@

spibitshiftertb: ana
	$(GHDL) -e $@

foe2spitb: ana
	$(GHDL) -e $@

ana: $(SRCS)
	$(GHDL) -a -P$(LAN9254_DIR) $(SRCS)

EEPROMContentPkg.vhd:
	$(LAN9254_DIR)/../tool/EsiTool.py -V eeprom_config_tst.xml

.PHONY: ana clean

clean:
	$(RM) eepromconfiguratortb $(notdir $(SRCS:%.vhd=%.o)) work-obj93.cf e~eepromconfiguratortb.o
