-------------------------------------------------------------------------------
-- File       : TE0715.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2015-04-08
-- Last update: 2017-02-16
-------------------------------------------------------------------------------
-- Description: Top Level Entity
-------------------------------------------------------------------------------
-- This file is part of 'Example Project Firmware'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'Example Project Firmware', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Structurally this project is a bit of a mess. This is due to the fact that
-- In SURF and Timing the MGTs are handled independently, i.e., ethernet and
-- timing 'embed' MGTs in their respective wrappers.
-- No problem because they can be clocked by individual 'channel PLLs'.
--
-- However, the Artix/GTP Transceiver lacks individual channel PLLs and therefore
-- must use/share the two available quad PLLs.
-- Unfortunately, both, the SURF/ethernet as well as the timing wrappers assume
-- they are the sole owners of a quad and instantiate the quad PLL which creates
-- a conflict.
--
-- When only a single quad is available then timing and ethernet have to share
-- the quad PLLs (each one can use one of the two available PLLs).
--
-- OTOH, we don't want to change the structure completely as it works fine for
-- other platforms (GTX). For this reason a modified version of the ethernet
-- wrapper was created (GigEthGtp7WrapperAdv) which adds ports and generics
-- that provide outside access to the quad pll.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;
use work.AxiLitePkg.all;
use work.AxiPkg.all;
use work.EthMacPkg.all;
use work.TimingPkg.all;
use work.TimingConnectorPkg.all;

library unisim;
use unisim.vcomponents.all;

entity TE0715 is
   generic (
      TPD_G             : time    := 1 ns;
      BUILD_INFO_G      : BuildInfoType;
      SIM_SPEEDUP_G     : boolean := false;
      SIMULATION_G      : boolean := false;
      NUM_TRIGS_G       : natural := 7;
      CLK_FEEDTHRU_G    : boolean := false;
      -- Did you set bit PMA_RSV2[5] of your GTX? See UG476 page 209.
      -- Otherwise the eye-scan is completely red
      PRJ_VARIANT_G     : string  := "deflt"; -- when 'ibert', load ip/_ibert_.xci
      NUM_SFPS_G        : natural := 2;
      NUM_GP_IN_G       : natural := 3;
      NUM_LED_G         : natural := 5;
      PRJ_PART_G        : string;
      TIMING_ETH_MGT_G  : natural range 0 to 2 := 2 -- which MGT to use for the timing ethernet stream
   );
   port (
      DDR_addr          : inout STD_LOGIC_VECTOR ( 14 downto 0 );
      DDR_ba            : inout STD_LOGIC_VECTOR (  2 downto 0 );
      DDR_cas_n         : inout STD_LOGIC;
      DDR_ck_n          : inout STD_LOGIC;
      DDR_ck_p          : inout STD_LOGIC;
      DDR_cke           : inout STD_LOGIC;
      DDR_cs_n          : inout STD_LOGIC;
      DDR_dm            : inout STD_LOGIC_VECTOR ( 3 downto 0 );
      DDR_dq            : inout STD_LOGIC_VECTOR ( 31 downto 0 );
      DDR_dqs_n         : inout STD_LOGIC_VECTOR ( 3 downto 0 );
      DDR_dqs_p         : inout STD_LOGIC_VECTOR ( 3 downto 0 );
      DDR_odt           : inout STD_LOGIC;
      DDR_ras_n         : inout STD_LOGIC;
      DDR_reset_n       : inout STD_LOGIC;
      DDR_we_n          : inout STD_LOGIC;
      FIXED_IO_ddr_vrn  : inout STD_LOGIC;
      FIXED_IO_ddr_vrp  : inout STD_LOGIC;
      FIXED_IO_mio      : inout STD_LOGIC_VECTOR ( 53 downto 0 );
      FIXED_IO_ps_clk   : inout STD_LOGIC;
      FIXED_IO_ps_porb  : inout STD_LOGIC;
      FIXED_IO_ps_srstb : inout STD_LOGIC;
      mgtRefClkP        : in  slv(1 downto 0);
      mgtRefClkN        : in  slv(1 downto 0);
      diffOutP          : out slv(NUM_TRIGS_G - 1 downto 0);
      diffOutN          : out slv(NUM_TRIGS_G - 1 downto 0);
      timingRecClkP     : out sl;
      timingRecClkN     : out sl;
      led               : out slv(NUM_LED_G - 1 downto 0);
      -- led[0] -> green LED, D5 (board edge)
      -- led[1] -> red LED, D4 (board edge)
      -- led[2] -> yellow LED in eth connector
      -- led[3] -> orange/anode - green/cathode in eth connector
      -- led[4] -> orange/cathode - green/anode in eth connector
--      enableSFP         : out sl := '1';
      mgtTxP            : out slv(3 downto 0);
      mgtTxN            : out slv(3 downto 0);
      mgtRxP            : in  slv(3 downto 0);
      mgtRxN            : in  slv(3 downto 0);

      sfp_tx_dis        : out slv(NUM_SFPS_G - 1 downto 0) := (others => '0');
      sfp_tx_flt        : in  slv(NUM_SFPS_G - 1 downto 0);
      sfp_los           : in  slv(NUM_SFPS_G - 1 downto 0);
      sfp_presentb      : in  slv(NUM_SFPS_G - 1 downto 0);
      resetOut          : inout sl;
      resetInp          : in    sl;
      gpIn              : in    slv(NUM_GP_IN_G - 1 downto 0)
      -- gpIn[0] -> Si5344 LOLb
      -- gpIn[1] -> Si5344 INTRb
      -- gpIn[2] -> Marvell Ethernet PHY LED[0]
   );

   constant  IBERT_C          : boolean := ( PRJ_VARIANT_G = "ibert"  );
   constant  DEVBRD_C         : boolean := ( PRJ_VARIANT_G = "devbd" or PRJ_VARIANT = "ecevr" );
   constant  COPY_CLOCKS_C    : boolean := ( PRJ_VARIANT_G = "toggle" );

   constant  TIMING_PLL_C     : natural range 0 to 1 := 1;
   constant  TIMING_PLL_SEL_C : slv(1 downto 0) := ite( TIMING_PLL_C = 0, "00", "11" );

   function  isArtix(part : string := PRJ_PART_G) return boolean is
      variable prefix: string(0 to 6);
   begin
      prefix := part(part'left to part'left + 6);
      return prefix = "XC7Z012" or prefix = "XC7Z015";
   end function isArtix;

   attribute IO_BUFFER_TYPE : string;
   attribute IOSTANDARD     : string;
   attribute SLEW           : string;
   
   attribute IO_BUFFER_TYPE of mgtTxP : signal is ite(IBERT_C, "OBUF", "NONE");
   attribute IO_BUFFER_TYPE of mgtTxN : signal is ite(IBERT_C, "OBUF", "NONE");
   attribute IO_BUFFER_TYPE of mgtRxP : signal is ite(IBERT_C, "IBUF", "NONE");
   attribute IO_BUFFER_TYPE of mgtRxN : signal is ite(IBERT_C, "IBUF", "NONE");

   attribute IOSTANDARD     of timingRecClkP : signal is ite( isArtix, "DIFF_HSTL_I_18", "LVDS" );
   attribute IOSTANDARD     of timingRecClkN : signal is ite( isArtix, "DIFF_HSTL_I_18", "LVDS" );
   attribute SLEW           of timingRecClkP : signal is ite( isArtix, "FAST",           ""     );
   attribute SLEW           of timingRecClkN : signal is ite( isArtix, "FAST",           ""     );

