library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.ESCBasicTypesPkg.all;
use     work.Lan9254Pkg.all;
use     work.EEPROMConfigPkg.all;
use     work.EvrTxPDOPkg.all;

entity EEPROMConfiguratorTb is
end entity EEPROMConfiguratorTb;

architecture sim of EEPROMConfiguratorTb is

   constant SIZE_BYTES_C         : natural   := 1024;
   constant MAX_TXPDO_MAPS_C     : natural   := 16;

   signal clk                    : std_logic := '0';
   signal rst                    : std_logic := '1';

   signal sda                    : std_logic;
   signal scl                    : std_logic;
   signal scl_m_o                : std_logic;
   signal scl_m_t                : std_logic;
   signal sda_m_o                : std_logic;
   signal sda_m_t                : std_logic;
   signal scl_s_o                : std_logic := '1';
   signal sda_s_o                : std_logic := '1';

   signal run                    : boolean := true;

   signal ack                    : EEPROMConfigAckType := EEPROM_CONFIG_ACK_ASSERT_C;
   signal cfg                    : EEPROMConfigReqType;

   signal dbufMaps               : MemXferArray(MAX_TXPDO_MAPS_C - 1 downto 0);

   function toSlv(x : in Slv08Array) return std_logic_vector is
      variable v : std_logic_vector(8*x'length - 1 downto 0);
   begin
      for i in 0 to x'length - 1 loop
         v(8*i+7 downto 8*i) := x(x'low + i);
      end loop;
      return v;
   end function toSlv;

   constant EEPROM_INIT_C : Slv08Array(SIZE_BYTES_C - 1 downto 0) := (

      64     => x"51",
      65     => x"00",
      66     => std_logic_vector( to_unsigned( (80 - 64 - 4) / 2, 8 ) ),
      67     => x"00",
      68     => x"80",
      69     => x"10",
      70     => x"01",
      71     => x"00",

      80     => x"50",
      81     => x"00",
      82     => std_logic_vector( to_unsigned( (128 - 80 - 2*4) / 2, 8 ) ),
      83     => x"00",
      84     => x"00",
      85     => x"aa",
      86     => x"21",
      87     => x"43",
      
      124    => x"01", -- category header
      125    => x"00", -- 
      126    => x"20", -- size (words)
      127    => x"00", -- 
      
      128    => x"56",
      129    => x"01",
      130    => x"02",
      131    => x"03",
      132    => x"04",
      133    => x"05",
      
      134    => x"0a",
      135    => x"0b",
      136    => x"0c",
      137    => x"0d",

      138    => x"40",
      139    => x"50",

      146    => x"04",
      147    => x"20",
      148    => x"ef",
      149    => x"be",

      154    => x"00",
      155    => x"01",
      156    => x"fe",
      157    => x"ca",
      others => x"FF"
   );

begin

   sda <= (sda_m_t or sda_m_o) and sda_s_o;
   scl <= (scl_m_t or scl_m_o) and scl_s_o;

   P_CLK : process is
   begin
      if ( run ) then
         wait for 1.25 us;
         clk <= not clk;
      else
         wait;
      end if;
   end process P_CLK;

   P_DRV : process is
   begin
      wait until rising_edge( clk );
      wait until rising_edge( clk );
      wait until rising_edge( clk );
      rst <= '0';
      wait until rising_edge( clk );
      wait;
   end process P_DRV;

   P_DON : process (clk) is
   begin
      if ( rising_edge( clk ) ) then
         if ( cfg.net.macAddrVld = '1' ) then
            report "MAC: " & toString( cfg.net.macAddr );
         end if;
         if ( cfg.net.ip4AddrVld = '1' ) then
            report "IP4: " & toString( cfg.net.ip4Addr );
         end if;
         if ( cfg.net.udpPortVld = '1' ) then
            report "UDP: " & toString( cfg.net.udpPort );
         end if;
         if ( cfg.esc.valid = '1' ) then
            report "NMAPS:   " & integer'image( cfg.txPDO.numMaps );
            report "SM2 LEN: " & toString( cfg.esc.sm2Len );
            report "SM3 LEN: " & toString( cfg.esc.sm3Len );
            for j in 0 to cfg.txPDO.numMaps - 1 loop
               report "MAP " & integer'image(j) & " : off " & toString( dbufMaps(j).off )
                                                & " : swp " & toString( dbufMaps(j).swp )
                                                & " : num " & toString( dbufMaps(j).num );
            end loop;
            report "DONE";
            run <= false;
         end if;
      end if;
   end process P_DON;

   U_EEP : entity work.I2CEEPROM
      generic map (
         SIZE_BYTES_G  => SIZE_BYTES_C,
         EEPROM_INIT_G => toSlv( EEPROM_INIT_C )
      )
      port map (
         clk       => clk,
         rst       => rst,

         sclSync   => scl,
         sdaSync   => sda,
         sdaOut    => sda_s_o
      );

   -- ClockFrequency_g must be >= 12*I2cFrequency_g
   -- otherwise spurious arbitration-lost will be detected
   -- (probably due to synchronizer delays)
   U_DUT : entity work.EEPROMConfigurator
      generic map (
         CLOCK_FREQ_G               => 5.0e5,
         I2C_FREQ_G                 => 4.0e4,
         EEPROM_OFFSET_G            => 0, --128,
         EEPROM_SIZE_G              => (8*SIZE_BYTES_C),
         MAX_TXPDO_MAPS_G           => MAX_TXPDO_MAPS_C,
         I2C_ADDR_G                 => "1010101"
      )
      port map (
         clk             => clk,
         rst             => rst,

         dbufMaps        => dbufMaps,
         configReq       => cfg,
         configAck       => ack,

         i2cSclInp       => scl,
         i2cSclOut       => scl_m_o,
         i2cSclHiZ       => scl_m_t,

         i2cSdaInp       => sda,
         i2cSdaOut       => sda_m_o,
         i2cSdaHiZ       => sda_m_t
      );
end architecture sim;

