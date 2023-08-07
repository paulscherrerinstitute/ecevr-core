
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Udp2BusPkg.all;
use work.Evr320ConfigPkg.all;
use work.transceiver_pkg.all;
use work.EcEvrBspPkg.all;
use work.IlaWrappersPkg.all;

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
      evrStreamData      : out std_logic_vector( 7 downto 0);

      mmcm_locked        : out std_logic
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

   signal dcMode                : std_logic := DC_MODE_DIS_C;
   signal dcUpdate              : std_logic := '0';
   signal dcValue               : std_logic_vector(31 downto 0) := (others => '0');
   signal dcStatus              : std_logic_vector(31 downto 0) := (others => '0');
   signal dcTopo                : std_logic_vector(31 downto 0) := (others => '0');
   signal dcTarget              : std_logic_vector(31 downto 0) := (others => '0');
   signal dcLocked              : std_logic := '0';
   signal dcMeasInp             : std_logic_vector(31 downto 0);
   signal dcMeas                : std_logic_vector(31 downto 0);

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

   signal evrStreamVldLoc       : std_logic;
   signal evrStreamAddrLoc      : std_logic_vector(10 downto 0);
   signal evrStreamDataLoc      : std_logic_vector( 7 downto 0);


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

         dc_mode               => dcMode,
         delay_meas_value      => dcMeasInp,

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
         transceiverIb         => mgtIb,

         mmcm_locked           => mmcm_locked
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
         databuf_strm_data     => evrStreamDataLoc,
         databuf_strm_addr     => evrStreamAddrLoc,
         databuf_strm_vld      => evrStreamVldLoc,

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

   G_DBUF_ILA : if ( true ) generate
   begin

      U_ILA : Ila_256
         port map (
            clk                  => eventClkLoc,
            probe0(10 downto  0) => evrStreamAddrLoc,
            probe0(11          ) => evrStreamVldLoc,
            probe0(19 downto 12) => evrStreamDataLoc,
            probe0(27 downto 20) => dbufData,
            probe0(28          ) => dbufIsK,
            probe0(29          ) => dbufVld,
            probe0(63 downto 30) => (others => '0'),

            probe1( 8 downto  0) => bufmemDWAddr,
            probe1( 9          ) => busReqEvr.dwaddr(9),
            probe1(10          ) => busReqEvr.valid,
            probe1(11          ) => busReqEvr.rdnwr,
            probe1(12          ) => busRepEvr.valid,
            probe1(13          ) => busRepEvr.berr,
            probe1(31 downto 14) => (others => '0'),
            probe1(63 downto 32) => bufmemData,

            probe2(31 downto  0) => busRepEvr.rdata,
            probe2(63 downto 32) => busReqEvr.data,

            probe3               => (others => '0')
         );

   end generate G_DBUF_ILA;

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
      -- DRP is not connected and we should/could use the PIPPM port on the GTP.
      -- Currently the GTP is configured for TX buffer-bypass mode which should
      -- be fine for ordinary use cases.
      -- If higher precision is ever required then
      --  - the PIPPM port needs to be enabled
      --  - the TX buffer needs to be enabled
      --  - openevr transceiver_dc must support PIPPM (is actually easier than using DRP
      --    and the implementation should be straightforward / derived from the DRP one)
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
         WIDTH_G   => 9
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
         datInp(8)          => dcLocked,

         datOut(0)          => hzTglEvr,
         datOut(1)          => cfgReqEvr,
         datOut(8 downto 2) => statusReg(6 downto 0)
      );

   statusReg(24)            <= dcMode;

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

      procedure wr32(
         variable v : inout std_logic_vector(31 downto 0);
         constant q : in    Udp2BusReqType
      ) is
      begin
         v := v;
         for i in q.be'range loop
            if ( q.be(i) = '1' ) then
               v(8*i + 7 downto 8*i) := q.data(8*i + 7 downto 8*i);
            end if;
         end loop;
      end procedure wr32;

      type RegType is record
         cfgAckTgl : std_logic;
         cfgReqLst : std_logic;
         ramVld    : std_logic;
         dcTarget  : std_logic_vector(31 downto 0);
         dcMode    : std_logic;
         pulseGens : Evr320ConfigReqType;
      end record RegType;

      constant REG_INIT_C          : RegType := (
         cfgAckTgl => '0',
         cfgReqLst => '0',
         ramVld    => '0',
         dcMode    => '0',
         dcTarget  => (others => '0'),
         pulseGens => EVR320_CONFIG_REQ_INIT_C
      );

      signal r                     : RegType := REG_INIT_C;
      signal rin                   : RegType;

      signal cfgAckOut             : std_logic;
      signal cfgAckOutLst          : std_logic := '0';

   begin

      P_SYNC_TXCLK_2_EVTCLK : entity work.SynchronizerVec
         generic map (
            W_A2B_G => dcMeasInp'length
         )
         port map (
            clkA    => evrTxClkLoc,
            dinA    => dcMeasInp,
            clkB    => eventClkLoc,
            douB    => dcMeas
         );

      P_SYNC_EVTCLK_2_SYSCLK : entity work.SynchronizerVec
         generic map (
            W_A2B_G => dcTarget'length
         )
         port map (
            clkA    => eventClkLoc,
            dinA    => r.dcTarget,
            clkB    => sysClk,
            douB    => dcTarget
         );

      P_SYNC_ACK : entity work.SynchronizerBit
         port map (
            clk       => sysClk,
            rst       => '0',
            datInp(0) => r.cfgAckTgl,
            datOut(0) => cfgAckOut
         );

      P_COMB : process (
         r,
         cfgReqEvr, cfgReqLoc,
         busReqEvr,
         bufmemData,
         statusReg,
         evrFreq,
         dcMeas,
         dcValue,
         dcStatus,
         dcTarget,
         dcTopo
       ) is
         variable v      : RegType;
         variable rep    : Udp2BusRepType;
      begin
         v               := r;
         v.cfgReqLst     := cfgReqEvr;
         v.ramVld        := '0';

         rep             := UDP2BUSREP_INIT_C;
         rep.berr        := '1';
         rep.valid       := busReqEvr.valid;
         rep.rdata       := bufmemData;

         bufmemDWAddr    <= busReqEvr.dwaddr(8 downto 0);

         if ( ( busReqEvr.valid and busReqEvr.rdnwr and busReqEvr.dwaddr(9) ) = '1' ) then
            -- RAM read; this has 1 cycle latency
            if ( r.ramVld = '0' ) then
               v.ramVld        := '1';
            end if;
            rep.valid          := r.ramVld;
            rep.berr           := '0';
         end if;

         if ( ( busReqEvr.valid and not busReqEvr.dwaddr(9) ) = '1' ) then
            case ( busReqEvr.dwaddr(8 downto 7) ) is
               when "00"   =>
                  if ( busReqEvr.rdnwr = '1' ) then
                     rep.berr := '0';
                     case ( busReqEvr.dwaddr(6 downto 0) ) is
                        when "0000000" =>
                           rep.rdata := statusReg;
                        when "0000001" =>
                           rep.rdata := std_logic_vector( evrFreq );
                        when "0000010" =>
                           rep.rdata := dcMeas;
                        when "0000011" =>
                           rep.rdata := dcValue;
                        when "0000100" =>
                           rep.rdata := dcStatus;
                        when "0000101" =>
                           rep.rdata := dcTopo;
                        when "0000110" =>
                           rep.rdata := r.dcTarget;
                        when others =>
                           rep.berr  := '1';
                     end case;
                  else
                     rep.berr := '0';
                     case ( busReqEvr.dwaddr(6 downto 0) ) is
                        when "0000000" =>
                           if ( busReqEvr.be(3) = '1' ) then
                              v.dcMode := busReqEvr.data(24);
                           end if;
                        when "0000110" =>
                           wr32( v.dcTarget, busReqEvr );
                        when others =>
                           rep.berr  := '1';
                     end case;
                  end if;
               when "01"   =>
                  for i in r.pulseGens.pulseGenParams'range loop
                     if ( to_integer( unsigned( busReqEvr.dwaddr(6 downto 2) ) ) = i - r.pulseGens.pulseGenParams'low ) then
                        rep.berr := '0';
                        case busReqEvr.dwaddr(1 downto 0) is
                           when "00" =>
                              if ( busReqEvr.rdnwr = '1' ) then
                                 rep.rdata             := r.pulseGens.pulseGenParams(i).pulseWidth;
                              else
                                 wr32( v.pulseGens.pulseGenParams(i).pulseWidth, busReqEvr);
                              end if;
                           when "01" =>
                              if ( busReqEvr.rdnwr = '1' ) then
                                 rep.rdata             := r.pulseGens.pulseGenParams(i).pulseDelay;
                              else
                                 wr32( v.pulseGens.pulseGenParams(i).pulseDelay, busReqEvr);
                              end if;
                           when "10" =>
                              if ( busReqEvr.rdnwr = '1' ) then
                                 rep.rdata             := (others => '0');
                                 rep.rdata(7 downto 0) := r.pulseGens.pulseGenParams(i).pulseEvent;
                                 rep.rdata(31)         := r.pulseGens.pulseGenParams(i).pulseEnbld;
                                 rep.rdata(30)         := r.pulseGens.pulseGenParams(i).pulseInvrt;
                              else
                                 if ( busReqEvr.be(0) = '1' ) then
                                    v.pulseGens.pulseGenParams(i).pulseEvent := busReqEvr.data(7 downto 0);
                                 end if;
                                 if ( busReqEvr.be(3) = '1' ) then
                                    v.pulseGens.pulseGenParams(i).pulseEnbld := busReqEvr.data(31);
                                    v.pulseGens.pulseGenParams(i).pulseInvrt := busReqEvr.data(30);
                                 end if;
                              end if;
                           when others =>
                              rep.berr := '1';
                        end case;
                     end if;
                  end loop;
               when "10"   =>
                  for i in r.pulseGens.extraEvents'range loop
                     if ( to_integer( unsigned( busReqEvr.dwaddr(6 downto 2) ) ) = i - r.pulseGens.extraEvents'low ) then
                        rep.berr := '0';
                        case busReqEvr.dwaddr(1 downto 0) is
                           when "00" =>
                              if ( busReqEvr.rdnwr = '1' ) then
                                 rep.rdata             := x"0000_0001";
                              else
                                 rep.berr              := '1';
                              end if;
                           when "01" =>
                              if ( busReqEvr.rdnwr = '1' ) then
                                 rep.rdata             := x"0000_0000";
                              else
                                 rep.berr              := '1';
                              end if;
                           when "10" =>
                              if ( busReqEvr.rdnwr = '1' ) then
                                 rep.rdata             := (others => '0');
                                 rep.rdata(7 downto 0) := r.pulseGens.extraEvents(i);
                                 if ( r.pulseGens.extraEvents(i) /= x"00" ) then
                                    rep.rdata(31)      := '1';
                                 end if;
                              else
                                 if ( busReqEvr.be(0) = '1' ) then
                                    v.pulseGens.extraEvents(i) := busReqEvr.data(7 downto 0);
                                 end if;
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

         busRepEvr        <= rep;
         rin              <= v;
         dcMode           <= r.dcMode;

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

   evrRxLinkOk        <= linkOkLoc;

   evrStreamAddr      <= evrStreamAddrLoc;
   evrStreamVld       <= evrStreamVldLoc;
   evrStreamData      <= evrStreamDataLoc;

end architecture Impl;