end TE0715;

architecture top_level of TE0715 is

  -- must match CONFIG.PCW_NUM_F2P_INTR_INPUTS {16} setting for IP generation
  constant NUM_IRQS_C  : natural          := 16;
  constant CLK_FREQ_C  : real             := 50.0E6;

  constant FEEDTHRU_C  : natural          := ite( CLK_FEEDTHRU_G, 1, 0 );

  constant TIMING_UDP_PORT_C       : natural := 8197;

  constant TIMING_GTP_HAS_COMMON_C : boolean := ((not isArtix) or (TIMING_UDP_PORT_C = 0));

  constant ETH_MAC_C   : slv(47 downto 0) := x"aa0300564400";  -- 00:44:56:00:03:01 (ETH only)

  constant NUM_AXI_SLV_C : natural        := 1;

  -- some differential outputs are swapped on PCB
  constant TIMING_TRIG_INVERT_C : slv(NUM_TRIGS_G - 1 downto 0) := "1100010";

  constant BLINK_TIME_C         : natural := natural( CLK_FREQ_C * 0.2 );
  constant BLINK_TIME_UNS_C     : unsigned(bitSize(BLINK_TIME_C) - 1 downto 0) := to_unsigned(BLINK_TIME_C, bitSize(BLINK_TIME_C));

  constant TIMING_SFP_MGT_C     : natural := ite( TIMING_ETH_MGT_G = 1, 2, 1 );

  signal   mgtRefClk   : slv(1 downto 0);
  signal   mgtRefClkBuf: slv(1 downto 0);

  signal   outClk      : sl;
  signal   outRst      : sl;

  signal   txDiv       : unsigned(27 downto 0) := to_unsigned(0, 28);
  signal   rxDiv       : unsigned(27 downto 0) := to_unsigned(0, 28);

  signal   rxLedData   : slv(1 downto 0);
  signal   rxLedTimer  : unsigned(BLINK_TIME_UNS_C'range) := to_unsigned(0, BLINK_TIME_UNS_C'length);
  signal   rxLedState  : sl := '0';
  signal   rxClkState  : sl := rxDiv(27);

  signal   dbgTrig     : slv(3 downto 0);

  signal   macAddr     : slv(47 downto 0);

  signal   timingSfpRxP: sl;
  signal   timingSfpRxN: sl;
  signal   timingSfpTxP: sl;
  signal   timingSfpTxN: sl;

  signal   timingEthRxP: sl;
  signal   timingEthRxN: sl;
  signal   timingEthTxP: sl;
  signal   timingEthTxN: sl;

  signal   ethTxMaster, ethRxMaster : AxiStreamMasterType;
  signal   ethTxSlave , ethRxSlave  : AxiStreamSlaveType;

  signal   timingIb    : TimingWireIbType := TIMING_WIRE_IB_INIT_C;
  signal   timingOb    : TimingWireObType := TIMING_WIRE_OB_INIT_C;

COMPONENT ibert_7series_gt_0
  PORT (
    TXN_O : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    TXP_O : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    RXOUTCLK_O : OUT STD_LOGIC;
    RXN_I : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    RXP_I : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    GTREFCLK0_I : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    GTREFCLK1_I : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    SYSCLK_I : IN STD_LOGIC
  );
END COMPONENT;

