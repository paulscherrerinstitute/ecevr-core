
LAN9254_DIR=../../lan9254-rtl-esc/hdl
EVR320_DIR=../../evr320/hdl
PSI_COMMON_DIR=../../psi_common/hdl
UNISIM_DIR=/opt/ghdl/v2.0.0-gcc/vivado-2021.2/
GHDL=ghdl

LANSRCS+=ESCBasicTypesPkg.vhd
LANSRCS+=Lan9254Pkg.vhd
LANSRCS+=Lan9254ESCPkg.vhd
LANSRCS+=IPAddrConfigPkg.vhd
LANSRCS+=IlaWrappersPkg.vhd
LANSRCS+=ESCMbxPkg.vhd
LANSRCS+=ESCFoEPkg.vhd
LANSRCS+=MicroUDPPkg.vhd
LANSRCS+=Udp2BusPkg.vhd
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
SRCS+=FoE2SpiPkg.vhd
SRCS+=EcEvrBspPkg.vhd
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_bit_cc.vhd)
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_i2c_master.vhd)
SRCS+=PsiI2cStreamIF.vhd
SRCS+=EEPROMConfigurator.vhd
SRCS+=I2cEEPROM.vhd
SRCS+=EEPROMConfiguratorTb.vhd
SRCS+=SpiBitShifter.vhd
SRCS+=SpiMonitor.vhd
SRCS+=SpiBitShifterTb.vhd
SRCS+=Bus2SpiFlashIF.vhd
SRCS+=FoE2Spi.vhd
SRCS+=FoE2SpiTb.vhd
SRCS+=IcapE2Reg.vhd
SRCS+=IcapE2RegTb.vhd
SRCS+=SpiMonitorTb.vhd
SRCS+=EcEvrPulseGen.vhd
SRCS+=EcEvrPulseGenTb.vhd

TSTS=$(filter %Tb,$(patsubst %.vhd,%,$(SRCS)))

IcapE2RegTb_GHDLFLAGS=$(addprefix -P,$(UNISIM_DIR)) -fsynopsys
IcapE2RegTb_RUNFLAGS =--stop-time=20us

test: $(addprefix run_,$(TSTS))

build: $(TSTS)

$(addprefix run_,$(TSTS)):run_%:%
	echo $@
	echo $^
	./$(@:run_%=%) $($(@:run_%=%)_RUNFLAGS)

$(TSTS): ana
	$(GHDL) -e -g -Wl,-no-pie $($@_GHDLFLAGS) -o $@ $@

ana: $(SRCS)
	$(GHDL) -a -g -P$(LAN9254_DIR) $(addprefix -P, $(UNISIM_DIR)) $(SRCS)

EEPROMContentPkg.vhd:
	$(LAN9254_DIR)/../tool/EsiTool.py -V eeprom_config_tst.xml

.PHONY: ana clean build test $(addprefix run_,$(TSTS))

clean:
	$(RM) $(notdir $(SRCS:%.vhd=%.o)) work-obj93.cf $(TSTS) e~*.o dump.ghw
