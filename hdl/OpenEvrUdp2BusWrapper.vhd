
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Udp2BusPkg.all;
use work.Evr320ConfigPkg.all;
use work.transceiver_pkg.all;

entity OpenEvrUdp2BusWrapper is
   generic (
      NUM_TRIGS_G        : natural := 8
   );
   port (
      sysClk             : in  std_logic;
      sysRst             : in  std_logic;

      busReq             : in  Udp2BusReqType;
      busRep             : out Udp2BusRepType;

      evrCfgReq          : in  Evr320ConfigReqType := EVR320_CONFIG_REQ_INIT_C;
      evrCfgAck          : out Evr320ConfigAckType;

      evrRxClk           : in  std_logic;
      evrRxData          : in  std_logic_vector(15 downto 0);
      evrRxCharIsK       : in  std_logic_vector( 1 downto 0);
      evrRxDispErr       : in  std_logic_vector( 1 downto 0);
      evrRxNotIntable    : in  std_logic_vector( 1 downto 0);

      evrTxClk           : in  std_logic;
      evrTxData          : out std_logic_vector(15 downto 0);
      evrTxCharIsK       : out std_logic_vector( 1 downto 0);

      mgtStatus          : in  std_logic_vector(31 downto 0);
      mgtControl         : out std_logic_vector(31 downto 0);

      evrClk             : out std_logic;
      evrRst             : out std_logic;

      evrEvent           : out std_logic_vector( 7 downto 0);
      evrEventVld        : out std_logic;
      evrTimestampHi     : out std_logic_vector(31 downto 0);
      evrTimestampLo     : out std_logic_vector(31 downto 0);
      evrTimestampVld    : out std_logic;

      evrTriggers        : out std_logic_vector(NUM_TRIGS_G - 1 downto 0);
      evrTriggersEn      : out std_logic_vector(NUM_TRIGS_G - 1 downto 0);

      evrStreamVld       : out std_logic;
      evrStreamAddr      : out std_logic_vector(10 downto 0);
      evrStreamData      : out std_logic_vector( 7 downto 0)
   );
end entity OpenEvrUdp2BusWrapper;

architecture Impl of OpenEvrUdp2BusWrapper is
   constant EVCODE_ZERO_C       : std_logic_vector( 7 downto 0) := x"00";
   constant DBUS_ZERO_C         : std_logic_vector( 7 downto 0) := x"00";
   constant DBUF_ENA_C          : std_logic := '1';
   constant DC_MODE_ENA_C       : std_logic := '1';
   constant DC_MODE_DIS_C       : std_logic := '0';
   constant Z128_C              : std_logic_vector(127 downto 0) := (others => '0');

   signal eventClkLoc           : std_logic;
   signal eventRstLoc           : std_logic;
   signal eventCodeLoc          : std_logic_vector( 7 downto 0);
   signal eventCodeVldLoc       : std_logic;

   signal dbufData              : std_logic_vector( 7 downto 0);
   signal dbufIsK               : std_logic;
   signal dbufVld               : std_logic;

   signal evrTxClkLoc           : std_logic;
   signal evrTxRstLoc           : std_logic;

   signal dcUpdate              : std_logic := '0';
   signal dcValue               : std_logic_vector(31 downto 0) := (others => '0');
   signal dcStatus              : std_logic_vector(31 downto 0) := (others => '0');
   signal dcTopo                : std_logic_vector(31 downto 0) := (others => '0');
   signal dcTarget              : std_logic_vector(31 downto 0) := (others => '0');
   signal dcLocked              : std_logic := '0';

   signal mgtOb                 : EvrTransceiverObType := EVR_TRANSCEIVER_OB_INIT_C;
   signal mgtIb                 : EvrTransceiverIbType := EVR_TRANSCEIVER_IB_INIT_C;

   signal bufmemData            : std_logic_vector(31 downto 0);
   signal bufmemDWAddr          : std_logic_vector(10 downto 2) := (others => '0');
