library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

library unisim;
use     unisim.vcomponents.all;

use     work.ESCBasicTypesPkg.all;
use     work.Lan9254Pkg.all;
use     work.ESCFoEPkg.all;
use     work.FoE2SpiPkg.all;

entity IcapE2RegTb is
end entity IcapE2RegTb;

architecture Sim of IcapE2RegTb is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal cnt : natural   := 0;
  signal don : boolean   := false;

  signal adr  : std_logic_vector(15 downto 0) := x"000C";

  signal req  : std_logic := '0';
  signal ack  : std_logic := '0';
  signal dou  : std_logic_vector(31 downto 0);
  signal rnw  : std_logic := '1';

  signal din  : std_logic_vector(31 downto 0);

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

  P_CTL : process (clk ) is
  begin
    if ( rising_edge( clk ) ) then
       cnt <= cnt + 1; 
       if ( cnt = 200 ) then
          rst <= '0';
       end if;
    end if;
  end process P_CTL;

  P_DRV : process is
  begin
    while ( rst = '1' ) loop
      wait until rising_edge( clk );
    end loop;

    rnw <= '0';
    adr <= x"0010";
    din <= x"deadbeef";
    req <= '1';
    while ( ( req and ack ) = '0' ) loop
      wait until rising_edge( clk );
    end loop;
    rnw <= '1';
    adr <= x"000C";
    din <= x"ffff_ffff";
    wait until rising_edge( clk );
    while ( ( req and ack ) = '0' ) loop
      wait until rising_edge( clk );
    end loop;
    report "IDCODE: x" & toString(dou);
    assert dou = x"03651093" report "IDCODE mismatch" severity failure;
    adr <= x"0010";
    wait until rising_edge( clk );
    while ( ( req and ack ) = '0' ) loop
      wait until rising_edge( clk );
    end loop;
    report "WBSTAR: x" & toString(dou);
    assert dou = x"deadbeef" report "WBSTAR mismatch" severity failure;
    req <= '0';
    wait until rising_edge( clk );

    report "Test PASSED -- (won't stop; you have to abort manually) ";
    don <= true;
    wait;
  end process P_DRV;


  U_DUT : entity work.IcapE2Reg
    port map (
      clk     => clk,
      rst     => rst,

      addr    => adr,
      rdnw    => rnw,
      dInp    => din,
      req     => req,

      dOut    => dou,
      ack     => ack
    );

end architecture Sim;
