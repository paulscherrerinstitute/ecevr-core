-- mapping of LAN9254 pins to 'fpga' array as labeled in the board schematics
-- these are then wired to FPGA-specific pins.

library ieee;
use ieee.std_logic_1164.all;

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.EcEvrBspPkg.all;

entity EcEvrBoardMap is
  port (
    sysClk          : in  std_logic;
    sysRst          : in  std_logic;

    imageSel        : in  Lan9254ImageType := HBI16M;

    fpga_i          : in  std_logic_vector(43 downto 0);
    fpga_o          : out std_logic_vector(43 downto 0) := (others => '0');
    fpga_t          : out std_logic_vector(43 downto 0) := (others => '1');

    spiMst          : in  BspSpiType := BSP_SPI_INIT_C;
    -- provides readback of sck/sdo/scs from digital io
    spiSub          : out BspSpiType;

    -- GPIO direction must match setup in EEPROM!
    gpio_i          : out std_logic_vector(31 downto 0);
    gpio_o          : in  std_logic_vector(31 downto 0) := (others => '0');
    gpio_t          : in  std_logic_vector(31 downto 0) := (others => '1');

    -- DIGIO signals
    dioSOF          : out std_logic;
    dioEOF          : out std_logic;
    dioWdState      : out std_logic;
    dioLatchIn      : in  std_logic := '0';
    dioOeExt        : in  std_logic := '1';
    dioWdTrig       : out std_logic;
    dioOutValid     : out std_logic;

    lan9254_hbiOb   : in  Lan9254HBIOutType := LAN9254HBIOUT_INIT_C;
    lan9254_hbiIb   : out Lan9254HBIInpType := LAN9254HBIINP_INIT_C;
    lan9254_irq     : out std_logic;
    lan9254_rst     : in  std_logic;

    ec_SYNC         : out std_logic_vector(1 downto 0);
    ec_LATCH        : in  std_logic_vector(1 downto 0)
  );
end entity EcEvrBoardMap;

architecture Impl of EcEvrBoardMap is

  signal irq_i      : std_logic;
  type   IntArray is array (natural range<>) of integer;

  constant DIGIO_MAP_C : IntArray := (
         0 => 35,
         1 => 36,
         2 => 37,
         3 => 39,
         4 => 18,
         5 => 17,
         6 => 16,
         7 =>  9,
         8 =>  8,
         9 => 27,
        10 => 23,
        11 => 20,
        12 => 21,
        13 => 22,
        14 => 24,
        15 => 25,
        16 =>  2,
        17 =>  3,
        18 =>  6,
        19 =>  7,
        20 => 12,
        21 => 13,
        22 => 14,
        23 => 26,
        24 => 28,
        25 => 30,
        26 => 31,
        27 => 32,
        28 => 33,
        29 => 41,
        30 => 42,
        31 => 43
  );

  constant HBI_MAP_C : IntArray := (
         0 => 10,
         1 =>  5,
         2 =>  4,
         3 => 34,
         4 => 39,
         5 => 40,
         6 => 35,
         7 => 36,
         8 => 37,
         9 => 15,
        10 => 18,
        11 => 17,
        12 => 16,
        13 =>  9,
        14 =>  8,
        15 => 27
  );

