
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Udp2BusPkg.all;
use work.Evr320ConfigPkg.all;
use work.transceiver_pkg.all;
use work.EcEvrBspPkg.all;

entity OpenEvrUdp2BusWrapper is
   generic (
      SYS_CLK_FREQ_G     : real;
      RX_POL_INVERT_G    : std_logic := '0';
      TX_POL_INVERT_G    : std_logic := '0'
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

      evrTxClk           : in  std_logic;
      evrTxData          : out std_logic_vector(15 downto 0);
      evrTxCharIsK       : out std_logic_vector( 1 downto 0);
      -- RX link status but in TXCLK domain
      -- (status must be given even if there is no stable rx clock)
      evrRxLinkOk        : out std_logic;

      mgtStatus          : in  EvrMGTStatusType;
      mgtControl         : out EvrMGTControlType;

      evrClk             : out std_logic;
      evrRst             : out std_logic;

      evrEvent           : out std_logic_vector( 7 downto 0);
      evrEventVld        : out std_logic;
      evrTimestampHi     : out std_logic_vector(31 downto 0);
      evrTimestampLo     : out std_logic_vector(31 downto 0);
      evrTimestampVld    : out std_logic;

      evrPulsers         : out std_logic_vector(NUM_PULSE_EVENTS_C  - 1 downto 0);
      evrPulsersEn       : out std_logic_vector(NUM_PULSE_EVENTS_C  - 1 downto 0);
      evrXtraDec         : out std_logic_vector(NUM_EXTRA_EVENTS_C - 1 downto 0);
      evrXtraDecEn       : out std_logic_vector(NUM_EXTRA_EVENTS_C - 1 downto 0);

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

   constant HZ_C                : natural   := natural( SYS_CLK_FREQ_G ) - 1;
   constant HZ_W_C              : natural   := numBits( HZ_C )           + 1;

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

   signal linkOkLoc             : std_logic;

   signal mgtOb                 : EvrTransceiverObType := EVR_TRANSCEIVER_OB_INIT_C;
   signal mgtIb                 : EvrTransceiverIbType := EVR_TRANSCEIVER_IB_INIT_C;

   signal bufmemData            : std_logic_vector(31 downto 0);
   signal bufmemDWAddr          : std_logic_vector(10 downto 2) := (others => '0');

   signal hzTgl                 : std_logic := '0';
   signal hzTglEvr              : std_logic := '0';
   signal hzTglEvrLst           : std_logic := '0';
   signal evrFreqCnt            : unsigned(31 downto 0)       := (others => '0');
   signal evrFreq               : unsigned(31 downto 0)       := (others => '0');
   signal hzCnt                 : signed(HZ_W_C - 1 downto 0) := to_signed( HZ_C, HZ_W_C );
   signal nxtHzCnt              : signed(HZ_W_C - 1 downto 0);

   signal cfgReqEvr             : std_logic;
   signal busReqEvr             : Udp2BusReqType;
   signal busRepEvr             : Udp2BusRepType := UDP2BUSREP_INIT_C;

   signal statusReg             : std_logic_vector(31 downto 0) := (others => '0');

   attribute KEEP               : string;

   signal cfgReqLoc             : Evr320ConfigReqType;

   -- keep this to help writing timing constraints
   attribute KEEP of cfgReqLoc  : signal is "TRUE";

begin

   cfgReqLoc                <= evrCfgReq;

   evrClk                   <= eventClkLoc;
   evrRst                   <= eventRstLoc;

   evrEvent                 <= eventCodeLoc;
   eventCodeVldLoc          <= toSl( eventCodeLoc /= EVCODE_ZERO_C );
   evrEventVld              <= eventCodeVldLoc;

   U_EVR_DC : entity work.evr_dc
      generic map (
         MARK_DEBUG_ENABLE     => "TRUE"
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
         rx_link_ok            => linkOkLoc,

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
         clk                   => eventClkLoc,
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
      evrTxClk,
      mgtStatus,
      mgtIb ) is
   begin
      mgtOb                                  <= EVR_TRANSCEIVER_OB_INIT_C;
      -- don't use DRP based delay adjustment
      -- DRP is not connected and we should/could use the PIPPM port on the GTP
      mgtOb.dly_adj                          <= NONE; -- PIPPM not implemented yet in evr_dc
      mgtOb.rx_usr_clk                       <= evrRxClk;
      mgtOb.rx_data                          <= evrRxData;
      mgtOb.rx_charisk                       <= evrRxCharIsK;
      mgtOb.rx_disperr                       <= mgtStatus.rxDispError;
      mgtOb.rx_notintable                    <= mgtStatus.rxNotIntable;
      mgtOb.rx_resetdone                     <= mgtStatus.rxResetDone;

      mgtOb.tx_usr_clk                       <= evrTxClk;
      mgtOb.tx_bufstatus                     <= mgtStatus.txBufStatus;
      mgtOb.cpll_locked                      <= mgtStatus.rxPllLocked;

      evrTxData                              <= mgtIb.tx_data;
      evrTxCharIsK                           <= mgtIb.tx_charisk;

      mgtControl                             <= EVR_MGT_CONTROL_INIT_C;
      mgtControl.rxReset                     <= mgtIb.rx_rst;
      mgtControl.txReset                     <= mgtIb.tx_rst;
      mgtControl.rxPolarityInvert            <= RX_POL_INVERT_G;
      mgtControl.txPolarityInvert            <= TX_POL_INVERT_G;
      mgtControl.rxCommaAlignDisable         <= '1';

   end process P_MGT_COMB;

   nxtHzCnt <= hzCnt - 1;

   P_HZ : process ( sysClk ) is
   begin
      if ( rising_edge( sysClk ) ) then
         if ( nxtHzCnt( nxtHzCnt'left ) = '1' ) then
            hzTgl <= not hzTgl;
            hzCnt <= to_signed( HZ_C , hzCnt'length );
         else
            hzCnt <= nxtHzCnt;
         end if;
      end if;
   end process P_HZ;

   P_HZ_SYNC_EVT : entity work.SynchronizerBit
      generic map (
         WIDTH_G   => 8
      )
      port map (
         clk                => eventClkLoc,
         rst                => '0',
         datInp(0)          => hzTgl,
         datInp(1)          => evrCfgReq.req,
         datInp(3 downto 2) => mgtStatus.rxDispError,
         datInp(5 downto 4) => mgtStatus.rxNotIntable,
         datInp(6)          => mgtStatus.rxPllLocked,
         datInp(7)          => linkOkLoc,

         datOut(0)          => hzTglEvr,
         datOut(1)          => cfgReqEvr,
         datOut(7 downto 2) => statusReg(5 downto 0)
      );

   P_FREQ_EVR : process ( eventClkLoc ) is
   begin
      if ( rising_edge( eventClkLoc ) ) then
         hzTglEvrLst <= hzTglEvr;
         if ( hzTglEvr /= hzTglEvrLst ) then
            evrFreq    <= evrFreqCnt + 1;
            evrFreqCnt <= (others => '0');
         else
            evrFreqCnt <= evrFreqCnt + 1;
         end if;
      end if;
   end process P_FREQ_EVR;

   B_REG : block is

      type RegType is record
         cfgAckTgl : std_logic;
         cfgReqLst : std_logic;
         ramVld    : std_logic;
         busReq    : Udp2BusReqType;
         pulseGens : Evr320ConfigReqType;
      end record RegType;

      constant REG_INIT_C          : RegType := (
         cfgAckTgl => '0',
         cfgReqLst => '0',
         ramVld    => '0',
         busReq    => UDP2BUSREQ_INIT_C,
         pulseGens => EVR320_CONFIG_REQ_INIT_C
      );

      signal r                     : RegType := REG_INIT_C;
      signal rin                   : RegType;

      signal cfgAckOut             : std_logic;
      signal cfgAckOutLst          : std_logic := '0';

   begin

      P_SYNC_ACK : entity work.SynchronizerBit
         port map (
            clk       => sysClk,
            rst       => '0',
            datInp(0) => r.cfgAckTgl,
            datOut(0) => cfgAckOut
         );

      P_COMB : process ( r, cfgReqEvr, cfgReqLoc, busReqEvr, bufmemData, statusReg, evrFreq ) is
         variable v      : RegType;
         variable rep    : Udp2BusRepType;
      begin
         v               := r;
         v.cfgReqLst     := cfgReqEvr;
         v.ramVld        := '0';

         v.busReq        := busReqEvr;

         rep             := UDP2BUSREP_INIT_C;
         rep.berr        := '1';
         rep.valid       := r.busReq.valid;
         rep.rdata       := bufmemData;

         bufmemDWAddr    <= r.busReq.dwaddr(8 downto 0);

         if ( ( r.busReq.valid and r.busReq.rdnwr and r.busReq.dwaddr(9)) = '1' ) then
            -- RAM read; this has 1 cycle latency
            if ( r.ramVld = '0' ) then
               v.ramVld        := '1';
            end if;
            rep.valid          := r.ramVld;
            rep.berr           := '0';
         end if;

         if ( ( r.busReq.valid and not r.busReq.dwaddr(9) ) = '1' ) then
            case ( r.busReq.dwaddr(8 downto 7) ) is
               when "00"   =>
                  if ( r.busReq.rdnwr = '1' ) then
                     rep.berr := '0';
                     case ( r.busReq.dwaddr(6 downto 0) ) is
                        when "0000000" =>
                           rep.rdata := statusReg;
                        when "0000001" =>
                           rep.rdata := std_logic_vector( evrFreq );
                        when others =>
                           rep.berr  := '1';
                     end case;
                  end if;
               when "01"   =>
                  for i in r.pulseGens.pulseGenParams'range loop
                     if ( to_integer( unsigned( r.busReq.dwaddr(6 downto 2) ) ) = i - r.pulseGens.pulseGenParams'low ) then
                        rep.berr := '0';
                        case r.busReq.dwaddr(1 downto 0) is
                           when "00" =>
                              if ( r.busReq.rdnwr = '1' ) then
                                 rep.rdata             := r.pulseGens.pulseGenParams(i).pulseWidth;
                              else
                                 v.pulseGens.pulseGenParams(i).pulseWidth := r.busReq.data;
                              end if;
                           when "01" =>
                              if ( r.busReq.rdnwr = '1' ) then
                                 rep.rdata             := r.pulseGens.pulseGenParams(i).pulseDelay;
                              else
                                 v.pulseGens.pulseGenParams(i).pulseDelay := r.busReq.data;
                              end if;
                           when "10" =>
                              if ( r.busReq.rdnwr = '1' ) then
                                 rep.rdata             := (others => '0');
                                 rep.rdata(7 downto 0) := r.pulseGens.pulseGenParams(i).pulseEvent;
                                 rep.rdata(31)         := r.pulseGens.pulseGenParams(i).pulseEnbld;
                                 rep.rdata(30)         := r.pulseGens.pulseGenParams(i).pulseInvrt;
                              else
                                 v.pulseGens.pulseGenParams(i).pulseEvent := r.busReq.data(7 downto 0);
                                 v.pulseGens.pulseGenParams(i).pulseEnbld := r.busReq.data(31);
                                 v.pulseGens.pulseGenParams(i).pulseInvrt := r.busReq.data(30);
                              end if;
                           when others =>
                              rep.berr := '1';
                        end case;
                     end if;
                  end loop;
               when "10"   =>
                  for i in r.pulseGens.extraEvents'range loop
                     if ( to_integer( unsigned( r.busReq.dwaddr(6 downto 2) ) ) = i - r.pulseGens.extraEvents'low ) then
                        rep.berr := '0';
                        case r.busReq.dwaddr(1 downto 0) is
                           when "00" =>
                              if ( r.busReq.rdnwr = '1' ) then
                                 rep.rdata             := x"0000_0001";
                              else
                                 rep.berr              := '1';
                              end if;
                           when "01" =>
                              if ( r.busReq.rdnwr = '1' ) then
                                 rep.rdata             := x"0000_0000";
                              else
                                 rep.berr              := '1';
                              end if;
                           when "10" =>
                              if ( r.busReq.rdnwr = '1' ) then
                                 rep.rdata             := (others => '0');
                                 rep.rdata(7 downto 0) := r.pulseGens.extraEvents(i);
                                 if ( r.pulseGens.extraEvents(i) /= x"00" ) then
                                    rep.rdata(31)      := '1';
                                 end if;
                              else
                                 v.pulseGens.extraEvents(i) := r.busReq.data(7 downto 0);
                              end if;
                           when others =>
                              rep.berr                 := '1';
                        end case;
                     end if;
                  end loop;
               when others =>
            end case;
         end if;

         if ( (cfgReqEvr and not r.cfgReqLst) = '1' ) then
            -- new request; ack
            v.cfgAckTgl      := not r.cfgAckTgl;
            -- CDC
            v.pulseGens      := cfgReqLoc;
         end if;

         v.pulseGens.req  := '0'; -- unused; should be optimized away

         if ( ( rep.valid and r.busReq.valid ) = '1' ) then
            v.busReq.valid := '0';
         end if;

         busRepEvr        <= rep;
         rin              <= v;

      end process P_COMB;

      P_GEN_ACK : process ( sysClk ) is
      begin
         if ( rising_edge( sysClk ) ) then
            cfgAckOutLst <= cfgAckOut;
         end if;
      end process P_GEN_ACK;

      evrCfgAck.ack <= (cfgAckOut xor cfgAckOutLst);

      P_REGS : process ( eventClkLoc ) is
      begin
         if ( rising_edge( eventClkLoc ) ) then
            r <= rin;
         end if; 
      end process P_REGS;

      G_PULSEGEN : for i in r.pulseGens.pulseGenParams'range generate
      begin

         U_PULSEGEN: entity work.EcEvrPulseGen
            generic map (
               USE_IOB_G  => "FALSE"
            )
            port map (
               clk        => eventClkLoc,
               rst        => eventRstLoc,

               event_code => eventCodeLoc,
               event_vld  => eventCodeVldLoc,

               pulse_out  => evrPulsers( i - r.pulseGens.pulseGenParams'low ),

               config     => r.pulseGens.pulseGenParams(i)
            );

         evrPulsersEn(i - r.pulseGens.pulseGenParams'low) <= r.pulseGens.pulseGenParams(i).pulseEnbld;

      end generate G_PULSEGEN;

      G_XTRA : for i in r.pulseGens.extraEvents'range generate
         constant IDX_C : integer := i - r.pulseGens.extraEvents'low;
         signal   isEn  : std_logic;
      begin

         isEn                  <= toSl( r.pulseGens.extraEvents(i) /= x"00" );
         evrXtraDecEn( IDX_C ) <= isEn;
         evrXtraDec  ( IDX_C ) <= isEn and toSl( r.pulseGens.extraEvents(i) = eventCodeLoc ) and eventCodeVldLoc;

      end generate G_XTRA;

      U_B2B : entity work.Bus2BusAsync
         port map (
            clkMst       => sysClk,
            rstMst       => open,
            reqMst       => busReq,
            repMst       => busRep,

            clkSub       => eventClkLoc,
            rstSub       => open,

            reqSub       => busReqEvr,
            repSub       => busRepEvr
         );

   end block B_REG;

   evrRxLinkOk <= linkOkLoc;

end architecture Impl;
