library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package EcEvrBspPkg is

   type Lan9254ImageType is (HBI16M, SPI_GPIO, DIGIO);

   type BspSpiMstType is record
      sclk : std_logic;
      mosi : std_logic;
      csel : std_logic;
      util : std_logic_vector(1 downto 0);
   end record BspSpiMstType;

   type BspSpiSubType is record
      miso : std_logic;
   end record BspSpiSubType;


   constant BSP_SPI_MST_INIT_C : BspSpiMstType := (
      sclk => '0',
      mosi => '0',
      csel => '1',
      util => (others => '0')
   );

   constant BSP_SPI_SUB_INIT_C : BspSpiSubType := (
      miso => '1'
   );


   type BspSpiMstArray is array (integer range <>) of BspSpiMstType;
   type BspSpiSubArray is array (integer range <>) of BspSpiSubType;

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

   constant NUM_I2C_C     : natural := 2;
   constant EEP_I2C_IDX_C : natural := 0;
   constant SFP_I2C_IDX_C : natural := 1;
   constant PLL_I2C_IDX_C : natural := 1;

end package EcEvrBspPkg;
