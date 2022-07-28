-- ---------------------------------------------------------------------------
--                       Paul Scherrer Institute (PSI)
-- ---------------------------------------------------------------------------
-- Unit    : evr320_tmem.vhd
-- Author  : Patric Bucher, Benoit Stef, Till Straumann
-- ---------------------------------------------------------------------------
-- Copyright (c) PSI, Section DSV
-- ---------------------------------------------------------------------------
-- Comment : UDP2BUS address decoding for register and memory access to evr320.
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.evr320_pkg.all;
use work.Udp2BusPkg.all;
use work.Evr320ConfigPkg.all;

entity evr320_udp2bus is
  generic (
    g_CS_TIMEOUT_CNT              : natural := 16#15CA20#; -- data frame checksum timeout (in EVR clks); 0 disables
    g_ADDR_MSB                    : natural;
    g_USR_CONTROL_INIT            : std_logic_vector(31 downto 0) := (others => '0');
    g_EXTRA_RAW_EVTS              : natural range 0 to 8          := 0  -- additional events to decode (no delay/width)
  );
  port(
    -- ------------------------------------------------------------------------
    -- UDP2BUS Interface (bus_CLK clock domain, 100-250MHz)
    -- ------------------------------------------------------------------------
    bus_CLK                       : in    std_logic; 
    bus_RESET                     : in    std_logic;                    
    bus_Req                       : in    Udp2BusReqType;
    bus_Rep                       : out   Udp2BusRepType;
    evr_CfgReq                    : in    Evr320ConfigReqType := EVR320_CONFIG_REQ_INIT_C;
    evr_CfgAck                    : Out   Evr320ConfigAckType;
    ---------------------------------------------------------------------------
    -- EVR320 Memory/Parameter Interface
    ---------------------------------------------------------------------------
    evr_params_o                  : out   typ_evr320_params;
    evr_frequency_i               : in    std_logic_vector(31 downto  0);
    evr_evt_rec_status_i          : in    typ_evt_rec_status;           
    evr_evt_rec_control_o         : out   typ_evt_rec_ctrl;           
    evr_latency_measure_stat_i    : in    typ_rec_latency_measure_stat;
    evr_latency_measure_ctrl_o    : out   typ_rec_latency_measure_ctrl;
    mgt_status_i                  : in    std_logic_vector(31 downto  0) := (others=>'0');
    mgt_control_o                 : out   std_logic_vector(31 downto  0);
    mgt_reset_o                   : out   std_logic;          
    mem_clk_o                     : out   std_logic; 
    mem_addr_o                    : out   std_logic_vector(10 downto  0); 
    mem_data_i                    : in    std_logic_vector(31 downto  0);
    misc_status_i                 : in    std_logic_vector(15 downto  0);
    usr_status_i                  : in    std_logic_vector(31 downto  0) := (others => '0'); -- not resynced
    usr_control_o                 : out   std_logic_vector(31 downto  0);
    extra_events_o                : out   typ_arr8(g_EXTRA_RAW_EVTS - 1 downto 0) := (others => (others => '0'));
    ---------------------------------------------------------------------------
    -- EVR320 pulse output paremters
    ---------------------------------------------------------------------------
    evr_clk_i                     : in    std_logic;
    evr_rst_i                     : in    std_logic;
    evr_pulse_delay_o             : out   typ_arr_delay;
    evr_pulse_width_o             : out   typ_arr_width
  );
end entity evr320_udp2bus;

