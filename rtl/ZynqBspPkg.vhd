library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ZynqBspPkg is

   constant SPI_MAX_SS_C : positive := 3; -- max # of PS-SPI SS signals

   type ZynqSpiType is record
      sclk : std_logic;
      mosi : std_logic;
      miso : std_logic;
   end record ZynqSpiType;

   constant ZYNQ_SPI_TYPE_C : ZynqSpiType := (
      sclk => '0',
      mosi => '0',
      miso => '0'
   );

   type ZynqSpiArray is array (integer range <>) of ZynqSpiType;

   type ZynqSpiOutType is record
      o     : ZynqSpiType;
      t     : ZynqSpiType;
      o_ss  : std_logic_vector(SPI_MAX_SS_C - 1 downto 0);
      t_ss0 : std_logic;
   end record ZynqSpiOutType;

   type ZynqSpiOutArray is array (integer range <>) of ZynqSpiOutType;

   type ZynqDiffType is record
      x     : std_logic;
      b     : std_logic;
   end record ZynqDiffType;

   type ZynqDiffArray is array (integer range <>) of ZynqDiffType;

   component ZynqOBufDS is
      generic (
         W_G        : natural;
         IOSTANDARD : string;
         SLEW       : string := "SLOW"
      );
      port (
         o          : out ZynqDiffArray   (W_G - 1 downto 0);
         i          : in    std_logic_vector(W_G - 1 downto 0)
      );
   end component ZynqObufDS;

   component ZynqIOBuf is
      generic (
         W_G        : natural
      );
      port (
         io         : inout std_logic_vector(W_G - 1 downto 0);
         i          : in    std_logic_vector(W_G - 1 downto 0) := (others => '0');
         t          : in    std_logic_vector(W_G - 1 downto 0) := (others => '1');
         o          : out   std_logic_vector(W_G - 1 downto 0)
      );
   end component ZynqIOBuf;

end package ZynqBspPkg;
