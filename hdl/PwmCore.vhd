library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity PwmCore is
   generic (
      SYS_CLK_FREQ_G      : real;
      PWM_FREQ_G          : real    := 1.0E3;
      PWM_WIDTH_G         : natural := 8
   );
   port (
      clk                 : in  std_logic;
      rst                 : in  std_logic;

      pw                  : in  unsigned(PWM_WIDTH_G - 1 downto 0);

      pwmOut              : out std_logic
   );
end entity PwmCore;

architecture Impl of PwmCore is

   function f return natural is
      variable presc : natural;
   begin
      return presc;
   end function f;

   constant PRESC_C   :  integer := integer( round ( SYS_CLK_FREQ_G / ( PWM_FREQ_G * real(2**PWM_WIDTH_G) ) ) );
   subtype  PrescType is integer range 0 to PRESC_C - 1;

   signal presc       : PrescType := 0;

   signal cen         :  boolean := true;

   constant MAX_C     :  natural := 2**PWM_WIDTH_G - 1;

   signal count       :  natural range 0 to MAX_C := 0;

begin


   G_PRESC : if ( PrescType'high > PrescType'low ) generate

      P_PRESC : process( clk ) is
      begin
         if ( rising_edge( clk ) ) then
            if ( rst = '1' ) then
               presc <= 0;
            else
               if ( presc = 0 ) then
                  presc <= PRESC_C - 1; 
               else
                  presc <= presc - 1;
               end if;
            end if;
         end if;
      end process P_PRESC;

      cen <= (presc = 0);

   end generate G_PRESC;

   P_PWM : process( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            count <= 0;
         else
            if ( cen )  then
               if ( count = 0 ) then
                  count <= MAX_C - 1;
               else
                  count <= count - 1;
               end if;
            end if;
         end if;
      end if;
   end process P_PWM;

   P_OUT : process ( count, pw ) is
   begin
      if ( count < to_integer( unsigned( pw ) ) ) then
         pwmOut <= '1';
      else
         pwmOut <= '0';
      end if;
   end process P_OUT;

end architecture Impl;
