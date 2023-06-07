LAN9254_DIR=../../lan9254-rtl-esc/hdl
EVR320_DIR=../../evr320/hdl
PSI_COMMON_DIR=../../psi_common/hdl

GHDL=ghdl

-include config.local.mk

ifndef UNISIM_DIR
$(error "please set UNISIM_DIR to point to ghdl build of unisim")
endif

LANSRCS+=ESCBasicTypesPkg.vhd
LANSRCS+=Lan9254Pkg.vhd
LANSRCS+=Lan9254ESCPkg.vhd
LANSRCS+=IPAddrConfigPkg.vhd
LANSRCS+=IlaWrappersPkg.vhd
LANSRCS+=ESCMbxPkg.vhd
LANSRCS+=ESCFoEPkg.vhd
LANSRCS+=MicroUDPPkg.vhd
LANSRCS+=Udp2BusPkg.vhd
LANSRCS+=SynchronizerBit.vhd
#LANSRCS+=EEPROMContentPkg.vhd

SRCS = $(addprefix $(LAN9254_DIR)/,$(LANSRCS))
SRCS+=$(addprefix ../hdl/,EvrTxPDOPkg.vhd)
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_array_pkg.vhd)
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_math_pkg.vhd)
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_logic_pkg.vhd)
SRCS+=$(addprefix $(EVR320_DIR)/,evr320_pkg.vhd)
SRCS+=$(addprefix ../hdl/,Evr320ConfigPkg.vhd)
SRCS+=$(addprefix ../hdl/,EEPROMConfigPkg.vhd)
SRCS+=$(addprefix ../hdl/,EEPROMContentPkg.vhd)
SRCS+=$(addprefix ../hdl/,FoE2SpiPkg.vhd)
SRCS+=$(addprefix ../hdl/,EcEvrBspPkg.vhd)
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_bit_cc.vhd)
SRCS+=$(addprefix $(PSI_COMMON_DIR)/,psi_common_i2c_master.vhd)
SRCS+=$(addprefix ../hdl/,PsiI2cStreamIF.vhd)
SRCS+=$(addprefix ../hdl/,EEPROMConfigurator.vhd)
SRCS+=$(addprefix ../hdl/,I2cEEPROM.vhd)
SRCS+=EEPROMConfiguratorTb.vhd
SRCS+=$(addprefix ../hdl/,SpiBitShifter.vhd)
SRCS+=$(addprefix ../hdl/,SpiMonitor.vhd)
SRCS+=SpiBitShifterTb.vhd
SRCS+=$(addprefix ../hdl/,Bus2SpiFlashIF.vhd)
SRCS+=$(addprefix ../hdl/,FoE2Spi.vhd)
SRCS+=FoE2SpiTb.vhd
SRCS+=$(addprefix ../hdl/,IcapE2Reg.vhd)
SRCS+=IcapE2RegTb.vhd
SRCS+=SpiMonitorTb.vhd
SRCS+=$(addprefix ../hdl/,EcEvrPulseGen.vhd)
SRCS+=EcEvrPulseGenTb.vhd
SRCS+=$(addprefix ../hdl/,ClockMeasure.vhd)
SRCS+=ClockMeasureTb.vhd

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
	$(RM) $(notdir $(SRCS:%.vhd=%.o)) work-obj93.cf $(TSTS) e~*.o dump.ghw frame_data_e2_rbt_out.txt
