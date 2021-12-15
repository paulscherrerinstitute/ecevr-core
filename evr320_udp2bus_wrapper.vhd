 ---------------------------------------------------------------------------
--                       Paul Scherrer Institute (PSI)
-- ---------------------------------------------------------------------------
-- Unit    : evr320_udp2bus_wrapper.vhd
-- Author  : Patric Bucher, Benoit Stef, Till Straumann
-- ---------------------------------------------------------------------------
-- Copyright© PSI, Section DSV
-- ---------------------------------------------------------------------------
-- Comment : Wraps evr320 decoder together with UDP2BUS registers.
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.evr320_pkg.all;
use work.Udp2BusPkg.all;
use work.Evr320ConfigPkg.all;

entity evr320_udp2bus_wrapper is
  generic(
    g_BUS_CLOCK_FREQ : natural   := 125000000;    -- Xuser Clk Frequency in Hz
    g_EVENT_RECORDER : boolean   := false;        -- enable/disable Event Recorder functionality
    g_DATA_MEMORY_EN : boolean   := true;         -- enable DPRAM data buffer
    g_N_EVT_DBL_BUFS : natural range 0 to 4 := 4; -- how many double-buffered memories to enable
    g_DATA_STREAM_EN : natural range 0 to 2 := 2; -- enable streaming interface (1) with fifo (2)
    g_EVR_FORCE_STBL : std_logic := '0';          -- when '1': force 'evr_stable' <= '1'
    g_MAX_LATCNT_PER : real      := 0.01;         -- max. period for latency counter; 0.0 never stops
    g_CS_TIMEOUT_CNT : natural   := 16#15CA20#;   -- data frame checksum timeout (in EVR clks); 0 disables
    g_EXTRA_RAW_EVTS : natural   := 0             -- additional events to decode (no delay/width)
  );
  port(
    -- ------------------------------------------------------------------------
    -- Debug interface
    -- ------------------------------------------------------------------------
    debug_clk        : out std_logic;
    debug            : out std_logic_vector(127 downto 0);
    -- ------------------------------------------------------------------------
    -- UDP2BUS Interface (bus clock domain, 100-250MHz)
    -- ------------------------------------------------------------------------
    bus_CLK          : in  std_logic;
    bus_RESET        : in  std_logic;
    bus_Req          : in  Udp2BusReqType;
    bus_Rep          : out Udp2BusRepType;
    evr_CfgReq       : in  Evr320ConfigReqType := EVR320_CONFIG_REQ_INIT_C;
    evr_CfgAck       : Out Evr320ConfigAckType;
    -- ------------------------------------------------------------------------
    -- EVR Interface
    -- ------------------------------------------------------------------------
    clk_evr          : in  std_logic;
    rst_evr          : in  std_logic;
    evr_rx_data      : in  std_logic_vector(15 downto 0);
    evr_rx_charisk   : in  std_logic_vector( 1 downto 0);
    mgt_status_i     : in  std_logic_vector(31 downto 0) := (others => '0');
    mgt_reset_o      : out std_logic;
    mgt_control_o    : out std_logic_vector(31 downto 0);

    event_o          : out std_logic_vector( 7 downto 0);
    event_vld_o      : out std_logic;
    timestamp_hi_o   : out std_logic_vector(31 downto 0);
    timestamp_lo_o   : out std_logic_vector(31 downto 0);
    timestamp_strb_o : out std_logic;
    ---------------------------------------------------------------------------
    -- User interface MGT clock
    ---------------------------------------------------------------------------
    usr_events_o     : out std_logic_vector(3 downto 0); -- User defined event pulses with one clock cycles length & no delay 
    sos_event_o      : out std_logic;   -- Start-of-Sequence Event
    --*** new features adjusted in delay & length ***
    --usr_event_width_i : in  typ_arr_width; --output extend in clock recovery clock cycles event 0,1,2,3
    --usr_event_delay_i : in  typ_arr_delay; -- delay in recovery clock cycles event sos,0,1,2,3
    usr_events_adj_o : out std_logic_vector(3 downto 0); -- User defined event pulses adjusted in delay & length
    sos_events_adj_o : out std_logic;   -- Start-of-Sequence adjusted in delay & length
    -- additional events to decode; unfortunatelye the register map of the evr320 and the
    -- associated data types are not easily extendable; therefore we provide an additional bank
    extra_events_o   : out std_logic_vector(g_EXTRA_RAW_EVTS - 1 downto 0);
    --------------------------------------------------------------------------
    -- Decoder axi stream interface, User clock
    --------------------------------------------------------------------------
    stream_clk_i     : in  std_logic := '0';
    stream_data_o    : out std_logic_vector(7 downto 0);
    stream_addr_o    : out std_logic_vector(10 downto 0);
    stream_valid_o   : out std_logic;
    stream_ready_i   : in  std_logic := '1';
    stream_clk_o     : out std_logic
  );
