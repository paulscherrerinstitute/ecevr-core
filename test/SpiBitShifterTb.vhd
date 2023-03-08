library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

entity SpiBitShifterTb is
end entity SpiBitShifterTb;

architecture Sim of SpiBitShifterTb is
  constant W_C  : natural  := 8;
  constant D2_C : positive := 10;
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal csb : std_logic := '1';
  signal din : std_logic_vector(W_C - 1 downto 0);
  signal dou : std_logic_vector(W_C - 1 downto 0);
  signal sin, sou, rin, vou: std_logic;
  signal rou : std_logic := '0';
  signal vin : std_logic := '0';
  signal cnt : natural := 10;
  signal don : boolean := false;
  signal bcn : natural := 0;
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
      if ( (vin and rin) = '1' ) then
        vin <= '0';
      end if;
      if ( (vou and rou) = '1' ) then
        bcn <= bcn + 1;
        rou <= '0';
        if ( csb = '1' ) then
          don <= true;
        else
          if ( bcn = 2 ) then
            csb <= '1';
            din <= x"ff";
          else
            din <= std_logic_vector( to_unsigned( bcn, W_C ) );
          end if;
          vin <= '1';
          rou <= '1';
        end if;
      end if;
      if ( cnt > 0 ) then
        cnt <= cnt - 1;
        if ( cnt = 8 ) then
          rst <= '0';
        elsif ( cnt = 5 ) then
          vin <= '1';
          rou <= '1';
          csb <= '0';
          din <= x"a5";
        end if;
      end if;
    end if;
  end process P_CTL;

  U_DUT : entity work.SpiBitShifter
    generic map (
      WIDTH_G => W_C,
      DIV2_G  => D2_C
    )
    port map (
      clk     => clk,
      rst     => rst,

      csbInp  => csb,
      datInp  => din,
      vldInp  => vin,
      rdyInp  => rin,

      datOut  => dou,
      vldOut  => vou,
      rdyOut  => rou,

      serInp  => sin,
      serOut  => sou
    );

  sin <= sou;
end architecture Sim;