component processing_system7_0
    PORT (
      USB0_PORT_INDCTL : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
      USB0_VBUS_PWRSELECT : OUT STD_LOGIC;
      USB0_VBUS_PWRFAULT : IN STD_LOGIC;
      M_AXI_GP0_ARVALID : OUT STD_LOGIC;
      M_AXI_GP0_AWVALID : OUT STD_LOGIC;
      M_AXI_GP0_BREADY : OUT STD_LOGIC;
      M_AXI_GP0_RREADY : OUT STD_LOGIC;
      M_AXI_GP0_WLAST : OUT STD_LOGIC;
      M_AXI_GP0_WVALID : OUT STD_LOGIC;
      M_AXI_GP0_ARID : OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
      M_AXI_GP0_AWID : OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
      M_AXI_GP0_WID : OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
      M_AXI_GP0_ARBURST : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
      M_AXI_GP0_ARLOCK : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
      M_AXI_GP0_ARSIZE : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
      M_AXI_GP0_AWBURST : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
      M_AXI_GP0_AWLOCK : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
      M_AXI_GP0_AWSIZE : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
      M_AXI_GP0_ARPROT : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
      M_AXI_GP0_AWPROT : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
      M_AXI_GP0_ARADDR : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      M_AXI_GP0_AWADDR : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      M_AXI_GP0_WDATA : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      M_AXI_GP0_ARCACHE : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      M_AXI_GP0_ARLEN : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      M_AXI_GP0_ARQOS : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      M_AXI_GP0_AWCACHE : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      M_AXI_GP0_AWLEN : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      M_AXI_GP0_AWQOS : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      M_AXI_GP0_WSTRB : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      M_AXI_GP0_ACLK : IN STD_LOGIC;
      M_AXI_GP0_ARREADY : IN STD_LOGIC;
      M_AXI_GP0_AWREADY : IN STD_LOGIC;
      M_AXI_GP0_BVALID : IN STD_LOGIC;
      M_AXI_GP0_RLAST : IN STD_LOGIC;
      M_AXI_GP0_RVALID : IN STD_LOGIC;
      M_AXI_GP0_WREADY : IN STD_LOGIC;
      M_AXI_GP0_BID : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
      M_AXI_GP0_RID : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
      M_AXI_GP0_BRESP : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
      M_AXI_GP0_RRESP : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
      M_AXI_GP0_RDATA : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
      IRQ_F2P : IN STD_LOGIC_VECTOR(NUM_IRQS_C - 1 DOWNTO 0);
      FCLK_CLK0 : OUT STD_LOGIC;
      FCLK_RESET0_N : OUT STD_LOGIC;
      FCLK_RESET1_N : OUT STD_LOGIC;
      MIO : INOUT STD_LOGIC_VECTOR(53 DOWNTO 0);
      DDR_CAS_n : INOUT STD_LOGIC;
      DDR_CKE : INOUT STD_LOGIC;
      DDR_Clk_n : INOUT STD_LOGIC;
      DDR_Clk : INOUT STD_LOGIC;
      DDR_CS_n : INOUT STD_LOGIC;
      DDR_DRSTB : INOUT STD_LOGIC;
      DDR_ODT : INOUT STD_LOGIC;
      DDR_RAS_n : INOUT STD_LOGIC;
      DDR_WEB : INOUT STD_LOGIC;
      DDR_BankAddr : INOUT STD_LOGIC_VECTOR(2 DOWNTO 0);
      DDR_Addr : INOUT STD_LOGIC_VECTOR(14 DOWNTO 0);
      DDR_VRN : INOUT STD_LOGIC;
      DDR_VRP : INOUT STD_LOGIC;
      DDR_DM : INOUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      DDR_DQ : INOUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      DDR_DQS_n : INOUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      DDR_DQS : INOUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      PS_SRSTB : INOUT STD_LOGIC;
      PS_CLK : INOUT STD_LOGIC;
      PS_PORB : INOUT STD_LOGIC
    );
  END component;

   constant AXIS_SIZE_C : positive         := 1;

   constant AXIS_WIDTH_C    : positive     := 4;

   signal   sysClk          : sl;
   signal   sysRst          : sl;
   signal   sysRstN         : sl;

   signal   appIrqs         : slv(7 downto 0);

   constant IRQ_MAX_C       : natural := ite( NUM_IRQS_C > 8, 8, NUM_IRQS_C );

   signal   cpuIrqs         : slv(NUM_IRQS_C - 1 downto 0) := (others => '0');

   signal   axilWriteMaster : AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
   signal   axilReadMaster  : AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
   signal   axilWriteSlave  : AxiLiteWriteSlaveType  := AXI_LITE_WRITE_SLAVE_INIT_C;
   signal   axilReadSlave   : AxiLiteReadSlaveType   := AXI_LITE_READ_SLAVE_INIT_C;

   signal   axiWriteMaster  : AxiWriteMasterType     := AXI_WRITE_MASTER_INIT_C;
   signal   axiReadMaster   : AxiReadMasterType      := AXI_READ_MASTER_INIT_C;
   signal   axiWriteSlave   : AxiWriteSlaveType      := AXI_WRITE_SLAVE_INIT_C;
   signal   axiReadSlave    : AxiReadSlaveType       := AXI_READ_SLAVE_INIT_C;

   signal   axilReadMasters : AxiLiteReadMasterArray (NUM_AXI_SLV_C - 1 downto 0) := (others => AXI_LITE_READ_MASTER_INIT_C);
   signal   axilWriteMasters: AxiLiteWriteMasterArray(NUM_AXI_SLV_C - 1 downto 0) := (others => AXI_LITE_WRITE_MASTER_INIT_C);
   signal   axilReadSlaves  : AxiLiteReadSlaveArray  (NUM_AXI_SLV_C - 1 downto 0) := (others => AXI_LITE_READ_SLAVE_INIT_C);
   signal   axilWriteSlaves : AxiLiteWriteSlaveArray (NUM_AXI_SLV_C - 1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_INIT_C);

   signal   timingTrig      : TimingTrigType;
   signal   timingRecClk    : sl;
   signal   timingRecRst    : sl;
   signal   timingRecClkLoc : sl;

   signal   timingRxStat    : TimingPhyStatusType;
   signal   timingTxStat    : TimingPhyStatusType;

   signal   timingTxClk     : sl;

   signal   trigReg         : slv(NUM_TRIGS_G - 1 downto 0) := TIMING_TRIG_INVERT_C;
   signal   recClk2         : slv(1 downto 0) := "00";

   attribute IOB : string;
   attribute IOB of trigReg : signal is "TRUE";
   attribute IOB of recClk2 : signal is "TRUE";

