library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity ClockMeasureTb is
end entity ClockMeasureTb;

architecture sim of ClockMeasureTb is
  constant REF_FREQ_C : real      := 0500.0;
  constant MSR_FREQ_C : real      := 1428.0;
  constant MAXW_C     : natural   := 11;
  signal refClk       : std_logic := '0';
  signal msrClk       : std_logic := '0';
  signal hiRes        : std_logic := '0';

  signal f            : unsigned(MAXW_C - 1 downto 0);
  signal v            : std_logic;

  signal run          : boolean   := true;

  signal state        : natural   := 0;
begin

  P_CLK : process is
  begin
    if ( run ) then
       wait for 0.5 sec / MSR_FREQ_C;
       msrClk <= not msrClk;
    else
       wait;
    end if;
  end process P_CLK;

  P_REF : process is
  begin
    if ( run ) then
       wait for 0.5 sec / REF_FREQ_C;
       refClk <= not refClk;
    else
       wait;
    end if;
  end process P_REF;

  P_MEAS : process ( refClk ) is
    variable tst : integer;
  begin
    if ( rising_edge( refClk ) ) then
      if ( v = '1' ) then
         tst   := to_integer( f );
         state <= state + 1;
         case ( state ) is
           when 2 =>
              assert tst >= 1424 and tst <= 1440 report "TEST FAILED - Lo-res result not acceptable" severity failure;
              hiRes <= '1';
           when 8  =>
              assert tst = 1428 report "TEST FAILED - Lo-res result not acceptable" severity failure;
           when 10 =>
              run <= false;
              report "TEST PASSED";
           when others =>
         end case;
         report integer'image( to_integer( f ) );
      end if;
    end if;
  end process P_MEAS;
 
  U_DUT : entity work.ClockMeasure
     generic map (
        REF_FREQUENCY_G   => REF_FREQ_C,
        MEAS_FREQ_WIDTH_G => MAXW_C
     )
     port map (
        measClk           => msrClk,
        refClk            => refClk,
        hiRes             => hiRes,
        freqOut           => f,
        freqVldOut        => v
     );
end architecture sim;