architecture rtl of evr320_udp2bus is

 -- ---------------------------------------------------------------------------
  -- Constants
  -- ---------------------------------------------------------------------------
  constant reserved               : std_logic_vector(31 downto  0)   := X"0000_0000";
  constant c_LOW                  : std_logic_vector(31 downto  0)   := X"0000_0000";
  constant LD_NUM_REG32           : integer := 5;
  constant NUM_REG32              : integer := 2**LD_NUM_REG32;
  constant DWRD_ADDR_LSB          : integer := 0; -- dword addresses in request
  constant REG_ADDR_WIDTH         : integer := LD_NUM_REG32 + DWRD_ADDR_LSB;
  constant REG_ADDR_MSB           : integer := REG_ADDR_WIDTH - 1;
  constant MEM_ADDR_START         : std_logic_vector(7 downto  0) := X"20";

  -- indirect registers; the address map is already quite full and indirect registers
  -- make backwards compatibility easier...

  -- If LD_NUM_IREGS > 8 then the tmem write logic needs to be modified!
  constant LD_NUM_IREGS           : natural  range 0 to 8 := 5; -- 4-byte words
 
  constant c_RXRESETDONE          : integer := 4;
  constant c_RXLOSSOFSYNC         : integer := 15;
  constant c_RXPLLLKDET           : integer :=  1;

  -- --------------------------------------------------------------------------
  -- Type definitions
  -- --------------------------------------------------------------------------

  type   typ_arr32              is array( integer range <> ) of std_logic_vector(31 downto 0);

  -- --------------------------------------------------------------------------
  -- Signal definitions
  -- --------------------------------------------------------------------------
  signal addr_dly               : std_logic_vector(g_ADDR_MSB downto DWRD_ADDR_LSB) := (others => '0');
  signal rdata                  : std_logic_vector(31         downto             0) := (others => '0');
  signal rvalid                 : std_logic                                         := '0';
  signal rberr                  : std_logic                                         := '0';
  signal wberr                  : std_logic                                         := '0';

  signal evr_CfgAckLoc          : Evr320ConfigAckType := EVR320_CONFIG_ACK_INIT_C;
  
  -- evr params
  signal mgt_status_evr         : std_logic_vector(15 downto 0)   := (others => '0');
  signal mgt_status_evr_sync    : std_logic_vector(15 downto 0)   := (others => '0');
  signal mgt_status_full        : std_logic_vector(31 downto 0)   := (others => '0');
  signal mgt_status_full_sync   : std_logic_vector(31 downto 0)   := (others => '0');
  signal misc_status            : std_logic_vector(15 downto 0)   := (others => '0');
  signal misc_status_last       : std_logic_vector(15 downto 0)   := (others => '0');
  signal misc_status_sync       : std_logic_vector(15 downto 0)   := (others => '0');
  signal mgt_reset              : std_logic                       := '0';
  signal mgt_control            : std_logic_vector(31 downto 0)   := (others => '0');
  signal event_enable           : std_logic_vector( 3 downto 0)   := (others => '0');
  signal event_numbers          : typ_arr8(3 downto 0)            := (others => (others => '0'));
  signal event_numbers_concat   : std_logic_vector(31 downto 0);
  signal cs_min_cnt             : std_logic_vector(31 downto 0)   := c_CHECKSUM_MIN_EVT;
  signal cs_min_time            : std_logic_vector(31 downto 0)   := c_CHECKSUM_MIN_TIME;
  signal cs_timeout_cnt         : std_logic_vector(31 downto 0)   := std_logic_vector(to_unsigned(g_CS_TIMEOUT_CNT, 32));
  signal evr_frequency_sync     : std_logic_vector(31 downto 0)   := (others => '0');
  signal evr_frequency          : std_logic_vector(31 downto 0)   := (others => '0');
  signal usr_control            : std_logic_vector(31 downto 0)   := g_USR_CONTROL_INIT;
  
  -- event recorder    
  signal er_status              : typ_evt_rec_status              := c_INIT_EVT_REC_STATUS;
  signal er_status_sync         : typ_evt_rec_status              := c_INIT_EVT_REC_STATUS;
  signal er_event_enable        : std_logic                       := '0';
  signal er_event_number        : std_logic_vector( 7 downto 0)   := c_SOS_EVENT_DEFAULT;
  signal er_data_ack            : std_logic_vector( 3 downto 0)   := (others => '0');
  signal er_error_ack           : std_logic_vector( 3 downto 0)   := (others => '0');
  signal er_handshake_status    : std_logic_vector(31 downto 0)   := (others => '0');
  signal er_control_concat      : std_logic_vector(31 downto 0)   := (others => '0');

  -- latency measurement
  signal lat_counter_arm        : std_logic                       := '0'; 
  signal lat_counter_autoarm    : std_logic                       := '0';
  signal lat_event_nr           : std_logic_vector(7 downto 0)    := c_SOS_EVENT_DEFAULT;
  signal lat_counter_val        : std_logic_vector(31 downto 0)   := (others=>'0'); 
  signal lat_event_detected     : std_logic_vector(7 downto 0);
  signal lat_arm                : std_logic := '0';
  signal lat_arm_edge           : std_logic_vector(1 downto 0)    := (others=>'0');

  -- event pulse config
  
  signal evr_puls_width_cfg_s   : typ_arr_width := (others => UsrEventWidthDefault_c);
  signal evr_puls_delay_cfg_s   : typ_arr_delay := (others => (others => '0'));

  -- status counters
  signal miscCount              : typ_arrU16(2 downto 0) := (others => (others => '0'));

  signal iregAddr               : unsigned(LD_NUM_IREGS - 1 downto 0) := (others => '0');
  signal iregData               : std_logic_vector(31 downto 0);

  signal extra_events           : typ_arr8(g_EXTRA_RAW_EVTS - 1 downto 0)            := (others => (others => '0'));
  signal extra_events_concat    : typ_arr32((g_EXTRA_RAW_EVTS + 3) / 4 - 1 downto 0) := (others => (others => '0'));

