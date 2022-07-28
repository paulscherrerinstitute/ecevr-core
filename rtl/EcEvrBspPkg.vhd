library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package EcEvrBspPkg is

   type Lan9254ImageType is (HBI16M, SPI_GPIO, DIGIO);

   type BspSpiType is record
      sclk : std_logic;
      mosi : std_logic;
      miso : std_logic;
      csel : std_logic;
   end record BspSpiType;

   constant BSP_SPI_INIT_C : BspSpiType := (
      sclk => '0',
      mosi => '0',
      miso => '0',
      csel => '1'
   );

   type BspSpiArray is array (integer range <>) of BspSpiType;

   component XilIOBuf is
      generic (
         W_G        : natural
      );
      port (
         io         : inout std_logic_vector(W_G - 1 downto 0);
         i          : in    std_logic_vector(W_G - 1 downto 0) := (others => '0');
         t          : in    std_logic_vector(W_G - 1 downto 0) := (others => '1');
         o          : out   std_logic_vector(W_G - 1 downto 0)
      );
   end component XilIOBuf;

end package EcEvrBspPkg;
