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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;
use work.AxiLitePkg.all;
use work.AxiPkg.all;
use work.EthMacPkg.all;
use work.TimingPkg.all;

library unisim;
use unisim.vcomponents.all;

entity TE0715 is
   generic (
      TPD_G         : time    := 1 ns;
      BUILD_INFO_G  : BuildInfoType;
      SIM_SPEEDUP_G : boolean := false;
      SIMULATION_G  : boolean := false;
      NUM_TRIGS_G   : natural := 7;
      CLK_FEEDTHRU_G: boolean := false;
      XVC_EN_G      : boolean := false;
      NUM_SFPS_G    : natural := 4; --2;
      NUM_GP_IN_G   : natural := 3;
      NUM_LED_G     : natural := 5
   );
   port (
      DDR_addr          : inout STD_LOGIC_VECTOR ( 14 downto 0 );
      DDR_ba            : inout STD_LOGIC_VECTOR ( 2 downto 0 );
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
--      diffInpP          : in  slv(0 downto 0) := (others => '0');
--      diffInpN          : in  slv(0 downto 0) := (others => '1');
      timingRecClkP     : out sl;
      timingRecClkN     : out sl;
      led               : out slv(NUM_LED_G - 1 downto 0);
      -- led[0] -> green LED, D5 (board edge)
      -- led[1] -> red LED, D4 (board edge)
      -- led[2] -> yellow LED in eth connector
      -- led[3] -> orange/anode - green/cathode in eth connector
      -- led[4] -> orange/cathode - green/anode in eth connector
--      enableSFP         : out sl := '1';
      sfpTxP            : out slv(NUM_SFPS_G - 1 downto 0);
      sfpTxN            : out slv(NUM_SFPS_G - 1 downto 0);
      sfpRxP            : in  slv(NUM_SFPS_G - 1 downto 0);
      sfpRxN            : in  slv(NUM_SFPS_G - 1 downto 0);

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

end TE0715;

architecture top_level of TE0715 is

  -- must match CONFIG.PCW_NUM_F2P_INTR_INPUTS {16} setting for IP generation
  constant NUM_IRQS_C  : natural          := 16;
  constant CLK_FREQ_C  : real             := 50.0E6;

  constant GEN_IC_C    : boolean          := false;

  constant FEEDTHRU_C  : natural          := ite( CLK_FEEDTHRU_G, 1, 0 );

  constant TIMING_UDP_PORT_C : natural    := 8197;

  constant ETH_MAC_C   : slv(47 downto 0) := x"010300564400";  -- 00:44:56:00:03:01 (ETH only)

  constant IBERT_C     : boolean          := false;

--  signal   diffInp     : slv(diffInpP'range);

  signal   siClk       : sl;
  signal   siClkLoc    : sl;

  signal   outClk      : sl;
  signal   outRst      : sl;

  signal   txDiv       : unsigned(27 downto 0) := to_unsigned(0, 28);
  signal   rxDiv       : unsigned(27 downto 0) := to_unsigned(0, 28);

  signal   rxLedData   : slv(1 downto 0);
  signal   rxLedTimer  : unsigned(27 downto 0) := to_unsigned(0, 28);
  signal   rxLedState  : sl := '0';
  signal   rxClkState  : sl := rxDiv(27);

COMPONENT ibert_7series_gtx_0
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

   signal   dbgTxMaster     : AxiStreamMasterType;
   signal   dbgTxSlave      : AxiStreamSlaveType     := AXI_STREAM_SLAVE_FORCE_C;
   signal   dbgRxMaster     : AxiStreamMasterType    := AXI_STREAM_MASTER_INIT_C;
   signal   dbgRxSlave      : AxiStreamSlaveType;

   signal   timingTrig      : TimingTrigType;
   signal   timingRecClk    : sl;
   signal   timingRecRst    : sl;
   signal   timingRecClkLoc : sl;

   signal   timingRxStat    : TimingPhyStatusType;
   signal   timingTxStat    : TimingPhyStatusType;

   signal   timingObMaster  : AxiStreamMasterType    := AXI_STREAM_MASTER_INIT_C;
   signal   timingObSlave   : AxiStreamSlaveType     := AXI_STREAM_SLAVE_FORCE_C;
   signal   timingIbMaster  : AxiStreamMasterType    := AXI_STREAM_MASTER_INIT_C;
   signal   timingIbSlave   : AxiStreamSlaveType     := AXI_STREAM_SLAVE_FORCE_C;

   signal   timingTxClk     : sl;

   signal   trigReg         : slv(NUM_TRIGS_G - 1 downto 0);
   signal   recClk2         : slv(1 downto 0) := "00";

   signal   refClkDbg       : slv(1 downto 0);

   attribute IOB : string;
   attribute IOB of trigReg : signal is "TRUE";
   attribute IOB of recClk2 : signal is "TRUE";

begin

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

   G_COMM : if ( not IBERT_C ) generate

   -- axiReadSlave  <= AXI_READ_SLAVE_FORCE_C;
   -- axiWriteSlave <= AXI_WRITE_SLAVE_FORCE_C;

--   U_Ila_Axi : entity work.IlaAxi4SurfWrapper
--      port map (
--          axiClk                      => sysClk,
--          axiRst                      => sysRst,
--          axiReadMaster               => axiReadMaster,
--          axiReadSlave                => axiReadSlave,
--          axiWriteMaster              => axiWriteMaster,
--          axiWriteSlave               => axiWriteSlave
--      );

   U_Ila_Axil : entity work.IlaAxiLite
      port map (
          axilClk                => sysClk,
          mAxilRead              => axilReadMaster,
          sAxilRead              => axilReadSlave,
          mAxilWrite             => axilWriteMaster,
          sAxilWrite             => axilWriteSlave
      );

   GEN_INTERCONNECT : if ( GEN_IC_C ) generate

   begin

     U_A2A : entity work.Axi4ToAxilSurfWrapper
        port map (
          axiClk                      => sysClk,
          axiRst                      => sysRst,

          axiReadMaster               => axiReadMaster,
          axiReadSlave                => axiReadSlave,
          axiWriteMaster              => axiWriteMaster,
          axiWriteSlave               => axiWriteSlave,

          axilReadMaster              => axilReadMaster,
          axilReadSlave               => axilReadSlave,
          axilWriteMaster             => axilWriteMaster,
          axilWriteSlave              => axilWriteSlave
        );

   end generate;


   GEN_AXI_2_AXILITE : if ( not GEN_IC_C ) generate

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

   end generate;

   -------------------
   -- AXI-Lite Modules
   -------------------
   U_Reg : entity work.AppReg
      generic map (
         TPD_G                => TPD_G,
         BUILD_INFO_G         => BUILD_INFO_G,
         XIL_DEVICE_G         => "7SERIES",
         AXIL_BASE_ADDR_G     => x"40000000",
         USE_SLOWCLK_G        => true,
         TPGMINI_G            => true,
         GEN_TIMING_G         => true,
         TIMING_UDP_MSG_G     => true,
         NUM_TRIGS_G          => NUM_TRIGS_G
      )
      port map (
         -- Clock and Reset
         clk                  => sysClk,
         rst                  => sysRst,
         -- AXI-Lite interface
         axilWriteMaster      => axilWriteMaster,
         axilWriteSlave       => axilWriteSlave,
         axilReadMaster       => axilReadMaster,
         axilReadSlave        => axilReadSlave,
         -- PBRS Interface
         pbrsTxMaster         => open,
         pbrsTxSlave          => AXI_STREAM_SLAVE_FORCE_C,
         pbrsRxMaster         => AXI_STREAM_MASTER_INIT_C,
         pbrsRxSlave          => open,
         -- Microblaze stream
         mbTxMaster           => dbgTxMaster,
         mbTxSlave            => dbgTxSlave,
         mbRxMaster           => dbgRxMaster,
         mbRxSlave            => dbgRxSlave,
         -- Timing
         timingRefClkP        => mgtRefClkP(0),
         timingRefClkN        => mgtRefClkN(0),
         timingRecClk         => timingRecClk,
         timingRecRst         => timingRecRst,
         timingRxP            => sfpRxP(0),
         timingRxN            => sfpRxN(0),
         timingTxP            => sfpTxP(0),
         timingTxN            => sfpTxN(0),
         timingTrig           => timingTrig,
         timingRxStat         => timingRxStat,
         timingTxStat         => timingTxStat,
         timingTxClk          => timingTxClk,
         ibTimingEthMsgMaster => timingIbMaster,
         ibTimingEthMsgSlave  => timingIbSlave,
         obTimingEthMsgMaster => timingObMaster,
         obTimingEthMsgSlave  => timingObSlave,
         -- ADC Ports
         vPIn                 => '0',
         vNIn                 => '0',
         irqOut               => appIrqs
      );

   GEN_TIMING_UDP : if ( TIMING_UDP_PORT_C /= 0 ) generate

      signal ethTxMaster, ethRxMaster : AxiStreamMasterType;
      signal ethTxSlave , ethRxSlave  : AxiStreamSlaveType;

   begin

   U_PL_ETH_GTX : entity work.GigEthGtx7Wrapper
      generic map (
         TPD_G               => TPD_G,
         -- Clocking Configurations
         USE_GTREFCLK_G      => true, --  FALSE: gtClkP/N,  TRUE: gtRefClk
         -- AXI-Lite Configurations
         EN_AXI_REG_G        => false,
         -- AXI Streaming Configurations
         AXIS_CONFIG_G       => (others => EMAC_AXIS_CONFIG_C)
      )
      port map (
         -- Local Configurations
         localMac(0)         => ETH_MAC_C,
         -- Streaming DMA Interface
         dmaClk(0)           => sysClk,
         dmaRst(0)           => sysRst,
         dmaIbMasters(0)     => ethTxMaster,
         dmaIbSlaves (0)     => ethTxSlave,
         dmaObMasters(0)     => ethRxMaster,
         dmaObSlaves (0)     => ethRxSlave,
--         -- Slave AXI-Lite Interface
--         axiLiteClk          : in  slv(NUM_LANE_G-1 downto 0)                     := (others => '0');
--         axiLiteRst          : in  slv(NUM_LANE_G-1 downto 0)                     := (others => '0');
--         axiLiteReadMasters  : in  AxiLiteReadMasterArray(NUM_LANE_G-1 downto 0)  := (others => AXI_LITE_READ_MASTER_INIT_C);
--         axiLiteReadSlaves   : out AxiLiteReadSlaveArray(NUM_LANE_G-1 downto 0);
--         axiLiteWriteMasters : in  AxiLiteWriteMasterArray(NUM_LANE_G-1 downto 0) := (others => AXI_LITE_WRITE_MASTER_INIT_C);
--         axiLiteWriteSlaves  : out AxiLiteWriteSlaveArray(NUM_LANE_G-1 downto 0);
         -- Misc. Signals
         extRst              => sysRst,
         phyClk              => open,
         phyRst              => open,
--         phyReady            : out slv(NUM_LANE_G-1 downto 0);
--         sigDet              : in  slv(NUM_LANE_G-1 downto 0)                     := (others => '1');
         -- MGT Clock Port (125.00 MHz or 250.0 MHz)
         gtRefClk            => siClk,
--         gtClkP              : in  sl                                             := '1';
--         gtClkN              : in  sl                                             := '0';
         -- MGT Ports
         gtTxP(0)            => sfpTxP(1),
         gtTxN(0)            => sfpTxN(1),
         gtRxP(0)            => sfpRxP(1),
         gtRxN(0)            => sfpRxN(1)
      );

   U_PL_ETH : entity work.EthPortMapping
      generic map (
         TPD_G           => TPD_G,
         CLK_FREQUENCY_G => 125.0E+6,
         MAC_ADDR_G      => ETH_MAC_C,
         IP_ADDR_G       => x"0A02A8C0",  -- 192.168.2.10 (ETH only)
         DHCP_G          => true,
         JUMBO_G         => false,
         USE_RSSI_G      => false,
         USE_JTAG_G      => false,
         USER_UDP_PORT_G => TIMING_UDP_PORT_C
      )
      port map (
         -- Clock and Reset
         clk             => sysClk,
         rst             => sysRst,
         -- ETH interface
         txMaster        => ethTxMaster,
         txSlave         => ethTxSlave,
         rxMaster        => ethRxMaster,
         rxSlave         => ethRxSlave,
--         rxCtrl          : out AxiStreamCtrlType; -- unused
--         -- PBRS Interface
--         pbrsTxMaster    : in  AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
--         pbrsTxSlave     : out AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C;
--         pbrsRxMaster    : out AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
--         pbrsRxSlave     : in  AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C;
--         -- HLS Interface
--         hlsTxMaster     : in  AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
--         hlsTxSlave      : out AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C;
--         hlsRxMaster     : out AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
--         hlsRxSlave      : in  AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C;
--         -- MB Interface
--         mbTxMaster      : in  AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
--         mbTxSlave       : out AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C;
         -- raw UDP Interface
         udpTxMaster     => timingObMaster,
         udpTxSlave      => timingObSlave,
         udpRxMaster     => timingIbMaster,
         udpRxSlave      => timingIbSlave
--         -- AXI-Lite MASTER Interface
--         axilWriteMaster : out AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
--         axilWriteSlave  : in  AxiLiteWriteSlaveType  := AXI_LITE_WRITE_SLAVE_INIT_C;
--         axilReadMaster  : out AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
--         axilReadSlave   : in  AxiLiteReadSlaveType   := AXI_LITE_READ_SLAVE_INIT_C
      );

   end generate; -- if TIMING_UDP_PORT_C /= 0

   cpuIrqs(IRQ_MAX_C - 1 downto 0) <= appIrqs(IRQ_MAX_C - 1 downto 0);

   GEN_XVC : if XVC_EN_G generate

   U_AxisBscan : entity work.AxisJtagDebugBridge
      generic map (
         TPD_G        => TPD_G,
         AXIS_WIDTH_G => 4,
         AXIS_FREQ_G  => CLK_FREQ_C,
         CLK_DIV2_G   => 5,
         MEM_DEPTH_G  => (2048/EMAC_AXIS_CONFIG_C.TDATA_BYTES_C)
      )
      port map (
         axisClk      => sysClk,
         axisRst      => sysRst,

         mAxisReq     => dbgTxMaster,
         sAxisReq     => dbgTxSlave,

         mAxisTdo     => dbgRxMaster,
         sAxisTdo     => dbgRxSlave
      );

   end generate;

   GEN_OUTBUFDS : for i in diffOutP'left - FEEDTHRU_C downto 0 generate
   begin
      U_OBUFDS : component OBUFDS
         port map (
            I   => trigReg(i),
            O   => diffOutP(i),
            OB  => diffOutN(i)
         );
   end generate;

   U_IBUFDS : component IBUFDS_GTE2
      generic map (
         CLKRCV_TRST      => true, -- ug476
         CLKCM_CFG        => true, -- ug476
         CLKSWING_CFG     => "11"  -- ug476
      )
      port map (
         I                => mgtRefClkP(1),
         IB               => mgtRefClkN(1),
         CEB              => '0',
         O                => siClkLoc,
         ODIV2            => open
      );

   U_BUFG_SI : component BUFG
      port map (
         I   => siClkLoc,
         O   => siClk
      );

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



   P_TRIG_REG : process ( timingTrig ) is
   begin
--      if ( rising_edge( outClk ) ) then
         trigReg <= timingTrig.trigPulse(trigReg'range);
--      end if;
   end process P_TRIG_REG;

   U_ODDR : component ODDR
      generic map (
         DDR_CLK_EDGE => "SAME_EDGE"
      )
      port map (
         C   => outClk,
         CE  => '1',
         D1  => '0', -- sample on negative clock edge; FIXME should use MMCM and variable phase shift!
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
               elsif ( rxDiv(27) = '1' and rxClkState = '0' ) then
                  rxLedTimer <= to_unsigned(10000000, rxLedTimer'length); -- 0.2s
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
   led(2) <= '0';
   -- led(3) and (4) are anti-parallel green/orange LEDs in the ethernet connector
   led(3) <= sl(txDiv(27));
   led(4) <= not sl(txDiv(27));

   end generate; -- if not IBERT_C

   GEN_IBERT : if ( IBERT_C ) generate

   GEN_BUFS : for i in 1 downto 0 generate
     signal wxx : sl;
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
         O                => refClkDbg(i),
         ODIV2            => open
      );

--   U_BUFG_SI : component BUFG
--      port map (
--         I   => wxx,
--         O   => refClkDbg(i)
--      );
   end generate;

   your_instance_name : ibert_7series_gtx_0
  PORT MAP (
    TXN_O => sfpTxN,
    TXP_O => sfpTxP,
    RXOUTCLK_O => open,
    RXN_I => sfpRxN,
    RXP_I => sfpRxP,
    GTREFCLK0_I(0) => refClkDbg(0),
    GTREFCLK1_I(0) => refClkDbg(1),
    SYSCLK_I => sysClk
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

   end generate;

end top_level;