begin

  -----------------------
  -- From lan9254 -> FPGA
  -----------------------

  -- IRQ synchronization

  U_SYNC_IRQ : entity work.SynchronizerBit
    generic map (
      RSTPOL_G   => not EC_IRQ_ACT_C
    )
    port map (
      clk        => sysClk,
      rst        => sysRst,
      datInp(0)  => fpga_i(38),
      datOut(0)  => irq_i
    );

  -- inbound mappings
  P_LAN_2_FPGA : process ( imageSel, fpga_i, irq_i ) is
  begin
    -- set defaults
    spiSub        <= BSP_SPI_INIT_C;
    gpio_i        <= (others => '0');
    dioSOF        <= '0';
    dioEOF        <= '0';
    dioWdState    <= '0';
    dioWdTrig     <= '0';
    dioOutValid   <= '0';
    lan9254_hbiIb <= LAN9254HBIINP_INIT_C;
    lan9254_irq   <= '0';

    if ( imageSel /= DIGIO ) then
      lan9254_irq <= irq_i;
    end if;

    -- SYNC - NOTE: SYNC must be enabled for this mapping
    --              to be active (reg. 0x151)
    ec_SYNC(1)            <= fpga_i(11);
    ec_SYNC(0)            <= fpga_i(29);
    case ( imageSel ) is

      when HBI16M =>

        for i in lan9254_hbiIb.ad'range loop
          lan9254_hbiIb.ad(i) <= fpga_i( HBI_MAP_C( i ) );
        end loop;

        lan9254_hbiIb.waitAck <= fpga_i(0);

      when SPI_GPIO | DIGIO =>
        for i in 0 to 15 loop
          gpio_i(i) <= fpga_i( DIGIO_MAP_C( i ) );
        end loop;

        if ( imageSel = SPI_GPIO ) then
          spiSub.mosi <= fpga_i(10);
          spiSub.sclk <= fpga_i(15);
          spiSub.miso <= fpga_i( 5);
          spiSub.csel <= fpga_i(40);
        else
          for i in 16 to 31 loop
            gpio_i(i) <= fpga_i( DIGIO_MAP_C( i ) );
          end loop;
          dioSOF      <= fpga_i( 4);
          dioEOF      <= fpga_i( 5);
          dioWdState  <= fpga_i(10);
          dioWdTrig   <= fpga_i(34);
          dioOutValid <= fpga_i(40);
        end if;
    end case;
  end process P_LAN_2_FPGA;

  -----------------------
  -- From FPGA -> lan9254
  -----------------------

  P_FPGA_2_LAN : process (
      imageSel,
      spiMst,
      gpio_o,
      gpio_t,
      dioLatchIn,
      dioOeExt,
      lan9254_hbiOb,
      lan9254_rst,
      ec_LATCH
    ) is
  begin
    -- set defaults

    fpga_t <= (others => '1');
    fpga_o <= (others => '0');

    -- RST#
    fpga_o(1)            <= lan9254_rst;
    fpga_t(1)            <= '0';

    -- LATCH mapping (requires EEPROM reg 0x151 to enable SYNC0/SYNC1)
    if ( imageSel = DIGIO ) then
      fpga_o( 0)           <= ec_LATCH(0);
      fpga_t( 0)           <= '0';
      fpga_o(38)           <= ec_LATCH(1);
      fpga_t(38)           <= '0';
    else
      fpga_o(42)           <= ec_LATCH(0);
      fpga_t(42)           <= '0';
      fpga_o(43)           <= ec_LATCH(1);
      fpga_t(43)           <= '0';
    end if;

    case ( imageSel ) is

      when HBI16M =>

        for i in lan9254_hbiOb.ad'range loop
          fpga_o( HBI_MAP_C( i ) ) <= lan9254_hbiOb.ad(i);
          fpga_t( HBI_MAP_C( i ) ) <= lan9254_hbiOb.ad_t(0);
        end loop;

        fpga_o(22)           <= lan9254_hbiOb.cs;
        fpga_t(22)           <= '0';
        
        fpga_o(21)           <= lan9254_hbiOb.be(1);
        fpga_t(21)           <= '0';
        
        fpga_o(20)           <= lan9254_hbiOb.be(0);
        fpga_t(20)           <= '0';
        
        fpga_o(25)           <= lan9254_hbiOb.rs;
        fpga_t(25)           <= '0';
        
        fpga_o(24)           <= lan9254_hbiOb.ws;
        fpga_t(24)           <= '0';
        
        fpga_o(19)           <= lan9254_hbiOb.ale(0);
        fpga_t(19)           <= '0';

      when SPI_GPIO | DIGIO =>
        for i in 0 to 15 loop
          fpga_o( DIGIO_MAP_C( i ) ) <= gpio_o(i);
          fpga_t( DIGIO_MAP_C( i ) ) <= gpio_t(i);
        end loop;

        if ( imageSel = SPI_GPIO ) then
          fpga_o(10) <= spiMst.mosi;
          fpga_o(10) <= '0';
          fpga_o(15) <= spiMst.sclk;
          fpga_o(15) <= '0';
          fpga_o(40) <= spiMst.csel;
          fpga_o(40) <= '0';
        else
          for i in 16 to 31 loop
            fpga_o( DIGIO_MAP_C( i ) ) <= gpio_o(i);
            fpga_t( DIGIO_MAP_C( i ) ) <= gpio_t(i);
          end loop;
          fpga_o(15)  <= dioLatchIn;
          fpga_t(15)  <= '0';
          fpga_o(19)  <= dioOeExt;
          fpga_t(19)  <= '0';
        end if;
    end case;
  end process P_FPGA_2_LAN;
  
end architecture Impl;