begin

   assert PRJ_VARIANT_G = "deflt" or PRJ_VARIANT_G = "ibert" or PRJ_VARIANT_G = "devbd" or PRJ_VARIANT_G = "toggle" or PRJ_VARIANT = "ecevr" severity failure;

   sysRst <= not sysRstN;

   U_Sys : component processing_system7_0
      port map (
         DDR_Addr(14 downto 0)         => DDR_addr(14 downto 0),
         DDR_BankAddr(2 downto 0)      => DDR_ba(2 downto 0),
         DDR_CAS_n                     => DDR_cas_n,
         DDR_CKE                       => DDR_cke,
         DDR_CS_n                      => DDR_cs_n,
         DDR_Clk                       => DDR_ck_p,
         DDR_Clk_n                     => DDR_ck_n,
         DDR_DM(3 downto 0)            => DDR_dm(3 downto 0),
         DDR_DQ(31 downto 0)           => DDR_dq(31 downto 0),
         DDR_DQS(3 downto 0)           => DDR_dqs_p(3 downto 0),
         DDR_DQS_n(3 downto 0)         => DDR_dqs_n(3 downto 0),
         DDR_DRSTB                     => DDR_reset_n,
         DDR_ODT                       => DDR_odt,
         DDR_RAS_n                     => DDR_ras_n,
         DDR_VRN                       => FIXED_IO_ddr_vrn,
         DDR_VRP                       => FIXED_IO_ddr_vrp,
         DDR_WEB                       => DDR_we_n,
         FCLK_CLK0                     => sysClk,
         FCLK_RESET0_N                 => sysRstN,
         FCLK_RESET1_N                 => open,
         IRQ_F2P                       => cpuIrqs,
         MIO(53 downto 0)              => FIXED_IO_mio,
         M_AXI_GP0_ACLK                => sysClk,
         M_AXI_GP0_ARADDR(31 downto 0) => axiReadMaster.araddr(31 downto 0),
         M_AXI_GP0_ARBURST(1 downto 0) => axiReadMaster.arburst,
         M_AXI_GP0_ARCACHE(3 downto 0) => axiReadMaster.arcache,
         M_AXI_GP0_ARID(11 downto 0)   => axiReadMaster.arid(11 downto 0),
         M_AXI_GP0_ARLEN(3 downto 0)   => axiReadMaster.arlen(3 downto 0),
         M_AXI_GP0_ARLOCK(1 downto 0)  => axiReadMaster.arlock,
         M_AXI_GP0_ARPROT(2 downto 0)  => axiReadMaster.arprot,
         M_AXI_GP0_ARQOS(3 downto 0)   => axiReadMaster.arqos,
         M_AXI_GP0_ARREADY             => axiReadSlave.arready,
         M_AXI_GP0_ARSIZE(2 downto 0)  => axiReadMaster.arsize,
         M_AXI_GP0_ARVALID             => axiReadMaster.arvalid,
         M_AXI_GP0_AWADDR(31 downto 0) => axiWriteMaster.awaddr(31 downto 0),
         M_AXI_GP0_AWBURST(1 downto 0) => axiWriteMaster.awburst,
         M_AXI_GP0_AWCACHE(3 downto 0) => axiWriteMaster.awcache,
         M_AXI_GP0_AWID(11 downto 0)   => axiWriteMaster.awid(11 downto 0),
         M_AXI_GP0_AWLEN(3 downto 0)   => axiWriteMaster.awlen(3 downto 0),
         M_AXI_GP0_AWLOCK(1 downto 0)  => axiWriteMaster.awlock,
         M_AXI_GP0_AWPROT(2 downto 0)  => axiWriteMaster.awprot,
         M_AXI_GP0_AWQOS(3 downto 0)   => axiWriteMaster.awqos,
         M_AXI_GP0_AWREADY             => axiWriteSlave.awready,
         M_AXI_GP0_AWSIZE(2 downto 0)  => axiWriteMaster.awsize,
         M_AXI_GP0_AWVALID             => axiWriteMaster.awvalid,
         M_AXI_GP0_BID(11 downto 0)    => axiWriteSlave.bid(11 downto 0),
         M_AXI_GP0_BREADY              => axiWriteMaster.bready,
         M_AXI_GP0_BRESP(1 downto 0)   => axiWriteSlave.bresp,
         M_AXI_GP0_BVALID              => axiWriteSlave.bvalid,
         M_AXI_GP0_RDATA(31 downto 0)  => axiReadSlave.rdata(31 downto 0),
         M_AXI_GP0_RID(11 downto 0)    => axiReadSlave.rid(11 downto 0),
         M_AXI_GP0_RLAST               => axiReadSlave.rlast,
         M_AXI_GP0_RREADY              => axiReadMaster.rready,
         M_AXI_GP0_RRESP(1 downto 0)   => axiReadSlave.rresp,
         M_AXI_GP0_RVALID              => axiReadSlave.rvalid,
         M_AXI_GP0_WDATA(31 downto 0)  => axiWriteMaster.wdata(31 downto 0),
         M_AXI_GP0_WID(11 downto 0)    => axiWriteMaster.wid(11 downto 0),
         M_AXI_GP0_WLAST               => axiWriteMaster.wlast,
         M_AXI_GP0_WREADY              => axiWriteSlave.wready,
         M_AXI_GP0_WSTRB(3 downto 0)   => axiWriteMaster.wstrb(3 downto 0),
         M_AXI_GP0_WVALID              => axiWriteMaster.wvalid,
         PS_CLK                        => FIXED_IO_ps_clk,
         PS_PORB                       => FIXED_IO_ps_porb,
         PS_SRSTB                      => FIXED_IO_ps_srstb,
         USB0_PORT_INDCTL              => open,
         USB0_VBUS_PWRFAULT            => '0',
         USB0_VBUS_PWRSELECT           => open
      );

   GEN_BUFDS : for i in 1 downto 0 generate
   begin
   U_IBUFDS : component IBUFDS_GTE2
      generic map (
         CLKRCV_TRST      => true, -- ug476
         CLKCM_CFG        => true, -- ug476
         CLKSWING_CFG     => "11"  -- ug476
      )
      port map (
         I                => mgtRefClkP(i),
         IB               => mgtRefClkN(i),
         CEB              => '0',
         O                => mgtRefClk(i),
         ODIV2            => open
      );

   U_MGT_BUFG : component BUFG
      port map (
         I   => mgtRefClk(i),
         O   => mgtRefClkBuf(i)
      );
   end generate;

   G_COMM : if ( not IBERT_C ) generate

      U_OBUF_TIMING_SFP_P : component OBUF
         port map (
            I => timingSfpTxP,
            O => mgtTxP( TIMING_SFP_MGT_C )
         );
      U_OBUF_TIMING_SFP_N : component OBUF
         port map (
            I => timingSfpTxN,
            O => mgtTxN( TIMING_SFP_MGT_C )
         );
      U_IBUF_TIMING_SFP_P : component IBUF
         port map (
            I => mgtRxP( TIMING_SFP_MGT_C ),
            O => timingSfpRxP
         );
      U_IBUF_TIMING_SFP_N : component IBUF
         port map (
            I => mgtRxN( TIMING_SFP_MGT_C ),
            O => timingSfpRxN
         );

