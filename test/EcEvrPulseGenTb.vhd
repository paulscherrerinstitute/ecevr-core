library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Evr320ConfigPkg.all;

entity EcEvrPulseGenTb is
end entity EcEvrPulseGenTb;

architecture sim of EcEvrPulseGenTb is
   signal clk          : std_logic := '0';
   signal cfg          : Evr320PulseGenConfigType := EVR320_PULSE_GEN_CONFIG_INIT_C;
   signal cod          : std_logic_vector(7 downto 0) := (others => '0');
   signal vld          : std_logic := '0';
   signal pul          : std_logic;
   signal run          : boolean := true;

   procedure tick is begin wait until rising_edge(clk); end procedure tick;

   procedure schParams(signal c : inout Evr320PulseGenConfigType; constant d,w: natural) is
   begin
      c <= c;
      c.pulseDelay <= std_logic_vector(to_unsigned(d, c.pulseDelay'length));
      c.pulseWidth <= std_logic_vector(to_unsigned(w, c.pulseWidth'length));
   end procedure schParams;

begin

   P_CLK : process is begin
      if ( run ) then
         wait for 10 ns;
         clk <= not clk;
      else
         wait;
      end if;
   end process P_CLK;

   P_TST : process is
      variable stg : natural := 0;
   begin
      tick;
      assert pul = '0' report "pulse not zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;
      schParams(cfg, 0, 0);
      cfg.pulseEvent <= x"01";
      cfg.pulseEnbld <= '1';
      cod            <= x"01";
      for i in 1 to 4 loop
      tick;
      assert pul = '0' report "pulse not zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;
      end loop;
      vld <= '1';
      tick;
      vld <= '0';
      for i in 1 to 4 loop
      assert pul = '0' report "pulse not zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;
      tick;
      end loop;
      schParams(cfg, 0, 1);
      tick;
      vld <= '1';
      assert pul = '0' report "pulse not zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;
      tick;
      vld <= '0';
      tick;
      assert pul = '1' report "pulse zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;
      tick;
      assert pul = '0' report "pulse not zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;

      tick;
      schParams(cfg, 1, 2);
      tick;
      vld <= '1';
      assert pul = '0' report "pulse not zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;
      tick;
      vld <= '0';
      assert pul = '0' report "pulse not zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;
      tick;
      assert pul = '0' report "pulse not zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;
      tick;
      assert pul = '1' report "pulse zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;
      tick;
      assert pul = '1' report "pulse zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;
      tick;
      assert pul = '0' report "pulse not zero (" & integer'image(stg) & ")" severity failure; stg := stg + 1;
 
      report "TEST PASSED";
      run <= false;
      wait;
   end process P_TST;

   U_DUT : entity work.EcEvrPulseGen
   port map (
      clk         => clk,
      rst         => open,

      event_code  => cod,
      event_vld   => vld,

      pulse_out   => pul,

      config      => cfg
   );
end architecture sim;