-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
-- ////////////////////           Main Body           /////////////////////////
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
begin

  -- --------------------------------------------------------------------------
  -- static signal assignments                                                      
  -- --------------------------------------------------------------------------
  event_numbers_concat  <= event_numbers(3) & event_numbers(2) & event_numbers(1) & event_numbers(0);
  er_handshake_status   <= X"0000" & bit2byte(er_status.data_error) & bit2byte(er_status.data_valid);
  er_control_concat     <= X"0000" & er_event_number & bit2byte(er_event_enable);
  lat_counter_val       <= evr_latency_measure_stat_i.counter_val;

  process (bus_CLK)
  begin
    if rising_edge(bus_CLK) then
      -- edge detection of latency arm:
      lat_arm_edge <= lat_arm_edge(0) & lat_arm;
      lat_counter_arm <= lat_arm_edge(0) and not lat_arm_edge(1);


      if (evr_latency_measure_stat_i.event_detected = '1') then
        lat_event_detected  <= (others=>'1');
      end if;
      if (lat_counter_arm = '1') then
        lat_event_detected  <= (others=>'0');
      end if;
    end if;
  end process;
  
  -- --------------------------------------------------------------------------
  -- Synchronisation to bus_CLK                                                      
  -- --------------------------------------------------------------------------
  prc_sync_xuser: process (bus_CLK)
  begin
    if rising_edge(bus_CLK) then
      ---
      mgt_status_evr_sync   <= "000000" & mgt_status_i(c_RXRESETDONE) & mgt_status_i(c_RXLOSSOFSYNC) & "000000" & mgt_status_i(c_RXRESETDONE) & mgt_status_i(c_RXPLLLKDET);
      mgt_status_evr        <= mgt_status_evr_sync;
      ---
      misc_status_sync      <= misc_status_i;
      misc_status           <= misc_status_sync;
      misc_status_last      <= misc_status;
      ---
      mgt_status_full_sync  <= mgt_status_i;
      mgt_status_full       <= mgt_status_full_sync;
      ---
      er_status_sync        <= evr_evt_rec_status_i;
      er_status             <= er_status_sync;
      ---
      evr_frequency_sync    <= evr_frequency_i;
      evr_frequency         <= evr_frequency_sync;
      ---
    end if;
  end process;

  -- --------------------------------------------------------------------------
  -- Status counters
  -- --------------------------------------------------------------------------
  G_StatusCounters : for i in miscCount'range generate
    misc_count : process (bus_CLK) is
    begin
      if ( rising_edge(bus_CLK) ) then
        if ( bus_RESET = '1' ) then
          miscCount(i) <= (others => '0');
        elsif ( (misc_status(i) = '0') and (misc_status_last(i) = '1') ) then
          miscCount(i) <= miscCount(i) + 1;
        end if;
      end if;
    end process misc_count;
  end generate G_StatusCounters;

  -- --------------------------------------------------------------------------
  -- Delay read address (to match delay in memory path)
  -- --------------------------------------------------------------------------
  prc_addr_dly: process (bus_CLK)
  begin
    if rising_edge(bus_CLK) then
       addr_dly <= bus_Req.dwaddr(addr_dly'range);
    end if;
  end process prc_addr_dly;
 
  -- --------------------------------------------------------------------------
  -- Read operation                                                       
  -- --------------------------------------------------------------------------
  blk_tmemrd : block

  begin

  read_tmem_evr: process(bus_CLK)
  begin
    if (rising_edge(bus_CLK)) then
      if ( bus_RESET = '1' ) then
        rvalid <= '0';
        rberr  <= '0';
      elsif ( (bus_Req.valid and bus_Req.rdnwr) = '1') then
        rberr  <= '0';
        rvalid <= not rvalid; -- equivalent to delay by 1 cycle
        if (bus_Req.dwaddr(g_ADDR_MSB downto REG_ADDR_WIDTH) = c_LOW(g_ADDR_MSB downto REG_ADDR_WIDTH)) then
          case bus_Req.dwaddr(REG_ADDR_MSB downto DWRD_ADDR_LSB) is
            when X"0" & "0" => rdata <=  misc_status & mgt_status_evr;       -- 32bit / ByteAddr 000
            when X"0" & "1" => rdata <=  event_numbers_concat;               -- 32bit / ByteAddr 004
            when X"1" & "0" => rdata <=  X"0000_00" & bit2byte(mgt_reset);   -- 32bit / ByteAddr 008
            when X"1" & "1" => rdata <=  reserved;                           -- 32bit / ByteAddr 00c   --> 0x00C = not implemented in ifc1210
            when X"2" & "0" => rdata <=  bit2byte(event_enable);             -- 32bit / ByteAddr 010
            when X"2" & "1" => rdata <=  reserved;                           -- 32bit / ByteAddr 014   --> 0x014 = Bit0 SW Trigger Event 0, Bit8 SW Trigger Event 1, ...
            when X"3" & "0" => rdata <=  cs_timeout_cnt;                     -- 32bit / ByteAddr 018
            when X"3" & "1" => rdata <=  evr_frequency;                      -- 32bit / ByteAddr 01c
            when X"4" & "0" => rdata <=  cs_min_cnt;                         -- 32bit / ByteAddr 020
            when X"4" & "1" => rdata <=  cs_min_time;                        -- 32bit / ByteAddr 024
            when X"5" & "0" => rdata <=  usr_status_i;                       -- 32bit / ByteAddr 028
            when X"5" & "1" => rdata <=  usr_control;                        -- 32bit / ByteAddr 02c
            when X"6" & "0" => rdata <=  x"00" & lat_event_detected & "000000" & lat_counter_autoarm & lat_counter_arm & lat_event_nr; -- 32bit / ByteAddr 030
            when X"6" & "1" => rdata <=  lat_counter_val;                    -- 32bit / ByteAddr 034
            when X"7" & "0" => rdata <=  reserved;                           -- 32bit / ByteAddr 038
            when X"7" & "1" => rdata <=  reserved;                           -- 32bit / ByteAddr 03c
            when X"8" & "0" => rdata <=  er_control_concat;                  -- 32bit / ByteAddr 040                
            when X"8" & "1" => rdata <=  er_handshake_status;                -- 32bit / ByteAddr 044                
            when X"9" & "0" => rdata <=  er_status.usr_events_counter;       -- 32bit / ByteAddr 048   
            when X"9" & "1" => rdata <=  reserved;                           -- 32bit / ByteAddr 04c
            when X"A" & "0" => rdata <=  evr_puls_delay_cfg_s(2)(15 downto 0) &
                                                      evr_puls_delay_cfg_s(1)(15 downto 0); -- 32bit / ByteAddr 050   
            when X"A" & "1" => rdata <=  evr_puls_delay_cfg_s(4)(15 downto 0) &
                                                      evr_puls_delay_cfg_s(3)(15 downto 0); -- 32bit / ByteAddr 054
            when X"B" & "0" => rdata <=  evr_puls_width_cfg_s(2)(15 downto 0) &
                                                      evr_puls_width_cfg_s(1)(15 downto 0); -- 32bit / ByteAddr 058
            when X"B" & "1" => rdata <=  evr_puls_width_cfg_s(4)(15 downto 0) &
                                                      evr_puls_width_cfg_s(3)(15 downto 0); -- 32bit / ByteAddr 05c
            when X"C" & "0" => rdata <=  evr_puls_width_cfg_s(0)(15 downto 0) &
                                                      evr_puls_delay_cfg_s(0)(15 downto 0); -- 32bit / ByteAddr 060
            when X"C" & "1" => rdata <=  reserved;                           -- 32bit / ByteAddr 064
            when X"D" & "0" => rdata <=  mgt_status_full;                    -- 32bit / ByteAddr 068
            when X"D" & "1" => rdata <=  mgt_control;                        -- 32bit / ByteAddr 06c
            when X"E" & "0" => rdata <=  std_logic_vector(miscCount(1)) & std_logic_vector(miscCount(0)); -- 32bit / ByteAddr 070
            when X"E" & "1" => rdata <=  x"0000" & std_logic_vector(miscCount(2)); -- 32bit / ByteAddr 074
            when X"F" & "0" => rdata <=  std_logic_vector(resize(iregAddr, 32));   -- 32bit / ByteAddr 078
            when X"F" & "1" => rdata <=  iregData;                           -- 32bit / ByteAddr 07c
            when others     => rdata <=  (others => '0');
                               rberr <= '1';
          end case;
        else --> 0x0080-0x4000
        end if;
      end if;
    end if;
  end process;

  P_IREG_RD_MUX : process ( iregAddr, evr_puls_width_cfg_s, evr_puls_delay_cfg_s, extra_events_concat ) is
    variable hi, lo: integer;
  begin
    iregData <= (others => '0');
    if ( iregAddr < 2*evr_puls_width_cfg_s'length ) then
      if ( iregAddr(0) = '1' ) then
        iregData(evr_puls_width_cfg_s(0)'range) <= evr_puls_width_cfg_s(to_integer(iregAddr(iregAddr'left downto 1)));
      else
        iregData(evr_puls_delay_cfg_s(0)'range) <= evr_puls_delay_cfg_s(to_integer(iregAddr(iregAddr'left downto 1)));
      end if;
    elsif ( (to_integer(iregAddr) >= 20) and (to_integer(iregAddr) < 20 + extra_events_concat'length) ) then
      iregData <= extra_events_concat( to_integer(iregAddr) - 20 );
    end if;
  end process P_IREG_RD_MUX;

  gen_concat : for i in extra_events'range generate
    constant j : natural := i mod 4;
  begin
    extra_events_concat( i / 4 )(8*j + 7 downto 8*j) <= extra_events(i);
  end generate gen_concat; 

  -- --------------------------------------------------------------------------
  -- Reply mux
  -- --------------------------------------------------------------------------
  prc_rb_mux : process (rdata, rberr, rvalid, bus_Req, mem_data_i, addr_dly) is
  begin
    if ( addr_dly(g_ADDR_MSB downto REG_ADDR_WIDTH) = c_LOW(g_ADDR_MSB downto REG_ADDR_WIDTH) ) then
      bus_Rep.rdata <= rdata;
    else
      bus_Rep.rdata <= mem_data_i(31 downto 0);
    end if;
    if ( bus_Req.valid = '1' ) then
      if ( bus_Req.rdnwr = '1' ) then
        bus_Rep.valid <= rvalid;
        bus_Rep.berr  <= rberr;
      else
        bus_Rep.valid <= '1';
        if ( bus_Req.dwaddr(g_ADDR_MSB downto REG_ADDR_WIDTH) = c_LOW(g_ADDR_MSB downto REG_ADDR_WIDTH) ) then
          bus_Rep.berr <= '0';
        else
          bus_Rep.berr <= '1';
        end if; 
      end if;
    else
      bus_Rep.valid <= '0';
      bus_Rep.berr  <= '0';
    end if;
  end process prc_rb_mux;

  end block;

  -- --------------------------------------------------------------------------
  -- Write operation  - Byte control                                           
  -- --------------------------------------------------------------------------
  write_tmem_evr: process(bus_CLK)

    procedure fil(signal y : out std_logic_vector; constant x : in std_logic_vector) is
      variable v : std_logic_vector(y'range);
    begin
      if    ( y'length > x'length ) then
        v                                      := (others => '0');
        v(y'right + x'length - 1 downto y'right) := x;
      elsif ( x'length > y'length ) then
        v := x(x'right + y'length - 1 downto x'right);
      else
        v := x;
      end if;
      y <= v;
    end procedure fil;

    variable v_data : std_logic_vector(31 downto 0);

  begin

    v_data := (others => '0');

    if rising_edge(bus_CLK) then

      -- default assignments
      lat_arm <= '0';

      if ( (bus_Req.valid and not bus_Req.rdnwr) = '1' ) then 
        if ( bus_Req.dwaddr(g_ADDR_MSB downto REG_ADDR_WIDTH) = c_LOW(g_ADDR_MSB downto REG_ADDR_WIDTH)) then
          case bus_Req.dwaddr(REG_ADDR_MSB downto DWRD_ADDR_LSB) is
            when X"0" & "0" => -- 0x00
            when X"0" & "1" => -- 0x04
              if bus_Req.be(0) = '1' then event_numbers(0) <= bus_Req.data( 7 downto  0); end if;
              if bus_Req.be(1) = '1' then event_numbers(1) <= bus_Req.data(15 downto  8); end if;
              if bus_Req.be(2) = '1' then event_numbers(2) <= bus_Req.data(23 downto 16); end if;
              if bus_Req.be(3) = '1' then event_numbers(3) <= bus_Req.data(31 downto 24); end if;
            when X"1" & "0" => -- 0x08
              if bus_Req.be(0) = '1' then mgt_reset        <= bus_Req.data(           0); end if;
            when X"1" & "1" => -- 0x0c
            when X"2" & "0" => -- 0x10
              if bus_Req.be(0) = '1' then event_enable (0) <= bus_Req.data(           0); end if;
              if bus_Req.be(1) = '1' then event_enable (1) <= bus_Req.data(           8); end if;
              if bus_Req.be(2) = '1' then event_enable (2) <= bus_Req.data(          16); end if;
              if bus_Req.be(3) = '1' then event_enable (3) <= bus_Req.data(          24); end if;
            when X"2" & "1" => -- 0x14
            when X"3" & "0" => -- 0x18
              if bus_Req.be(0) = '1' then cs_timeout_cnt( 7 downto  0) <= bus_Req.data( 7 downto  0); end if;
              if bus_Req.be(1) = '1' then cs_timeout_cnt(15 downto  8) <= bus_Req.data(15 downto  8); end if;
              if bus_Req.be(2) = '1' then cs_timeout_cnt(23 downto 16) <= bus_Req.data(23 downto 16); end if;
              if bus_Req.be(3) = '1' then cs_timeout_cnt(31 downto 24) <= bus_Req.data(31 downto 24); end if;
            when X"3" & "1" => -- 0x1c
            when X"4" & "0" => -- 0x20
              if bus_Req.be(0) = '1' then cs_min_cnt    ( 7 downto  0) <= bus_Req.data( 7 downto  0); end if;
              if bus_Req.be(1) = '1' then cs_min_cnt    (15 downto  8) <= bus_Req.data(15 downto  8); end if;
              if bus_Req.be(2) = '1' then cs_min_cnt    (23 downto 16) <= bus_Req.data(23 downto 16); end if;
              if bus_Req.be(3) = '1' then cs_min_cnt    (31 downto 24) <= bus_Req.data(31 downto 24); end if;
            when X"4" & "1" => -- 0x24
              if bus_Req.be(0) = '1' then cs_min_time   ( 7 downto  0) <= bus_Req.data( 7 downto  0); end if;
              if bus_Req.be(1) = '1' then cs_min_time   (15 downto  8) <= bus_Req.data(15 downto  8); end if;
              if bus_Req.be(2) = '1' then cs_min_time   (23 downto 16) <= bus_Req.data(23 downto 16); end if;
              if bus_Req.be(3) = '1' then cs_min_time   (31 downto 24) <= bus_Req.data(31 downto 24); end if;
            when X"5" & "0" => -- 0x28 (read-only)
            when X"5" & "1" => -- 0x2c
              if bus_Req.be(0) = '1' then usr_control   ( 7 downto  0) <= bus_Req.data( 7 downto  0); end if;
              if bus_Req.be(1) = '1' then usr_control   (15 downto  8) <= bus_Req.data(15 downto  8); end if;
              if bus_Req.be(2) = '1' then usr_control   (23 downto 16) <= bus_Req.data(23 downto 16); end if;
              if bus_Req.be(3) = '1' then usr_control   (31 downto 24) <= bus_Req.data(31 downto 24); end if;
            when X"6" & "0" => -- 0x30
              if bus_Req.be(0) = '1' then lat_event_nr  ( 7 downto  0) <= bus_Req.data( 7 downto  0); end if;
              if bus_Req.be(1) = '1' then lat_arm                      <= bus_Req.data(           8);
                                          lat_counter_autoarm          <= bus_Req.data(           9); end if;
            when X"6" & "1" => -- 0x34
            when X"7" & "0" => -- 0x38
              if bus_Req.be(0) = '1' then lat_arm          <= bus_Req.data(           0); end if;
            when X"7" & "1" => -- 0x3c
            when X"8" & "0" => -- 0x40
              if bus_Req.be(0) = '1' then er_event_enable              <= bus_Req.data(           0); end if;
              if bus_Req.be(1) = '1' then er_event_number              <= bus_Req.data(15 downto  8); end if;
            when X"8" & "1" => -- 0x44
              if (bus_Req.be(2) and bus_Req.data(16)) = '1' then er_data_ack    <= (others => '1'); end if;
              if (bus_Req.be(3) and bus_Req.data(24)) = '1' then er_error_ack   <= (others => '1'); end if;
            when X"9" & "0" => -- 0x48
            when X"9" & "1" => -- 0x4c
            when X"A" & "0" => -- 0x50
              -- legacy 16-bit delay/width
              if bus_Req.be(1 downto 0) = "11" then fil(evr_puls_delay_cfg_s(1), bus_Req.data(15 downto  0)); end if;  -- usr evt 0 del
              if bus_Req.be(3 downto 2) = "11" then fil(evr_puls_delay_cfg_s(2), bus_Req.data(31 downto 16)); end if; -- usr evt 1 del
            when X"A" & "1" => -- 0x54
              if bus_Req.be(1 downto 0) = "11" then fil(evr_puls_delay_cfg_s(3), bus_Req.data(15 downto  0)); end if;  -- usr evt 0 del
              if bus_Req.be(3 downto 2) = "11" then fil(evr_puls_delay_cfg_s(4), bus_Req.data(31 downto 16)); end if; -- usr evt 1 del
            when X"B" & "0" => -- 0x58
              if bus_Req.be(1 downto 0) = "11" then fil(evr_puls_width_cfg_s(1), bus_Req.data(15 downto  0)); end if;  -- usr evt 0 del
              if bus_Req.be(3 downto 2) = "11" then fil(evr_puls_width_cfg_s(2), bus_Req.data(31 downto 16)); end if; -- usr evt 1 del
            when X"B" & "1" => -- 0x5c
              if bus_Req.be(1 downto 0) = "11" then fil(evr_puls_width_cfg_s(3), bus_Req.data(15 downto  0)); end if;  -- usr evt 0 del
              if bus_Req.be(3 downto 2) = "11" then fil(evr_puls_width_cfg_s(4), bus_Req.data(31 downto 16)); end if; -- usr evt 1 del
            when X"C" & "0" => -- 0x60
              if bus_Req.be(1 downto 0) = "11" then fil(evr_puls_delay_cfg_s(0), bus_Req.data(15 downto  0)); end if;  -- usr evt 0 del
              if bus_Req.be(3 downto 2) = "11" then fil(evr_puls_width_cfg_s(0), bus_Req.data(31 downto 16)); end if; -- usr evt 1 del
            when X"C" & "1" => -- 0x64
            when X"D" & "0" => -- 0x68
            when X"D" & "1" => -- 0x6c
              for i in 3 downto 0 loop
                if ( bus_Req.be(i) = '1' ) then
                  mgt_control(8*(i) + 7 downto 8*(i)) <= bus_Req.data(8*i + 7 downto 8*i);
                end if;
              end loop;
            when X"E" & "0" => -- 0x70
            when X"E" & "1" => -- 0x74
            when X"F" & "0" => -- 0x78
              if bus_Req.be(0) = '1' then iregAddr <= unsigned( bus_Req.data( iregAddr'range ) ); end if;
            when X"F" & "1" => -- 0x7c
              if ( iregAddr < 2*evr_puls_width_cfg_s'length ) then
                if ( iregAddr(0) = '1' ) then
                  v_data( evr_puls_width_cfg_s(0)'range ) := evr_puls_width_cfg_s(to_integer(iregAddr(iregAddr'left downto 1)));
                else
                  v_data( evr_puls_delay_cfg_s(0)'range ) := evr_puls_delay_cfg_s(to_integer(iregAddr(iregAddr'left downto 1)));
                end if;
                for i in 3 downto 0 loop
                  if ( bus_Req.be(i) = '1' ) then
                     v_data(8*i + 7 downto 8*i) := bus_req.data(8*i + 7 downto 8*i);
                  end if;
                end loop;
                if ( iregAddr(0) = '1' ) then
                  evr_puls_width_cfg_s(to_integer(iregAddr(iregAddr'left downto 1))) <= v_data( evr_puls_width_cfg_s(0)'range );
                else
                  evr_puls_delay_cfg_s(to_integer(iregAddr(iregAddr'left downto 1))) <= v_data( evr_puls_delay_cfg_s(0)'range );
                end if;
              elsif ( (to_integer(iregAddr) >= 20) and (to_integer(iregAddr) < 20 + (g_EXTRA_RAW_EVTS + 3)/4) ) then
                for i in 3 downto 0 loop
                  if ( ( bus_Req.be(i) = '1' ) and ( 4*(to_integer(iregAddr) - 20) + i < extra_events'length ) ) then
                     extra_events( 4*(to_integer(iregAddr) - 20) + i ) <= bus_req.data(8*i + 7 downto 8*i);
                  end if;
                end loop;
              end if;
            when others     => 
          end case;
        end if;
      end if;

      -- configuration interface
      if ( evr_CfgReq.req = '1' ) then
        evr_CfgAckLoc.ack <= not evr_cfgAckLoc.ack;
        for i in event_enable'range loop
          event_enable(i)           <= evr_CfgReq.pulseGenParams(i).pulseEnbld;
          event_numbers(i)          <= evr_CfgReq.pulseGenParams(i).pulseEvent;
          evr_puls_width_cfg_s(i+1) <= evr_CfgReq.pulseGenParams(i).pulseWidth;
          evr_puls_delay_cfg_s(i+1) <= evr_CfgReq.pulseGenParams(i).pulseDelay;
        end loop;
        for i in extra_events'length - 1 downto 0 loop
          if ( i < evr_CfgReq.extraEvents(i)'length ) then
            extra_events(i)           <= evr_CfgReq.extraEvents(i);
          end if;
        end loop;
      end if;
    end if;
  end process;
  
  
  -- --------------------------------------------------------------------------
  -- Port mapping                                                       
  -- --------------------------------------------------------------------------
  mem_clk_o                   <= bus_CLK;
  mem_addr_o                  <= std_logic_vector(unsigned(bus_Req.dwaddr(mem_addr_o'range)) - unsigned(MEM_ADDR_START));
  evr_params_o                <= (event_numbers, event_enable, cs_min_cnt, cs_min_time, cs_timeout_cnt);
  evr_evt_rec_control_o       <= (er_event_number, er_event_enable, er_data_ack(3), er_error_ack(3));
  mgt_reset_o                 <= mgt_reset;
  evr_latency_measure_ctrl_o  <= (event_nr => lat_event_nr, counter_arm => lat_counter_arm, auto_arm => lat_counter_autoarm);
  mgt_control_o               <= mgt_control;
  usr_control_o               <= usr_control;
  evr_CfgAck                  <= evr_CfgAckLoc;
  extra_events_o              <= extra_events;

  -- --------------------------------------------------------------------------
  -- add CDC output
  -- --------------------------------------------------------------------------
  block_cdc_evr_puls_param : block
    constant c_D_N : positive := evr_puls_delay_cfg_s'length;
    constant c_D_W : positive := evr_puls_delay_cfg_s(0)'length;
    constant c_D_V : positive := c_D_N * c_D_W;
    constant c_W_N : positive := evr_puls_width_cfg_s'length;
    constant c_W_W : positive := evr_puls_width_cfg_s(0)'length;
    constant c_W_V : positive := c_W_N * c_W_W;
    signal input_s, output_s : std_logic_vector(c_D_V + c_W_V - 1 downto 0);
  begin
    -- ------------------------------------------------------------------------
    -- Map Input/Output
    -- ------------------------------------------------------------------------
    --** pulse delay parameters **
    GEN_IN_DELAY : for i in 0 to evr_puls_delay_cfg_s'length - 1 generate
      constant c_D_IDX : natural := i * c_D_W;
    begin
      input_s( c_D_IDX + c_D_W - 1 downto c_D_IDX ) <= evr_puls_delay_cfg_s(i);
      evr_pulse_delay_o(i)                          <= output_s(c_D_IDX + c_D_W - 1 downto c_D_IDX);
    end generate GEN_IN_DELAY;

    GEN_IN_WIDTH : for i in 0 to evr_puls_width_cfg_s'length - 1 generate
      constant c_W_IDX : natural := c_D_V + i*c_W_W;
    begin
      input_s( c_W_IDX + c_W_W - 1 downto c_W_IDX ) <= evr_puls_width_cfg_s(i);
      evr_pulse_width_o(i)                          <= output_s(c_W_IDX + c_W_W - 1 downto c_W_IDX);
    end generate GEN_IN_WIDTH;

    -- Instance
    inst_cdc_fast_stat : entity work.psi_common_status_cc
      generic map(DataWidth_g => input_s'length)
      port map(ClkA   => bus_CLK,
               RstInA => bus_RESET,
               DataA  => input_s,
               ClkB   => evr_clk_i,
               RstInB => evr_rst_i,
               DataB  => output_s);
  end block;

end architecture rtl;