--   U_Ila_Axi : entity work.IlaAxi4SurfWrapper
--      port map (
--          axiClk                      => sysClk,
--          axiRst                      => sysRst,
--          axiReadMaster               => axiReadMaster,
--          axiReadSlave                => axiReadSlave,
--          axiWriteMaster              => axiWriteMaster,
--          axiWriteSlave               => axiWriteSlave
--      );

   GEN_ILA : if ( false ) generate
   U_Ila_Axil : entity work.IlaAxiLite
      port map (
          axilClk                => sysClk,
          mAxilRead              => axilReadMaster,
          sAxilRead              => axilReadSlave,
          mAxilWrite             => axilWriteMaster,
          sAxilWrite             => axilWriteSlave
      );
   end generate;

   U_A2A : entity work.AxiToAxiLite
      generic map (
         TPD_G            => TPD_G
      )
      port map (
         axiClk           => sysClk,
         axiClkRst        => sysRst,

         axiReadMaster    => axiReadMaster,
         axiReadSlave     => axiReadSlave,
         axiWriteMaster   => axiWriteMaster,
         axiWriteSlave    => axiWriteSlave,

         axilReadMaster   => axilReadMaster,
         axilReadSlave    => axilReadSlave,
         axilWriteMaster  => axilWriteMaster,
         axilWriteSlave   => axilWriteSlave
      );

   -------------------
   -- AXI-Lite Modules
   -------------------
   U_Reg : entity work.AppCore
      generic map (
         TPD_G                   => TPD_G,
         APP_TYPE_G              => ite( TIMING_UDP_PORT_C /= 0, "ETH", "NONE" ),
         AXIL_CLK_FREQUENCY_G    => CLK_FREQ_C,
         DHCP_G                  => true,
         JUMBO_G                 => false,
         USE_RSSI_G              => false,
         USE_JTAG_G              => false,
         USER_UDP_PORT_G         => TIMING_UDP_PORT_C,
         BUILD_INFO_G            => BUILD_INFO_G,
         XIL_DEVICE_G            => "7SERIES",
         AXIL_BASE_ADDR_G        => x"40000000",
         IP_ADDR_G               => x"410AA8C0",  -- 192.168.2.10 (ETH only)
         MAC_ADDR_G              => ETH_MAC_C,
         TPGMINI_G               => true, --(not isArtix),
         GEN_TIMING_G            => true,
         TIMING_UDP_MSG_G        => (TIMING_UDP_PORT_C /= 0),
         TIMING_GTP_HAS_COMMON_G => TIMING_GTP_HAS_COMMON_C,
         TIMING_TRIG_INVERT_G    => TIMING_TRIG_INVERT_C,
         NUM_AXIL_SLAVES_G       => NUM_AXI_SLV_C,
         NUM_TRIGS_G             => NUM_TRIGS_G
      )
      port map (
         -- Clock and Reset
         clk                  => sysClk,
         rst                  => sysRst,

         -- Ethernet Stream
         txMasters(0)         => ethTxMaster,
         txSlaves (0)         => ethTxSlave,
         rxMasters(0)         => ethRxMaster,
         rxSlaves (0)         => ethRxSlave,

         -- AXI-Lite interface
         sAxilWriteMaster     => axilWriteMaster,
         sAxilWriteSlave      => axilWriteSlave,
         sAxilReadMaster      => axilReadMaster,
         sAxilReadSlave       => axilReadSlave,

         mAxilReadMasters     => axilReadMasters,
         mAxilReadSlaves      => axilReadSlaves,
         mAxilWriteMasters    => axilWriteMasters,
         mAxilWriteSlaves     => axilWriteSlaves,

         -- Timing
         timingIb             => timingIb,
         timingOb             => timingOb,

         -- ADC Ports
         vPIn                 => '0',
         vNIn                 => '0',
         irqOut               => appIrqs,

         -- Register values
         macAddrOut           => macAddr
      );

   GEN_DEVBRD : if ( DEVBRD_C ) generate
      timingIb.refClk <= mgtRefClk( 1 );
   end generate;

   GEN_NORMAL : if ( not DEVBRD_C ) generate
      timingIb.refClk <= mgtRefClk( 0 );
   end generate;

   timingRecClk      <= timingOb.recClk;
   timingRecRst      <= timingOb.recRst;
   timingIb.RxP      <= timingSfpRxP;
   timingIb.RxN      <= timingSfpRxN;
   timingSfpTxP      <= timingOb.txP;
   timingSfpTxN      <= timingOb.txN;
   timingTrig        <= timingOb.trig;
   timingRxStat      <= timingOb.rxStat;
   timingTxStat      <= timingOb.txStat;
   timingTxClk       <= timingOb.txClk;

   GEN_TIMING_UDP : if ( TIMING_UDP_PORT_C /= 0 ) generate

      signal tiedToOne                : sl := '1';
      constant ETH_AXIS_CONFIG_C      : AxiStreamConfigArray(3 downto 0) := (others => EMAC_AXIS_CONFIG_C);

   begin

      U_OBUF_TIMING_ETH_P : component OBUF
         port map (
            I => timingEthTxP,
            O => mgtTxP( TIMING_ETH_MGT_G )
         );
      U_OBUF_TIMING_ETH_N : component OBUF
         port map (
            I => timingEthTxN,
            O => mgtTxN( TIMING_ETH_MGT_G )
         );
      U_IBUF_TIMING_ETH_P : component IBUF
         port map (
            I => mgtRxP( TIMING_ETH_MGT_G ),
            O => timingEthRxP
         );
      U_IBUF_TIMING_ETH_N : component IBUF
         port map (
            I => mgtRxN( TIMING_ETH_MGT_G ),
            O => timingEthRxN
         );

   GEN_GTX_ETH : if ( not isArtix ) generate

   U_PL_ETH_GTX : entity work.GigEthGtx7Wrapper
      generic map (
         TPD_G               => TPD_G,
         -- Clocking Configurations
         USE_GTREFCLK_G      => true, --  FALSE: gtClkP/N,  TRUE: gtRefClk
         -- AXI-Lite Configurations
         EN_AXI_REG_G        => true,
         -- AXI Streaming Configurations
         AXIS_CONFIG_G       => ETH_AXIS_CONFIG_C
      )
      port map (
         -- Local Configurations
         localMac(0)         => macAddr,
         -- Streaming DMA Interface
         dmaClk(0)           => sysClk,
         dmaRst(0)           => sysRst,
         dmaIbMasters(0)     => ethRxMaster,
         dmaIbSlaves (0)     => ethRxSlave,
         dmaObMasters(0)     => ethTxMaster,
         dmaObSlaves (0)     => ethTxSlave,
--         -- Slave AXI-Lite Interface
         axiLiteClk(0)       => sysClk,
         axiLiteRst(0)       => sysRst,
         axiLiteReadMasters(0)  => axilReadMasters(0),
         axiLiteReadSlaves(0)   => axilReadSlaves(0),
         axiLiteWriteMasters(0) => axilWriteMasters(0),
         axiLiteWriteSlaves(0)  => axilWriteSlaves(0),
         -- Misc. Signals
         extRst              => sysRst,
         phyClk              => open,
         phyRst              => open,
--         phyReady            : out slv(NUM_LANE_G-1 downto 0);
--         sigDet              : in  slv(NUM_LANE_G-1 downto 0)                     := (others => '1');
         -- MGT Clock Port (125.00 MHz or 250.0 MHz)
         gtRefClk            => mgtRefClkBuf(1),
--         gtClkP              : in  sl                                             := '1';
--         gtClkN              : in  sl                                             := '0';
         gtTxPolarity(0)     => tiedToOne,
         -- MGT Ports
         gtTxP(0)            => timingEthTxP,
         gtTxN(0)            => timingEthTxN,
         gtRxP(0)            => timingEthRxP,
         gtRxN(0)            => timingEthRxN
      );

   end generate;

   GEN_GTP_ETH : if ( isArtix ) generate
      signal qpllLocked     : slv(1 downto 0);
      signal qpllResetOut   : slv(1 downto 0);
      signal qpllRefClkLost : slv(1 downto 0);
      signal qpllRst        : slv(1 downto 0) := "00";
      signal mmcmLocked     : sl;
   begin

   timingIb.rxPllSel     <= TIMING_PLL_SEL_C;
   timingIb.txPllSel     <= TIMING_PLL_SEL_C;
   timingIb.pllLocked    <= qpllLocked    (TIMING_PLL_C );
   timingIb.refClkLost   <= qpllRefClkLost(TIMING_PLL_C );
   timingIb.pllRstRequest<= qpllResetOut;
   timingIb.debug(0)     <= mmcmLocked;
   timingIb.debug(1)     <= qpllLocked(0);
   timingIb.debug(2)     <= qpllLocked(1);
   timingIb.debug(3)     <= qpllRefClkLost(0);
   timingIb.debug(4)     <= qpllRefClkLost(1);
   qpllRst(TIMING_PLL_C) <= timingOb.pllRst;

   U_PL_ETH_GTP : entity work.GigEthGtp7WrapperAdv
      generic map (
         TPD_G               => TPD_G,
         -- Clocking Configurations
         USE_GTREFCLK_G      => true, --  FALSE: gtClkP/N,  TRUE: gtRefClk
         -- PLL1 configuration (for timing line rate and 16-bit output width)
         PLL1_FBDIV_IN_G     => 2,
         PLL1_FBDIV_45_IN_G  => 5,
         -- AXI-Lite Configurations
         PLL0_REFCLK_SEL_G   => "010", -- mgtRefClk(1) / 125MHz
         PLL1_REFCLK_SEL_G   => ite( DEVBRD_C, "010", "001" ),
         EN_AXI_REG_G        => true,
         -- AXI Streaming Configurations
         AXIS_CONFIG_G       => ETH_AXIS_CONFIG_C
      )
      port map (
         -- Local Configurations
         localMac(0)         => macAddr,
         -- Streaming DMA Interface
         dmaClk(0)           => sysClk,
         dmaRst(0)           => sysRst,
         dmaIbMasters(0)     => ethRxMaster,
         dmaIbSlaves (0)     => ethRxSlave,
         dmaObMasters(0)     => ethTxMaster,
         dmaObSlaves (0)     => ethTxSlave,
--         -- Slave AXI-Lite Interface
         axiLiteClk(0)       => sysClk,
         axiLiteRst(0)       => sysRst,
         axiLiteReadMasters(0)  => axilReadMasters(0),
         axiLiteReadSlaves(0)   => axilReadSlaves(0),
         axiLiteWriteMasters(0) => axilWriteMasters(0),
         axiLiteWriteSlaves(0)  => axilWriteSlaves(0),
         -- Misc. Signals
         extRst              => sysRst,
         phyClk              => open,
         phyRst              => open,
--         phyReady            : out slv(NUM_LANE_G-1 downto 0);
--         sigDet              : in  slv(NUM_LANE_G-1 downto 0)                     := (others => '1');
         -- MGT Clock Port (125.00 MHz or 250.0 MHz)
         gtRefClk            => mgtRefClk,
         gtRefClkBufg        => mgtRefClkBuf,
--         gtClkP              : in  sl                                             := '1';
--         gtClkN              : in  sl                                             := '0';
         mmcmLocked          => mmcmLocked,
         -- QPLL
         qpllOutClk          => timingIb.pllClk,
         qpllOutRefClk       => timingIb.pllRefClk,
         qpllLock            => qpllLocked,
         qpllRefClkLost      => qpllRefClkLost,
         qpllResetOut        => qpllResetOut,
         qpllReset           => qpllRst,
         -- Polarity
         gtTxPolarity(0)     => tiedToOne,
         -- MGT Ports
         gtTxP(0)            => timingEthTxP,
         gtTxN(0)            => timingEthTxN,
         gtRxP(0)            => timingEthRxP,
         gtRxN(0)            => timingEthRxN
      );

   end generate;

   GEN_ETH_ILA : if ( false ) generate
   U_ILA_ETH_RX : entity work.IlaAxiStream
      port map (
         axisClk         => sysClk,
         trigIn          => dbgTrig(0),
         trigInAck       => dbgTrig(1),
         trigOut         => dbgTrig(2),
         trigOutAck      => dbgTrig(3),
         mAxis           => ethRxMaster,
         sAxis           => ethRxSlave
      );

   U_ILA_ETH_TX : entity work.IlaAxiStream
      port map (
         axisClk         => sysClk,
         trigIn          => dbgTrig(2),
         trigInAck       => dbgTrig(3),
         trigOut         => dbgTrig(0),
         trigOutAck      => dbgTrig(1),
         mAxis           => ethTxMaster,
         sAxis           => ethTxSlave
      );
   end generate; -- if false

   end generate; -- if TIMING_UDP_PORT_C /= 0

   cpuIrqs(IRQ_MAX_C - 1 downto 0) <= appIrqs(IRQ_MAX_C - 1 downto 0);

   GEN_OUTBUFDS : for i in diffOutP'left - FEEDTHRU_C downto 0 generate
   begin
      U_OBUFDS : component OBUFDS
         port map (
            I   => trigReg(i),
            O   => diffOutP(i),
            OB  => diffOutN(i)
         );
   end generate;

   outClk <= timingRecClk;
   outRst <= timingRecRst;

   P_DIV_RX : process ( outClk ) is
   begin
      if rising_edge( outClk ) then
         if ( outRst = '1' ) then
            rxDiv   <= to_unsigned( 0, rxDiv'length );
            recClk2 <= "00";
         else
            rxDiv   <= rxDiv + 1;
            recClk2 <= not recClk2;
         end if;
      end if;
   end process P_DIV_RX;

   P_DIV_TX : process (timingTxClk) is
   begin
      if rising_edge( timingTxClk ) then
         txDiv <= txDiv + 1;
      end if;
   end process P_DIV_TX;


   G_COPY_CLOCKS : if ( COPY_CLOCKS_C ) generate
      P_COPY_CLOCKS : process ( outClk) is
      begin
         if ( rising_edge( outClk ) ) then
            if ( outRst = '1' ) then 
               trigReg <= TIMING_TRIG_INVERT_C;
	        else
               trigReg <= not trigReg;
            end if;
         end if;
      end process P_COPY_CLOCKS;
   end generate;

   G_NOT_COPY_CLOCKS: if ( not COPY_CLOCKS_C ) generate

      P_TRIG_REG : process ( timingTrig ) is
      begin
         trigReg <= timingTrig.trigPulse(trigReg'range);
      end process P_TRIG_REG;

   end generate;

   U_ODDR : component ODDR
      generic map (
         DDR_CLK_EDGE => "SAME_EDGE"
      )
      port map (
         C   => outClk,
         CE  => '1',
         D1  => '0', -- sample on negative clock edge
         D2  => '1',
         Q   => timingRecClkLoc,
         S   => '0',
         R   => '0'
      );

   U_RECCLKBUF : component OBUFDS
      port map (
         I  => timingRecClkLoc,
         O  => timingRecClkP,
         OB => timingRecClkN
      );

   GEN_CLK_FEEDTHRU : if ( CLK_FEEDTHRU_G ) generate
   begin

   U_RECCLKBUF17: component OBUFDS
      port map (
         I  => recClk2(0),
         O  => diffOutP(diffOutP'left),
         OB => diffOutN(diffOutN'left)
      );

   end generate;
   ----------------
   -- Misc. Signals
   ----------------

   U_RESETBUF : component IOBUF
      port map (
         I  => '0',
         IO => resetOut,
         O  => open,
         T  => '1'
      );

   U_SYNC_RX_LED : entity work.SynchronizerVector
      generic map (
         WIDTH_G => 2
      )
      port map (
         clk       => sysClk,
         rst       => sysRst,
         dataIn(0) => gpIn(0),
         dataIn(1) => rxDiv(27),
         dataOut   => rxLedData
      );

   P_RX_LED : process ( sysClk ) is
   begin

      if ( rising_edge( sysClk ) ) then

         if ( sysRst = '1' ) then
            rxLedTimer <= to_unsigned(0, rxLedTimer'length);
            rxLedState <= '0';
            rxClkState <= '0';
         else
            rxClkState <= rxLedData(1);

            if ( rxLedData(0) = '1' ) then
               -- PLL locked
               rxLedState <= '1';
               rxLedTimer <= to_unsigned(0, rxLedTimer'length);
            else
               if ( rxLedTimer /= 0 ) then
                  rxLedTimer <= rxLedTimer - 1;
               elsif ( rxLedData(1) = '1' and rxClkState = '0' ) then
                  rxLedTimer <= BLINK_TIME_UNS_C;
                  rxLedState <= '1';
               else
                  rxLedState <= '0';
               end if;
            end if;
         end if;
      end if;
   end process P_RX_LED;

   -- Green (board edge)
   -- If Si5344 locked: steady green - else blink if recovered RX clock is active
   led(0) <= rxLedState;
   -- led(0) <= sl(rxDiv(27));
   led(1) <= not timingRxStat.locked;

   -- Ethernet PHY LED[0] -- unfortunately this LED is
   -- virtually disconnected on the TE0715 module. There
   -- is a level translator (U21) with /OE tied to VCC
   -- which basically bricks it...
   -- led(2) <= gpIn(2);

   -- led(2) is the yellow lED in the ethernet connector
   led(2) <= rxDiv(27);
   -- led(3) and (4) are anti-parallel green/orange LEDs in the ethernet connector
   led(3) <= sl(txDiv(27));
   led(4) <= not sl(txDiv(27));

   end generate; -- if not IBERT_C

   GEN_IBERT : if ( IBERT_C ) generate

   U_IBERT : component ibert_7series_gt_0
      PORT MAP (
         TXN_O          => mgtTxN,
         TXP_O          => mgtTxP,
         RXOUTCLK_O     => open,
         RXN_I          => mgtRxN,
         RXP_I          => mgtRxP,
         GTREFCLK0_I(0) => mgtRefClk(0),
         GTREFCLK1_I(0) => mgtRefClk(1),
         SYSCLK_I       => sysClk
      );

  GEN_OUTBUFDS : for i in diffOutP'left - FEEDTHRU_C downto 0 generate
   begin
      U_OBUFDS : component OBUFDS
         port map (
            I   => '0',
            O   => diffOutP(i),
            OB  => diffOutN(i)
         );
   end generate;
   U_RECCLKBUF : component OBUFDS
      port map (
         I  => '0',
         O  => timingRecClkP,
         OB => timingRecClkN
      );

   end generate; -- if IBERT_C

end top_level;
