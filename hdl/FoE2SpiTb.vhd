library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.ESCBasicTypesPkg.all;
use     work.Lan9254Pkg.all;
use     work.ESCFoEPkg.all;
use     work.FoE2SpiPkg.all;

entity FoE2SpiTb is
end entity FoE2SpiTb;

architecture Sim of FoE2SpiTb is
  constant W_C  : natural  := 8;
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal cnt : natural   := 0;
  signal don : boolean   := false;


  signal foeMst : FoEMstType := FOE_MST_INIT_C;
  signal foeSub : FoESubType := FOE_SUB_ASSERT_C;

  signal ser : std_logic;
begin

  P_CLK : process is
  begin
    if ( don ) then
      wait;
    else
      wait for 10 ns;
      clk <= not clk;
    end if;
  end process;

  foeMst.strmMst.data <= std_logic_vector( to_unsigned(cnt, 16 ) );
  foeMst.strmMst.ben  <= "01";
  foeMst.strmMst.usr  <= (others => '0');

  P_CTL : process (clk ) is
  begin
    if ( rising_edge( clk ) ) then
       if ( (foeMst.strmMst.valid and foeSub.strmRdy and foeMst.strmMst.last ) = '1' ) then
          foeMst.strmMst.valid <= '0';
       end if;
       if ( ( foeMst.doneAck and foeSub.done ) = '1' ) then
          foeMst.doneAck <= '0';
          don            <= true;
       end if;
       if    ( cnt = 1 ) then
          rst <= '0';
          foeMst.doneAck <= '1';
       elsif    ( cnt = 3 ) then
          foeMst.strmMst.valid <= '1';
       elsif ( cnt = 8 ) then
          foeMst.strmMst.last  <= '1';
       end if;
       if ( foeMst.strmMst.valid = '0' or foeSub.strmRdy = '1' ) then
          cnt <= cnt + 1;
       end if;
    end if;
  end process P_CTL;


  U_DUT : entity work.FoE2Spi
    generic map (
      FILE_MAP_G          => (
         0 => (
            id       => x"00",
            begAddr  => x"000000",
            endAddr  => x"00000F"
              )
      ),
      CLOCK_FREQ_G   => 20.0E6,
      LD_ERASE_BLK_SIZE_G => 2,
      LD_PAGE_SIZE_G      => 2,
      EN_SIM_G            => true
    )
    port map (
      clk     => clk,
      rst     => rst,

      foeMst  => foeMst,
      foeSub  => foeSub,

      miso    => ser,
      mosi    => open
    );

    ser <= '0'; -- fake non-busy

end architecture Sim;
