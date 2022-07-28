library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

use work.ZynqBspPkg.all;

entity ZynqOBufDS is
   generic (
      W_G        : natural;
      IOSTANDARD : string;
      SLEW       : string := ""
   );
   port (
      o          : out   ZynqDiffArray   (W_G - 1 downto 0);
      i          : in    std_logic_vector(W_G - 1 downto 0)
   );
end entity ZynqOBufDS;

architecture rtl of ZynqOBufDS is
begin
   GEN_BUF : for x in o'range generate
      U_BUF : OBUFDS
         generic map (
            IOSTANDARD => IOSTANDARD,
            SLEW       => SLEW
         )
         port map (
            O   => o(x).x,
            OB  => o(x).b,
            I   => i(x)
         );
   end generate GEN_BUF;
end architecture rtl;