end evr320_udp2bus_wrapper;

architecture rtl of evr320_udp2bus_wrapper is

  -- --------------------------------------------------------------------------
  -- Parameters
  -- --------------------------------------------------------------------------
  constant c_UDP2BUS_DATA_WIDTH : integer := 32;
  constant c_EVR_REG64_COUNT    : integer := 16; -- unused, only documentation
  constant c_EVR_MEM_SIZE       : integer := 16384; -- unused, only documentation

  constant c_TS_BIT_0_EVENT     : std_logic_vector(7 downto 0) := x"70";
  constant c_TS_BIT_1_EVENT     : std_logic_vector(7 downto 0) := x"71";
  constant c_TS_CLOCK_EVENT     : std_logic_vector(7 downto 0) := x"7C";
  constant c_TS_LATCH_EVENT     : std_logic_vector(7 downto 0) := x"7D";

  constant c_TS_MODE_EVR_CLK    : std_logic := '0';
  -- --------------------------------------------------------------------------
  -- Signal definitions
  -- --------------------------------------------------------------------------
  --signal clk_evr_monitor                  : std_logic; -- for debugging
  signal mem_clk                      : std_logic;
  signal mem_addr_evr                 : std_logic_vector(11 downto 0);
  signal mem_addr_tosca               : std_logic_vector(10 downto 0);
  signal mem_data                     : std_logic_vector(c_UDP2BUS_DATA_WIDTH - 1 downto 0);
  signal evr_params                   : typ_evr320_params;
  signal evr_params_sync              : typ_evr320_params;
  signal evr_params_xuser             : typ_evr320_params;
  signal event_recorder_status        : typ_evt_rec_status;
  signal event_recorder_control       : typ_evt_rec_ctrl;
  signal event_recorder_control_sync  : typ_evt_rec_ctrl;
  signal event_recorder_control_xuser : typ_evt_rec_ctrl;
  signal evr_latency_measure_stat     : typ_rec_latency_measure_stat;
  signal evr_latency_measure_ctrl     : typ_rec_latency_measure_ctrl;
  signal evr_frequency                : std_logic_vector(31 downto 0) := (others => '0');
  signal debug_data                   : std_logic_vector(127 downto 0);
  signal decoder_event_valid          : std_logic;
  signal decoder_event                : std_logic_vector(7 downto 0);
  signal decoder_status               : std_logic_vector(15 downto 0);
  signal misc_status                  : std_logic_vector(15 downto 0) := (others => '0');
  signal timestampHi                  : std_logic_vector(31 downto 0) := (others => '0');
  signal timestampSR                  : std_logic_vector(31 downto 0) := (others => '0');
  signal timestampLo                  : std_logic_vector(31 downto 0) := (others => '0');
  signal timestampStrobe              : std_logic                     := '0';
  signal timestampLoMode              : std_logic                     := '0';
  signal timestampLoMode_sync         : std_logic                     := '0';
  signal timestampLoMode_xuser        : std_logic                     := '0';
  signal usr_status                   : std_logic_vector(31 downto 0) := (others => '0');
  signal usr_control                  : std_logic_vector(31 downto 0);

  signal extra_events                 : typ_arr8(g_EXTRA_RAW_EVTS - 1 downto 0) := ( others => (others => '0') );

  -- --------------------------------------------------------------------------
  -- Attribute definitions
  -- --------------------------------------------------------------------------
  attribute keep           : string;
  attribute keep of debug_data : signal is "TRUE";
  signal usr_events_s      : std_logic_vector(3 downto 0);
  signal sos_event_s       : std_logic;
  signal evr_rst_s         : std_logic;
  signal usr_event_delay_s : typ_arr_delay;
  signal usr_event_width_s : typ_arr_width;

  -- ----------------------------------------------------------------------------
  -- ----------------------------------------------------------------------------
  -- ////////////////////           Main Body           /////////////////////////
  -- ----------------------------------------------------------------------------
  -- ----------------------------------------------------------------------------
