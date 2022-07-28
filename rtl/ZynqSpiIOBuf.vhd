library ieee;
use ieee.std_logic_1164.all;

use work.ZynqBspPkg.all;

library unisim;
use unisim.vcomponents.all;

entity ZynqSpiIOBuf is
   generic (
      NUM_SPI_SS_G : natural range 0 to SPI_MAX_SS_C := 1 -- how many SS buffers to instantiate
   );

   port (
      io     : inout ZynqSpiType;
      ioSS   : inout std_logic_vector(NUM_SPI_SS_G - 1 downto 0);

      i      : in    ZynqSpiOutType;
      o      : out   ZynqSpiType;
      o_ss0  : out   std_logic_vector(SPI_MAX_SS_C - 1 downto 0) := (others => '1')
   );
end entity ZynqSpiIOBuf;

architecture rtl of ZynqSpiIOBuf is

   signal ss_d : std_logic_vector(NUM_SPI_SS_G - 1 downto 0);

begin
   U_SPI_SCLK_BUF : component IOBUF
      port map (
         IO => io.sclk,
         I  => i.o.sclk,
         T  => i.t.sclk,
         O  => o.sclk
      );     

   U_SPI_MOSI_BUF : component IOBUF
      port map (
         IO => io.mosi,
         I  => i.o.mosi,
         T  => i.t.mosi,
         O  => o.mosi
      );     

   U_SPI_MISO_BUF : component IOBUF
      port map (
         IO => io.miso,
         I  => i.o.miso,
         T  => i.t.miso,
         O  => o.miso
      );

   GEN_SS_BUF : for inst in ioSS'range generate

      signal ss_t : std_logic;

   begin

      ss_t <= i.t_ss0 when inst = 0 else '0';

   U_SPI_SS_BUF : component IOBUF
      port map (
         IO => ioSS(inst),
         I  => i.o_ss(inst),
         T  => ss_t,
         O  => o_ss0(inst)
      );

   end generate GEN_SS_BUF;

end architecture rtl;