begin

   evrClk                   <= eventClkLoc;
   evrRst                   <= eventRstLoc;

   evrEvent                 <= eventCodeLoc;
   eventCodeVldLoc          <= toSl( eventCodeLoc /= EVCODE_ZERO_C );
   evrEventVld              <= eventCodeVldLoc;
 
   U_EVR_DC : entity work.evr_dc
      generic map (
         MARK_DEBUG_ENABLE     => "FALSE"
      )
      port map (
         -- System bus clock
         sys_clk               => sysClk,
         reset                 => sysRst,

         -- flags (sys_clk domain)
         rx_violation          => open,
         rx_clear_viol         => '0',

         -- Event clock output, delay compensated
         event_clk_out         => eventClkLoc,
         event_clk_rst         => eventRstLoc,

         -- Receiver side connections (event_clk domain)
         event_rxd             => eventCodeLoc,
         dbus_rxd              => open,

         databuf_rxd           => dbufData,
         databuf_rx_k          => dbufIsK,
         databuf_rx_ena        => dbufVld,
         databuf_rx_mode       => DBUF_ENA_C,

         -- Transmitter side connections
         refclk_out            => evrTxClkLoc,
         refclk_rst            => evrTxRstLoc,

         dc_mode               => DC_MODE_DIS_C,
           
         -- flags (refclk domain)
         rx_link_ok            => open, --: out   std_logic; -- Received link ok

         event_txd             => EVCODE_ZERO_C,
         dbus_txd              => DBUS_ZERO_C,
         databuf_txd           => DBUS_ZERO_C,
         databuf_tx_k          => '0',
         databuf_tx_ena        => open,
         databuf_tx_mode       => '0',

         -- Delay compensation signals
         delay_comp_update     => dcUpdate,
         delay_comp_value      => dcValue,
         delay_comp_target     => dcTarget,
         delay_comp_locked_out => dcLocked,

         transceiverOb         => mgtOb,
         transceiverIb         => mgtIb
      );

   U_DBUF_RX : entity work.databuf_rx_dc
      generic map (
         MARK_DEBUG_ENABLE     => "FALSE"
      )
      port map (
         -- Memory buffer RAMB read interface (clk domain)
         clk                   => sysClk,
         data_out              => bufmemData,
         size_data_out         => open,
         addr_in               => bufmemDWAddr,
         
         -- Data stream interface (event_clk domain)
         event_clk             => eventClkLoc,
         databuf_data          => dbufData,
         databuf_k             => dbufIsK,
         databuf_ena           => dbufVld,

         -- Databuf outbound stream interface;
         -- someone may be interested in picking out snippets of
         -- the databuf as it is streamed into the memory
         databuf_strm_data     => evrStreamData,
         databuf_strm_addr     => evrStreamAddr,
         databuf_strm_vld      => evrStreamVld,

         delay_comp_update     => dcUpdate,
         delay_comp_rx         => dcValue,
         delay_comp_status     => dcStatus,
         topology_addr         => dcTopo,

         -- Control interface (clk domain)
         irq_out               => open,
         sirq_ena              => Z128_C,

         -- Control interface (event_clk domain)
         rx_flag               => open, --  128 bit vector
         cs_flag               => open, --  128 bit vector
         ov_flag               => open, --  128 bit vector
         clear_flag            => Z128_c,
         reset                 => eventRstLoc
      );

   P_MGT_COMB : process (
      evrRxClk,
      evrRxData,
      evrRxCharIsK,
      evrRxDispErr,
      evrRxNotIntable,
      evrTxClk,
      mgtStatus,
      mgtIb ) is
   begin
      mgtOb                 <= EVR_TRANSCEIVER_OB_INIT_C;
      mgtOb.rx_usr_clk      <= evrRxClk;
      mgtOb.rx_data         <= evrRxData;
      mgtOb.rx_charisk      <= evrRxCharIsK;
      mgtOb.rx_disperr      <= evrRxDispErr;
      mgtOb.rx_notintable   <= evrRxNotIntable;

      mgtOb.tx_usr_clk      <= evrTxClk;
      mgtOb.cpll_locked     <= mgtStatus(1);

      evrTxData             <= mgtIb.tx_data;
      evrTxCharIsK          <= mgtIb.tx_charisk;

      mgtControl            <= (others => '0');
   end process P_MGT_COMB;

end architecture Impl;
