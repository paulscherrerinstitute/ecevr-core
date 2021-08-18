library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity ZynqIOBuf is
   generic (
      W_G        : integer;
      SLEW       : string := "";
      IOSTANDARD : string := ""
   );
   port (
      io         : inout std_logic_vector(W_G - 1 downto 0);
      i          : in    std_logic_vector(W_G - 1 downto 0) := (others => '0');
      t          : in    std_logic_vector(W_G - 1 downto 0) := (others => '1');
      o          : out   std_logic_vector(W_G - 1 downto 0)
   );
end entity ZynqIOBuf;

architecture rtl of ZynqIOBuf is
begin
   GEN_BUF : for x in W_G - 1 downto 0 generate
      U_BUF : IOBUF
         generic map (
            SLEW       => SLEW,
            IOSTANDARD => IOSTANDARD
         )
         port map (
            IO => io(x),
            I  => i (x),
            T  => t (x),
            O  => O (x)
         );
   end generate GEN_BUF;
end architecture rtl;