begin
  -- --------------------------------------------------------------------------
  -- static signal assignments
  -- --------------------------------------------------------------------------
  mem_addr_evr   <= '0' & mem_addr_tosca;

  -- --------------------------------------------------------------------------
  -- Synchronisation to EVR Clock
  -- --------------------------------------------------------------------------
  prc_sync_evr : process(clk_evr)
  begin
    if rising_edge(clk_evr) then
      ---
      evr_params_sync             <= evr_params_xuser;
      evr_params                  <= evr_params_sync;
      ---
      event_recorder_control_sync <= event_recorder_control_xuser;
      event_recorder_control      <= event_recorder_control_sync;
      ---
      timestampLoMode_sync        <= timestampLoMode_xuser;
      timestampLoMode             <= timestampLoMode_sync;
      ---
    end if;
  end process;

  misc_status(15 downto 7) <= (others => '0');

  misc_status( 3 downto 0) <= decoder_status(3 downto 0);

  timestampLoMode_xuser    <= usr_control(0);

  -- --------------------------------------------------------------------------
  -- EVR320 Decoder
  -- --------------------------------------------------------------------------
  evr320_decoder_inst : entity work.evr320_decoder
    generic map(
      EVENT_RECORDER   => g_EVENT_RECORDER,
      MEM_DATA_WIDTH   => c_UDP2BUS_DATA_WIDTH,
      EVR_FORCE_STBL   => g_EVR_FORCE_STBL,
      DATA_MEMORY_EN   => g_DATA_MEMORY_EN,
      N_EVT_DBL_BUFS   => g_N_EVT_DBL_BUFS,
      DATA_STREAM_EN   => g_DATA_STREAM_EN
    )
    port map(
      -- Debug interface
      debug_clk             => debug_clk,
      debug                 => debug_data,
      -- GTX parallel interface
      i_mgt_rst             => rst_evr,
      i_mgt_rx_clk          => clk_evr,
      i_mgt_rx_data         => evr_rx_data,
      i_mgt_rx_charisk      => evr_rx_charisk,
      o_decoder_status      => decoder_status,
      -- User interface CPU clock
      i_usr_clk             => mem_clk,
      i_evr_params          => evr_params,
      o_event_recorder_stat => event_recorder_status,
      i_event_recorder_ctrl => event_recorder_control,
      i_mem_addr            => mem_addr_evr,
      o_mem_data            => mem_data,
      -- user stream interface, user clock
      i_stream_clk          => stream_clk_i,
      o_stream_data         => stream_data_o,
      o_stream_addr         => stream_addr_o,
      o_stream_valid        => stream_valid_o,
      i_stream_ready        => stream_ready_i,
      o_stream_clk          => stream_clk_o,
      -- User interface MGT clock
      o_usr_events          => usr_events_s,
      --	o_usr_events_ext      => usr_events_ext_o, -- not in use anymore
      o_sos_event           => sos_event_s,
      o_event               => decoder_event,
      o_event_valid         => decoder_event_valid
    );

  usr_events_o <= usr_events_s;
  sos_event_o  <= sos_event_s;

  -- --------------------------------------------------------------------------
  -- UDP2Bus
  -- -------------------------------------------------------------------------- 
  --formatter:off 
  evr320_udp2bus_inst : entity work.evr320_udp2bus
    generic map(
      g_CS_TIMEOUT_CNT           => g_CS_TIMEOUT_CNT,
      g_ADDR_MSB                 => 10,
      g_EXTRA_RAW_EVTS           => g_EXTRA_RAW_EVTS
    )
    port map(
      -- UDP2Bus Interface
      bus_CLK                    => bus_CLK,
      bus_RESET                  => bus_RESET,
      bus_Req                    => bus_Req,
      bus_Rep                    => bus_Rep,
      evr_CfgReq                 => evr_CfgReq,
      evr_CfgAck                 => evr_CfgAck,
      -- EVR320 Memory/Parameter Interface
      evr_params_o               => evr_params_xuser,
      evr_frequency_i            => evr_frequency,
      evr_evt_rec_status_i       => event_recorder_status,
      evr_evt_rec_control_o      => event_recorder_control_xuser,
      evr_latency_measure_stat_i => evr_latency_measure_stat,
      evr_latency_measure_ctrl_o => evr_latency_measure_ctrl,
      mgt_status_i               => mgt_status_i,
      mgt_reset_o                => mgt_reset_o,
      mgt_control_o              => mgt_control_o,
      mem_clk_o                  => mem_clk,
      mem_addr_o                 => mem_addr_tosca,
      mem_data_i                 => mem_data,
      misc_status_i              => misc_status,
      usr_status_i               => usr_status,
      usr_control_o              => usr_control,
      extra_events_o             => extra_events,
      -- 
      evr_clk_i                  => clk_evr,
      evr_rst_i                  => evr_rst_s,
      evr_pulse_delay_o          => usr_event_delay_s,
      evr_pulse_width_o          => usr_event_width_s)
    ;

  -- --------------------------------------------------------------------------
  -- Measure EVR Clock (based on xuser_CLK)
  -- --------------------------------------------------------------------------
  clock_meas_inst : entity work.psi_common_clk_meas
    generic map(
      MasterFrequency_g  => g_BUS_CLOCK_FREQ,
      MaxMeasFrequency_g => 150000000
    )
    port map(
      ClkMaster   => bus_CLK,
      Rst         => bus_RESET,
      ClkTest     => clk_evr,
      FrequencyHz => evr_frequency
    );

  -- --------------------------------------------------------------------------
  -- Event Latency Measurement for SW tests
  -- --------------------------------------------------------------------------
  lat_meas_block : block
    type state_type is (armed, count);
    signal state                   : state_type;
    signal counter                 : unsigned(31 downto 0);
    signal event_nr_sync, event_nr : std_logic_vector(7 downto 0);
    signal event_detected          : std_logic_vector(3 downto 0);
    signal event_detected_sync     : std_logic_vector(1 downto 0);

    function MAX_COUNT_F return unsigned is
      variable v : real;
      variable u : unsigned(31 downto 0);
    begin
      v := real(g_BUS_CLOCK_FREQ);
      v := v * g_MAX_LATCNT_PER;
      if ( v >= 2.0**32 ) then
          v := 2.0**32 - 1.0;
      end if;
      if ( v >= 2.0**31 ) then
          v     := v - 2.0**31;
          u(31) := '1';
      else
          u(31) := '0';
      end if;
      if ( v < 0.0 ) then
          v     := 0.0;
      end if;
      u(30 downto 0) := to_unsigned(natural(v), 31);
      return u;
    end function MAX_COUNT_F;

    constant MAX_COUNT             : unsigned(31 downto 0) := MAX_COUNT_F;
  begin

    -- Process: filter events for matching event_nr register:
    ---------------------------------------------------------
    ext_event_proc : process(clk_evr)
    begin
      if (rising_edge(clk_evr)) then
        -- sync to MGT clock domain:
        event_nr_sync <= evr_latency_measure_ctrl.event_nr;
        event_nr      <= event_nr_sync;

        -- check if event has been detected and stretch pulse: 
        event_detected <= event_detected(2 downto 0) & '0';
        if (decoder_event_valid = '1' and decoder_event = event_nr) then
          event_detected <= (others => '1');
        end if;
      end if;
    end process;

    -- Process: Counter when configured event has been detected:
    ------------------------------------------------------------
    lat_meas_proc : process(bus_CLK)
    begin
      if rising_edge(bus_CLK) then
        -- sync to user clock domain:
        event_detected_sync <= event_detected_sync(0) & event_detected(3);

        -- counter FSM:
        ---------------
        case state is
          -- counter is armed:
          when armed =>
            counter <= (others => '0');
            -- start counting when event detected (rising edge):
            if (event_detected_sync(1) = '0' and event_detected_sync(0) = '1') then
              state <= count;
            end if;

          -- counting:
          when count =>
            if (MAX_COUNT = 0 or counter < MAX_COUNT) then
              counter <= counter + 1;
            end if;
            if (evr_latency_measure_ctrl.counter_arm = '1') then
              state <= armed;
            end if;
            if (evr_latency_measure_ctrl.auto_arm = '1') then
              if (event_detected_sync(1) = '0' and event_detected_sync(0) = '1') then
                counter <= (others => '0');
                state   <= count;
              end if;
            end if;
        end case;
      end if;
    end process;

    evr_latency_measure_stat.counter_val <= std_logic_vector(counter);

    p_ev_dbg : process (bus_CLK) is
    begin
      if ( rising_edge( bus_CLK ) ) then
        if ( bus_RESET = '1' ) then
          misc_status(4) <= '0';
        else
          if ( event_detected_sync(1) = '1' ) then
            misc_status(4) <= '1';
          elsif (evr_latency_measure_ctrl.counter_arm = '1') then
            misc_status(4) <= '0';
          end if;
        end if;
      end if;
    end process p_ev_dbg;

    misc_status(6 downto 5) <= "01" when (state = armed) else
                               "10" when (state = count) else
                               "00";

  end block;

  -- --------------------------------------------------------------------------
  -- Add delay output
  -- --------------------------------------------------------------------------
  output_delay_block : block
    signal rst0_s, rst1_s      : std_logic; -- double stage sync for reset
    signal usr_events_adj_s    : std_logic_vector(4 downto 0);
    signal usr_events_concat_s : std_logic_vector(4 downto 0);
    signal mmcm_locked                  : std_logic;
    signal rxpll_locked                 : std_logic;
    signal evr_rst_in                   : std_logic;


  begin

    rxpll_locked <= mgt_status_i(1);
    mmcm_locked  <= mgt_status_i(2);
    evr_rst_in   <= bus_RESET or (not rxpll_locked) or (not mmcm_locked);

    --*** double stage sync for reset ***--
    proc_rst : process(clk_evr)
    begin
      if rising_edge(clk_evr) then
        rst0_s <= evr_rst_in;
        rst1_s <= rst0_s;
      end if;
    end process;

    evr_rst_s <= rst1_s;

    usr_events_concat_s <= usr_events_s & sos_event_s;

    gene_adj_out : for i in 0 to 4 generate

      inst_pulser_evr0 : entity work.pulse_shaper_dly_cfg
        generic map(
          DelayLd_g => MaxDelayLd_c,
          WidthLd_g => MaxDurationLd_c
        )
        port map(
          clk_i     => clk_evr,
          rst_i     => rst1_s,
          width_i   => usr_event_width_s(i),
          delay_i   => usr_event_delay_s(i),
          dat_i     => usr_events_concat_s(i),
          dat_o     => usr_events_adj_s(i)
        );
    end generate;

    usr_events_adj_o <= usr_events_adj_s(4 downto 1);
    sos_events_adj_o <= usr_events_adj_s(0);
  end block;

  -- --------------------------------------------------------------------------
  -- Timestamp decoder
  -- --------------------------------------------------------------------------
  prc_ts : process(clk_evr) is
  begin
    if ( rising_edge( clk_evr ) ) then
       if ( rst_evr = '1' ) then
          timestampLo     <= (others => '0');
          timestampHi     <= (others => '0');
          timestampSR     <= (others => '0');
          timestampStrobe <= '0';
       else
          timestampStrobe <= '0';
          if ( c_TS_MODE_EVR_CLK = timestampLoMode ) then
             timestampLo <= std_logic_vector( unsigned( timestampLo ) + 1 );
          end if;
          if ( decoder_event_valid = '1' ) then
             if    ( decoder_event = c_TS_LATCH_EVENT ) then
                timestampHi     <= timestampSR;
                timestampLo     <= (others => '0');
                timestampStrobe <= '1';
             elsif ( decoder_event = c_TS_BIT_0_EVENT ) then
                timestampSR     <= timestampSR(timestampSR'left - 1 downto 0) & '0';
             elsif ( decoder_event = c_TS_BIT_1_EVENT ) then
                timestampSR     <= timestampSR(timestampSR'left - 1 downto 0) & '1';
             elsif ( decoder_event = c_TS_CLOCK_EVENT ) then
                if ( not c_TS_MODE_EVR_CLK = timestampLoMode ) then
                   timestampLo <= std_logic_vector( unsigned( timestampLo ) + 1 );
                end if;
             end if;
          end if;
       end if;
    end if;
  end process prc_ts;

  -- --------------------------------------------------------------------------
  -- Extra events
  -- --------------------------------------------------------------------------
  gene_extra_decoders : for dec in g_EXTRA_RAW_EVTS - 1 downto 0 generate
    prc_xtra_dec : process(clk_evr) is
    begin
      if ( rising_edge( clk_evr ) ) then
         if ( rst_evr = '1' ) then
            extra_events_o(dec) <= '0';
         else
            extra_events_o(dec) <= '0';
            if ( ( decoder_event_valid = '1' ) and (decoder_event = extra_events(dec) ) ) then 
               extra_events_o(dec) <= '1';
            end if;
         end if;
      end if;
    end process prc_xtra_dec;
  end generate gene_extra_decoders;
 
  -- --------------------------------------------------------------------------
  -- port mapping
  -- --------------------------------------------------------------------------
  debug            <= debug_data;

  event_o          <= decoder_event;
  event_vld_o      <= decoder_event_valid;

  timestamp_lo_o   <= timestampLo;
  timestamp_hi_o   <= timestampHi;
  timestamp_strb_o <= timestampStrobe;

end rtl;
-- ----------------------------------------------------------------------------
-- ////////////////////////////////////////////////////////////////////////////
-- ----------------------------------------------------------------------------
