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
      NUM_SFPS_G    : natural := 2;
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

  constant NUM_IRQS_C  : natural          := 1;
  constant CLK_FREQ_C  : real             := 33.0E6;

  constant GEN_IC_C    : boolean          := false;

  constant FEEDTHRU_C  : natural          := ite( CLK_FEEDTHRU_G, 1, 0 );

--  signal   diffInp     : slv(diffInpP'range);

  signal   siClk       : sl;
  signal   siClkLoc    : sl;

  signal   outClk      : sl;

  signal   txDiv       : unsigned(27 downto 0) := to_unsigned(0, 28);
  signal   rxDiv       : unsigned(27 downto 0) := to_unsigned(0, 28);

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
   constant FIFO_DEPTH_C    : natural      := 0; -- had removed the axiVlg submodule

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
   signal   timingRecClkLoc : sl;

   signal   timingTxClk     : sl;

   signal   trigReg         : slv(NUM_TRIGS_G - 1 downto 0);
   signal   recClk2         : slv(1 downto 0) := "00";

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

   -- axiReadSlave  <= AXI_READ_SLAVE_FORCE_C;
   -- axiWriteSlave <= AXI_WRITE_SLAVE_FORCE_C;

   U_Ila_Axi : entity work.IlaAxi4SurfWrapper
      port map (
          axiClk                      => sysClk,
          axiRst                      => sysRst,
          axiReadMaster               => axiReadMaster,
          axiReadSlave                => axiReadSlave,
          axiWriteMaster              => axiWriteMaster,
          axiWriteSlave               => axiWriteSlave
      );

   U_Ila_Axil : entity work.IlaAxilSurfWrapper
      port map (
          axilClk                     => sysClk,
          axilRst                     => sysRst,
          axilReadMaster              => axilReadMaster,
          axilReadSlave               => axilReadSlave,
          axilWriteMaster             => axilWriteMaster,
          axilWriteSlave              => axilWriteSlave
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
         TPD_G            => TPD_G,
         BUILD_INFO_G     => BUILD_INFO_G,
         XIL_DEVICE_G     => "7SERIES",
         AXIL_BASE_ADDR_G => x"40000000",
         USE_SLOWCLK_G    => true,
         TPGMINI_G        => true,
         GEN_TIMING_G     => true,
         NUM_TRIGS_G      => NUM_TRIGS_G,
         FIFO_DEPTH_G     => FIFO_DEPTH_C)
      port map (
         -- Clock and Reset
         clk              => sysClk,
         rst              => sysRst,
         -- AXI-Lite interface
         axilWriteMaster  => axilWriteMaster,
         axilWriteSlave   => axilWriteSlave,
         axilReadMaster   => axilReadMaster,
         axilReadSlave    => axilReadSlave,
         -- PBRS Interface
         pbrsTxMaster     => open,
         pbrsTxSlave      => AXI_STREAM_SLAVE_FORCE_C,
         pbrsRxMaster     => AXI_STREAM_MASTER_INIT_C,
         pbrsRxSlave      => open,
         -- Microblaze stream
         mbTxMaster       => dbgTxMaster,
         mbTxSlave        => dbgTxSlave,
         mbRxMaster       => dbgRxMaster,
         mbRxSlave        => dbgRxSlave,
         -- Timing
         timingRefClkP    => mgtRefClkP(1),
         timingRefClkN    => mgtRefClkN(1),
         timingRecClk     => timingRecClk,
         timingRecRst     => open,
         timingRxP        => sfpRxP(0),
         timingRxN        => sfpRxN(0),
         timingTxP        => sfpTxP(0),
         timingTxN        => sfpTxN(0),
         timingTrig       => timingTrig,
         txRstStat        => open,
         rxRstStat        => open,
         timingTxClk      => timingTxClk,
         -- ADC Ports
         vPIn             => '0',
         vNIn             => '0',
         irqOut           => appIrqs
      );

   cpuIrqs(IRQ_MAX_C - 1 downto 0) <= appIrqs(IRQ_MAX_C - 1 downto 0);

   GEN_XVC : if XVC_EN_G generate

   U_AxisBscan : entity work.AxisDebugBridge
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
         I                => mgtRefClkP(0),
         IB               => mgtRefClkN(0),
         CEB              => '0',
         O                => siClkLoc,
         ODIV2            => open
      );

   U_BUFG_SI : component BUFG
      port map (
         I   => siClkLoc,
         O   => siClk
      );

--   outClk <= '0';
--   outClk <= siClk;
     outClk <= timingRecClk;

   P_DIV_RX : process ( outClk ) is
   begin
      if rising_edge( outClk ) then
         rxDiv   <= rxDiv + 1;
         recClk2 <= not recClk2;
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
   -- Green (board edge)
   led(0) <= gpIn(0); -- LOLb
   -- led(0) <= sl(rxDiv(27));
   led(1) <= sl(txDiv(27));
   -- Ethernet PHY LED[0]
   led(2) <= gpIn(2);
   led(3) <= '0';
   led(4) <= '0';
end top_level;
